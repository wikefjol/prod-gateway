local core = require("apisix.core")
local cjson = require("cjson.safe")
local ngx_encode_base64 = ngx.encode_base64

local plugin_name = "response-wiretap"

local schema = {
    type = "object",
    properties = {
        enabled = { type = "boolean", default = true },
        max_body_bytes = { type = "integer", minimum = 1024, default = 524288 },
        log_path = { type = "string", default = "/usr/local/apisix/logs/wiretap.jsonl" },
    },
}

local _M = {
    version = 0.1,
    priority = 900,  -- Run after billing-extractor (1000)
    name = plugin_name,
    schema = schema,
}

-- Check if chunk contains non-printable bytes (binary)
local function is_binary(chunk)
    for i = 1, math.min(#chunk, 512) do
        local b = chunk:byte(i)
        -- Allow printable ASCII, tab, newline, carriage return
        if b < 32 and b ~= 9 and b ~= 10 and b ~= 13 then
            return true
        end
    end
    return false
end

function _M.access(conf, ctx)
    if not conf.enabled then
        return
    end

    -- Gate: only capture if X-Debug-Capture: 1 header present
    local debug_header = core.request.header(ctx, "X-Debug-Capture")
    if debug_header ~= "1" then
        return
    end

    ctx._wiretap_enabled = true
    ctx._wiretap_chunks = {}
    ctx._wiretap_sse_frames = {}
    ctx._wiretap_sse_buf = ""
    ctx._wiretap_total_bytes = 0
    ctx._wiretap_truncated = false

    -- Extract request metadata
    local body, _ = core.request.get_body()
    local req = body and cjson.decode(body) or {}
    ctx._wiretap_is_streaming = (req.stream == true)

    -- Detect provider from host
    local host = core.request.header(ctx, "Host") or ""
    if host:match("anthropic") then
        ctx._wiretap_provider = "anthropic"
    elseif host:match("openai") then
        ctx._wiretap_provider = "openai"
    else
        -- Infer from route URI
        local uri = ngx.var.uri or ""
        if uri:match("/v1/messages") then
            ctx._wiretap_provider = "anthropic"
        elseif uri:match("/v1/chat/completions") then
            ctx._wiretap_provider = "openai"
        else
            ctx._wiretap_provider = "unknown"
        end
    end

    ctx._wiretap_request_id = core.request.header(ctx, "X-Request-Id") or ngx.var.request_id or ""
end

-- Extract complete SSE frames from buffer, return remaining incomplete data
local function extract_sse_frames(buf, frames)
    local pos = 1
    while true do
        -- Find frame delimiter: \n\n or \r\n\r\n
        local frame_end = buf:find("\n\n", pos, true)
        local delim_len = 2
        if not frame_end then
            frame_end = buf:find("\r\n\r\n", pos, true)
            delim_len = 4
        end

        if not frame_end then
            -- No complete frame, return remainder
            return buf:sub(pos)
        end

        -- Extract frame (including delimiter for completeness)
        local frame = buf:sub(pos, frame_end + delim_len - 1)
        frames[#frames + 1] = frame
        pos = frame_end + delim_len
    end
end

function _M.body_filter(conf, ctx)
    if not ctx._wiretap_enabled then
        return
    end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]
    local max_bytes = conf.max_body_bytes or 524288

    if chunk and chunk ~= "" then
        ctx._wiretap_total_bytes = ctx._wiretap_total_bytes + #chunk

        if ctx._wiretap_total_bytes <= max_bytes then
            -- Store chunk (base64 if binary)
            local stored_chunk
            if is_binary(chunk) then
                stored_chunk = ngx_encode_base64(chunk)
                ctx._wiretap_has_binary = true
            else
                stored_chunk = chunk
            end
            ctx._wiretap_chunks[#ctx._wiretap_chunks + 1] = stored_chunk

            -- For streaming: extract SSE frames
            if ctx._wiretap_is_streaming then
                ctx._wiretap_sse_buf = ctx._wiretap_sse_buf .. chunk
                ctx._wiretap_sse_buf = extract_sse_frames(ctx._wiretap_sse_buf, ctx._wiretap_sse_frames)
            end
        else
            ctx._wiretap_truncated = true
        end
    end

    -- On EOF: flush remaining SSE buffer and extract final frames
    if eof and ctx._wiretap_is_streaming and #ctx._wiretap_sse_buf > 0 then
        -- Add remaining buffer as final frame if non-empty
        ctx._wiretap_sse_frames[#ctx._wiretap_sse_frames + 1] = ctx._wiretap_sse_buf
        ctx._wiretap_sse_buf = ""
    end
end

function _M.log(conf, ctx)
    if not ctx._wiretap_enabled then
        return
    end

    local record = {
        request_id = ctx._wiretap_request_id,
        provider = ctx._wiretap_provider,
        is_streaming = ctx._wiretap_is_streaming,
        status = ngx.status,
        content_encoding = ngx.header["Content-Encoding"] or "identity",
        raw_chunks = ctx._wiretap_chunks,
        total_bytes = ctx._wiretap_total_bytes,
        truncated = ctx._wiretap_truncated,
        is_base64 = ctx._wiretap_has_binary or false,
        timestamp = ngx.now(),
    }

    -- Only include sse_frames for streaming responses
    if ctx._wiretap_is_streaming then
        record.sse_frames = ctx._wiretap_sse_frames
    end

    local json_line = cjson.encode(record)
    if not json_line then
        core.log.error("wiretap: failed to encode record")
        return
    end

    local log_path = conf.log_path or "/usr/local/apisix/logs/wiretap.jsonl"
    local file, err = io.open(log_path, "a")
    if not file then
        core.log.error("wiretap: failed to open log file: ", err)
        return
    end

    file:write(json_line, "\n")
    file:close()
end

return _M
