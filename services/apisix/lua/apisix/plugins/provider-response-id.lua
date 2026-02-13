local core = require("apisix.core")
local cjson = require("cjson.safe")

local plugin_name = "provider-response-id"

local schema = {
    type = "object",
    properties = {
        max_body_bytes = {
            type = "integer",
            minimum = 1,
            default = 65536
        }
    }
}

-- Register ctx var for logging
core.ctx.register_var("provider_response_id", function(ctx)
    return ctx.provider_response_id or ""
end)

local _M = {
    version = 0.1,
    priority = 900,  -- Run after response is received, before logging
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

-- Process SSE data line to extract ID
local function extract_id_from_sse(line, ctx)
    line = line:gsub("\r$", "")

    if not line:match("^data:") then
        return
    end

    local json_str = line:match("^data:%s*(.+)$")
    if not json_str or json_str == "[DONE]" then
        return
    end

    local data = cjson.decode(json_str)
    if not data then
        return
    end

    -- OpenAI format: data.id = "chatcmpl-xxx"
    if data.id and data.id ~= "" then
        ctx.provider_response_id = data.id
    end
    -- Anthropic format: data.message.id = "msg_xxx"
    if data.message and data.message.id and data.message.id ~= "" then
        ctx.provider_response_id = data.message.id
    end
end

-- Process streaming response
local function process_streaming(conf, ctx, chunk, eof)
    ctx._prid_buf = (ctx._prid_buf or "") .. chunk

    local last_nl = ctx._prid_buf:match(".*()[\r\n]")
    if last_nl then
        local complete = ctx._prid_buf:sub(1, last_nl)
        ctx._prid_buf = ctx._prid_buf:sub(last_nl + 1)

        for line in complete:gmatch("[^\r\n]+") do
            extract_id_from_sse(line, ctx)
        end
    end

    -- Cap buffer at 16KB
    if #ctx._prid_buf > 16384 then
        ctx._prid_buf = ctx._prid_buf:sub(-16384)
    end

    if eof and ctx._prid_buf and #ctx._prid_buf > 0 then
        extract_id_from_sse(ctx._prid_buf, ctx)
        ctx._prid_buf = ""
    end
end

-- Process non-streaming response
local function process_nonstreaming(conf, ctx, chunk, eof)
    if chunk and chunk ~= "" then
        ctx._prid_bytes = (ctx._prid_bytes or 0) + #chunk

        if ctx._prid_bytes <= (conf.max_body_bytes or 65536) then
            local t = ctx._prid_chunks
            if not t then
                t = {}
                ctx._prid_chunks = t
            end
            t[#t + 1] = chunk
        end
    end

    if not eof then
        return
    end

    if not ctx._prid_chunks then
        return
    end

    local raw = table.concat(ctx._prid_chunks)
    local resp = cjson.decode(raw)
    if resp and resp.id then
        ctx.provider_response_id = resp.id
    end
end

function _M.body_filter(conf, ctx)
    if ngx.status ~= 200 then
        return
    end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    -- Detect streaming by content-type
    local ct = ngx.header["Content-Type"] or ""
    local is_streaming = ct:match("text/event%-stream")

    if is_streaming then
        if chunk and chunk ~= "" then
            process_streaming(conf, ctx, chunk, false)
        end
        if eof then
            process_streaming(conf, ctx, "", true)
        end
    else
        process_nonstreaming(conf, ctx, chunk, eof)
    end
end

return _M
