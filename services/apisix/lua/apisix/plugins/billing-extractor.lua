local core = require("apisix.core")
local cjson = require("cjson.safe")

local plugin_name = "billing-extractor"

-- Register custom APISIX variables for file-logger log_format
core.ctx.register_var("billing_model", function(ctx)
    return ctx.billing_model or ""
end)

core.ctx.register_var("billing_provider_response_id", function(ctx)
    return ctx.billing_provider_response_id or ""
end)

core.ctx.register_var("billing_usage_json", function(ctx)
    return ctx.billing_usage_json or ""
end)

core.ctx.register_var("billing_provider", function(ctx)
    return ctx.billing_provider or ""
end)

core.ctx.register_var("billing_endpoint", function(ctx)
    return ctx.billing_endpoint or ""
end)

core.ctx.register_var("billing_is_streaming", function(ctx)
    return ctx.billing_is_streaming or "false"
end)

core.ctx.register_var("billing_usage_present", function(ctx)
    return ctx.billing_usage_present or "false"
end)

-- New extraction outcome variables
core.ctx.register_var("billing_usage_expected", function(ctx)
    return ctx.billing_usage_expected or "false"
end)

core.ctx.register_var("billing_extract_status", function(ctx)
    return ctx.billing_extract_status or ""
end)

core.ctx.register_var("billing_extract_reason", function(ctx)
    return ctx.billing_extract_reason or ""
end)

core.ctx.register_var("billing_parse_attempted", function(ctx)
    return ctx.billing_parse_attempted or "false"
end)

core.ctx.register_var("billing_truncated", function(ctx)
    return ctx.billing_truncated or "false"
end)

local schema = {
    type = "object",
    properties = {
        max_resp_body_bytes = { type = "integer", minimum = 1, default = 262144 },
        provider = { type = "string", enum = {"anthropic", "openai", "litellm"} },
        endpoint = { type = "string" },
    },
}

-- Determine if usage is expected for this request
-- Heuristic: POST with model AND (messages OR input OR prompt)
local function is_usage_expected(req, method)
    if method ~= "POST" then
        return false
    end
    if not req or not req.model then
        return false
    end
    -- Has model + generation payload = usage expected
    if req.messages or req.input or req.prompt then
        return true
    end
    return false
end

local _M = {
    version = 0.2,
    priority = 1100,  -- Higher priority: extract billing before stream-usage-injector strips it
    name = plugin_name,
    schema = schema,
}

function _M.access(conf, ctx)
    -- Set provider and endpoint from plugin config
    ctx.billing_provider = conf.provider or ""
    ctx.billing_endpoint = conf.endpoint or ""

    local body, err = core.request.get_body()
    if not body then
        ctx.billing_is_streaming = "false"
        ctx.billing_usage_expected = "false"
        return
    end

    local req = cjson.decode(body)
    if not req then
        ctx.billing_is_streaming = "false"
        ctx.billing_usage_expected = "false"
        return
    end

    ctx.billing_model = req.model or ""

    -- Detect streaming request
    if req.stream == true then
        ctx.billing_is_streaming = "true"
    else
        ctx.billing_is_streaming = "false"
    end

    -- Determine if usage is expected
    ctx.billing_usage_expected = is_usage_expected(req, ngx.req.get_method()) and "true" or "false"
end

-- Process a single SSE data line and extract billing info
local function process_sse_line(line, ctx)
    -- Strip \r if present (handle CRLF)
    line = line:gsub("\r$", "")

    -- Only process "data:" lines, ignore "event:" and empty lines
    if not line:match("^data:") then
        return
    end

    -- Extract JSON after "data: "
    local json_str = line:match("^data:%s*(.+)$")
    if not json_str or json_str == "[DONE]" then
        return
    end

    local data = cjson.decode(json_str)
    if not data then
        ctx._billing_had_parse_error = true
        ctx._billing_parse_error_reason = "json_decode_failed"
        return
    end

    -- Extract ID (overwrite if found - most providers send ID in every chunk)
    if data.id and data.id ~= "" then
        ctx.billing_provider_response_id = data.id
    end
    -- Also check nested: data.message.id (Anthropic message_start)
    if data.message and data.message.id and data.message.id ~= "" then
        ctx.billing_provider_response_id = data.message.id
    end
    -- Also check nested: data.response.id (OpenAI Responses API)
    if data.response and data.response.id and data.response.id ~= "" then
        ctx.billing_provider_response_id = data.response.id
    end

    -- Extract usage (last one wins - overwrite)
    if data.usage then
        ctx.billing_usage_json = cjson.encode(data.usage)
        ctx._billing_usage_found = true
    end
    -- Also check nested: data.response.usage (OpenAI Responses API)
    if data.response and data.response.usage then
        ctx.billing_usage_json = cjson.encode(data.response.usage)
        ctx._billing_usage_found = true
    end
end

-- Finalize streaming extraction status
local function finalize_streaming_status(ctx)
    if ctx.billing_usage_expected ~= "true" then
        ctx.billing_extract_status = "not_applicable"
        ctx.billing_extract_reason = "aux_request"
    elseif ctx._billing_usage_found then
        ctx.billing_extract_status = "captured"
        ctx.billing_extract_reason = ""
        ctx.billing_usage_present = "true"
    elseif ctx._billing_truncated then
        ctx.billing_extract_status = "truncated"
        ctx.billing_extract_reason = ctx._billing_truncate_reason or "sse_buf_limit"
    elseif ctx._billing_had_parse_error then
        ctx.billing_extract_status = "parse_error"
        ctx.billing_extract_reason = ctx._billing_parse_error_reason or "json_decode_failed"
    else
        ctx.billing_extract_status = "missing_usage"
        ctx.billing_extract_reason = "usage_field_absent"
    end

    ctx.billing_truncated = ctx._billing_truncated and "true" or "false"

    if ctx.billing_extract_status ~= "captured" then
        ctx.billing_usage_present = "false"
        ctx.billing_usage_json = ""
    end
