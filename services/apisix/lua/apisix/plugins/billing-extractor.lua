local core = require("apisix.core")
local cjson = require("cjson.safe")

local plugin_name = "billing-extractor"

-- Register custom APISIX variables for kafka-logger log_format
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

local schema = {
    type = "object",
    properties = {
        max_resp_body_bytes = { type = "integer", minimum = 1, default = 262144 },
        provider = { type = "string", enum = {"anthropic", "openai", "litellm"} },
        endpoint = { type = "string" },
    },
}

local _M = {
    version = 0.2,
    priority = 1000,
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
        return
    end

    local req = cjson.decode(body)
    if not req then
        ctx.billing_is_streaming = "false"
        return
    end

    ctx.billing_model = req.model or ""

    -- Detect streaming request
    if req.stream == true then
        ctx.billing_is_streaming = "true"

        -- Check include_usage for OpenAI streaming requests (no longer enforced)
        if conf.provider == "openai" then
            local include_usage = req.stream_options
                and req.stream_options.include_usage == true
            if not include_usage then
                ctx.billing_usage_present = "false"
                core.log.warn("OpenAI streaming without include_usage - billing data unavailable")
            end
        end
    else
        ctx.billing_is_streaming = "false"
    end
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

    -- Extract usage (last one wins - overwrite)
    if data.usage then
        ctx.billing_usage_json = cjson.encode(data.usage)
        ctx._billing_usage_found = true
    end
end

-- Process streaming response with SSE parsing
local function process_streaming_chunk(conf, ctx, chunk, eof)
    -- Accumulate chunk into buffer
    ctx._sse_buf = (ctx._sse_buf or "") .. chunk

    -- Find last newline position
    local last_nl = ctx._sse_buf:match(".*()[\r\n]")
    if last_nl then
        -- Process complete portion (up to last newline)
        local complete = ctx._sse_buf:sub(1, last_nl)
        -- Keep tail (incomplete line) for next chunk
        ctx._sse_buf = ctx._sse_buf:sub(last_nl + 1)

        -- Process each line in complete portion
        for line in complete:gmatch("[^\r\n]+") do
            process_sse_line(line, ctx)
        end
    end

    -- Safety cap on buffer (32KB)
    if #ctx._sse_buf > 32768 then
        ctx._sse_buf = ctx._sse_buf:sub(-32768)
    end

    -- On EOF: flush remaining buffer (handles streams without trailing newline)
    if eof and ctx._sse_buf and #ctx._sse_buf > 0 then
        process_sse_line(ctx._sse_buf, ctx)
        ctx._sse_buf = ""
    end

    -- Set usage_present flag on EOF
    if eof then
        if ctx._billing_usage_found then
            ctx.billing_usage_present = "true"
        else
            ctx.billing_usage_present = "false"
            ctx.billing_usage_json = ""
        end
    end
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
        end
    end

    if not eof then
        return
    end

    if ctx._billing_resp_truncated then
        ctx.billing_provider_response_id = ""
        ctx.billing_usage_json = ""
        ctx.billing_usage_present = "false"
        return
    end

    local raw = ""
    if ctx._billing_resp_chunks then
        raw = table.concat(ctx._billing_resp_chunks)
    end

    local resp = cjson.decode(raw)
    if not resp then
        ctx.billing_usage_present = "false"
        return
    end

    ctx.billing_provider_response_id = resp.id or ""

    if resp.usage then
        ctx.billing_usage_json = cjson.encode(resp.usage) or ""
        ctx.billing_usage_present = "true"
    else
        ctx.billing_usage_json = ""
        ctx.billing_usage_present = "false"
    end
end

function _M.body_filter(conf, ctx)
    if ngx.status ~= 200 then
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