end

-- Process streaming response with frame-based SSE parsing
local function process_streaming_chunk(conf, ctx, chunk, eof)
    ctx._sse_buf = (ctx._sse_buf or "") .. chunk
    ctx.billing_parse_attempted = "true"

    -- Process complete SSE frames (end with \n\n or \r\n\r\n)
    while true do
        local frame_end = ctx._sse_buf:find("\n\n", 1, true)
        local crlf_end = ctx._sse_buf:find("\r\n\r\n", 1, true)

        if crlf_end and (not frame_end or crlf_end < frame_end) then
            frame_end = crlf_end + 2  -- Account for extra \r\n
        end

        if not frame_end then break end

        local frame = ctx._sse_buf:sub(1, frame_end - 1)
        ctx._sse_buf = ctx._sse_buf:sub(frame_end + 2)

        -- Process data: lines within frame
        for line in frame:gmatch("[^\r\n]+") do
            process_sse_line(line, ctx)
        end
    end

    -- Buffer cap check
    if #ctx._sse_buf > 32768 then
        ctx._billing_truncated = true
        ctx._billing_truncate_reason = "sse_buf_limit"
        ctx._sse_buf = ctx._sse_buf:sub(-32768)
    end

    -- EOF: finalize status
    if eof then
        finalize_streaming_status(ctx)
    end
end

-- Finalize non-streaming extraction status
local function finalize_nonstreaming_status(ctx, resp)
    if ctx.billing_usage_expected ~= "true" then
        ctx.billing_extract_status = "not_applicable"
        ctx.billing_extract_reason = "aux_request"
        ctx.billing_truncated = "false"
        ctx.billing_usage_present = "false"
        return
    end

    if ctx._billing_truncated then
        ctx.billing_extract_status = "truncated"
        ctx.billing_extract_reason = ctx._billing_truncate_reason or "resp_body_limit"
        ctx.billing_truncated = "true"
        ctx.billing_usage_present = "false"
        ctx.billing_usage_json = ""
        ctx.billing_provider_response_id = ""
        return
    end

    if ctx._billing_had_parse_error then
        ctx.billing_extract_status = "parse_error"
        ctx.billing_extract_reason = ctx._billing_parse_error_reason or "json_decode_failed"
        ctx.billing_truncated = "false"
        ctx.billing_usage_present = "false"
        return
    end

    -- Extract ID
    if resp then
        if resp.id and resp.id ~= "" then
            ctx.billing_provider_response_id = resp.id
        elseif resp.response and resp.response.id then
            ctx.billing_provider_response_id = resp.response.id
        else
            ctx.billing_provider_response_id = ""
        end

        -- Extract usage
        local usage = resp.usage or (resp.response and resp.response.usage)
        if usage then
            ctx.billing_usage_json = cjson.encode(usage)
            ctx.billing_usage_present = "true"
            ctx.billing_extract_status = "captured"
            ctx.billing_extract_reason = ""
        else
            ctx.billing_usage_json = ""
            ctx.billing_usage_present = "false"
            ctx.billing_extract_status = "missing_usage"
            ctx.billing_extract_reason = "usage_field_absent"
        end
    else
        ctx.billing_extract_status = "missing_usage"
        ctx.billing_extract_reason = "usage_field_absent"
        ctx.billing_usage_present = "false"
    end

    ctx.billing_truncated = "false"
end

-- Process non-streaming response by buffering full body
local function process_nonstreaming_chunk(conf, ctx, chunk, eof)
    if chunk and chunk ~= "" then
        ctx._billing_resp_bytes = (ctx._billing_resp_bytes or 0) + #chunk

        if ctx._billing_resp_bytes <= (conf.max_resp_body_bytes or 262144) then
            local t = ctx._billing_resp_chunks
            if not t then
                t = {}
                ctx._billing_resp_chunks = t
            end
            t[#t + 1] = chunk
        else
            ctx._billing_resp_truncated = true
            ctx._billing_truncated = true
            ctx._billing_truncate_reason = "resp_body_limit"
        end
    end

    if not eof then
        return
    end

    ctx.billing_parse_attempted = "true"

    -- Truncated: finalize early
    if ctx._billing_truncated then
        finalize_nonstreaming_status(ctx, nil)
        return
    end

    local raw = ""
    if ctx._billing_resp_chunks then
        raw = table.concat(ctx._billing_resp_chunks)
    end

    local resp = cjson.decode(raw)
    if not resp then
        ctx._billing_had_parse_error = true
        ctx._billing_parse_error_reason = "json_decode_failed"
        finalize_nonstreaming_status(ctx, nil)
        return
    end

    finalize_nonstreaming_status(ctx, resp)
end

function _M.body_filter(conf, ctx)
    local status = ngx.status

    -- Non-2xx: upstream error, skip extraction
    if status < 200 or status >= 300 then
        ctx.billing_extract_status = "upstream_error"
        ctx.billing_extract_reason = "non_2xx_status"
        ctx.billing_parse_attempted = "false"
        ctx.billing_usage_present = "false"
        ctx.billing_truncated = "false"
        return
    end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    -- Route to appropriate handler based on streaming flag
    if ctx.billing_is_streaming == "true" then
        if chunk and chunk ~= "" then
            process_streaming_chunk(conf, ctx, chunk, false)
        end
        if eof then
            process_streaming_chunk(conf, ctx, "", true)
        end
    else
        process_nonstreaming_chunk(conf, ctx, chunk, eof)
    end
end

return _M
