-- stream-usage-injector
-- Purpose: Inject stream_options.include_usage into streaming requests so providers return token counts
-- Phase: access (inject into request body), body_filter (handle response)
-- Priority: 1000
-- Schema: { provider: "openai" | "anthropic-openai" }
-- Ctx vars set: none
-- WARNING: INACTIVE — not registered in config.yaml and not wired into any routes. Investigate before use.

local core = require("apisix.core")
local cjson = require("cjson.safe")

local plugin_name = "stream-usage-injector"

local schema = {
    type = "object",
    properties = {
        provider = {
            type = "string",
            enum = {"openai", "anthropic-openai"},
            description = "Provider type for response format handling"
        },
    },
    required = {"provider"},
}

local _M = {
    version = 0.1,
    priority = 1000,  -- Lower than billing-extractor (1100) so billing reads first
    name = plugin_name,
    schema = schema,
}

-- Check if request is streaming
local function is_streaming_request(body)
    if not body then return false end
    local req = cjson.decode(body)
    return req and req.stream == true
end

function _M.access(conf, ctx)
    local body, err = core.request.get_body()
    if not body then return end

    if not is_streaming_request(body) then return end

    local req = cjson.decode(body)
    if not req then return end

    -- Check if user already set include_usage
    local user_set = req.stream_options
        and req.stream_options.include_usage == true

    -- Anthropic-OpenAI: inject stream_options to get usage for billing, strip from response
    if conf.provider == "anthropic-openai" then
        if user_set then
            return  -- User requested usage, don't strip or inject
        end
        -- Inject stream_options so upstream returns usage (for billing)
        req.stream_options = req.stream_options or {}
        req.stream_options.include_usage = true
        ctx._strip_usage = true  -- Strip from client response

        local new_body = cjson.encode(req)
        ngx.req.set_body_data(new_body)
        ngx.req.set_header("Content-Length", #new_body)
        return
    end

    -- OpenAI: inject stream_options to get usage for billing
    if user_set then
        ctx._usage_user_requested = true
        return
    end

    -- Inject stream_options
    req.stream_options = req.stream_options or {}
    req.stream_options.include_usage = true
    ctx._usage_injected = true

    local new_body = cjson.encode(req)
    ngx.req.set_body_data(new_body)

    -- Update Content-Length header
    ngx.req.set_header("Content-Length", #new_body)
end

-- Check if SSE frame is a usage-only chunk (OpenAI format)
-- OpenAI usage chunk: choices is empty array, usage is present
local function is_usage_only_chunk(frame)
    local json_str = frame:match("^data:%s*(.+)$")
    if not json_str then return false end

    -- Strip trailing whitespace/newlines
    json_str = json_str:gsub("%s+$", "")

    if json_str == "[DONE]" then return false end

    local data = cjson.decode(json_str)
    if not data then return false end

    -- OpenAI usage chunk: choices is empty array, usage is present
    return data.choices
        and type(data.choices) == "table"
        and #data.choices == 0
        and data.usage ~= nil
end

-- Strip usage field from SSE frame (anthropic-openai - usage embedded in final chunk)
local function strip_usage_from_frame(frame)
    local json_str = frame:match("^data:%s*(.+)$")
    if not json_str then return frame end

    -- Strip trailing whitespace
    json_str = json_str:gsub("%s+$", "")
    if json_str == "[DONE]" then return frame end

    local data = cjson.decode(json_str)
    if not data or not data.usage then return frame end

    data.usage = nil
    return "data: " .. cjson.encode(data) .. "\n\n"
end

-- Strip usage field from SSE stream (anthropic-openai)
local function strip_usage_from_stream(chunk, ctx)
    ctx._sui_buf = (ctx._sui_buf or "") .. chunk

    local output = {}
    local pos = 1
    local buf = ctx._sui_buf

    while true do
        local frame_end = buf:find("\n\n", pos, true)
        if not frame_end then
            frame_end = buf:find("\r\n\r\n", pos, true)
            if frame_end then
                frame_end = frame_end + 2
            end
        end

        if not frame_end then break end

        local frame = buf:sub(pos, frame_end + 1)
        output[#output + 1] = strip_usage_from_frame(frame)

        pos = frame_end + 2
    end

    ctx._sui_buf = buf:sub(pos)

    if #ctx._sui_buf > 32768 then
        ctx._sui_buf = ctx._sui_buf:sub(-32768)
    end

    return table.concat(output)
end

-- Filter usage-only chunks from SSE stream (OpenAI - usage in separate chunk)
local function filter_usage_chunks(chunk, ctx)
    -- Buffer partial frames across chunks
    ctx._sui_buf = (ctx._sui_buf or "") .. chunk

    local output = {}
    local pos = 1
    local buf = ctx._sui_buf

    -- SSE frames end with double newline
    while true do
        -- Find end of SSE frame (double newline)
        local frame_end = buf:find("\n\n", pos, true)
        if not frame_end then
            -- Check for CRLF variant
            frame_end = buf:find("\r\n\r\n", pos, true)
            if frame_end then
                frame_end = frame_end + 2  -- Account for extra \r\n
            end
        end

        if not frame_end then break end

        local frame = buf:sub(pos, frame_end + 1)

        -- Check if this is a usage-only chunk
        if not is_usage_only_chunk(frame) then
            output[#output + 1] = frame
        end

        pos = frame_end + 2
    end

    -- Keep remaining (incomplete frame) in buffer
    ctx._sui_buf = buf:sub(pos)

    -- Safety cap on buffer (32KB)
    if #ctx._sui_buf > 32768 then
        ctx._sui_buf = ctx._sui_buf:sub(-32768)
    end

    return table.concat(output)
end

function _M.body_filter(conf, ctx)
    -- Don't touch non-2xx responses
    local status = ngx.status
    if status < 200 or status >= 300 then return end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    -- Anthropic-OpenAI: strip usage field from chunks
    if ctx._strip_usage then
        if chunk and chunk ~= "" then
            ngx.arg[1] = strip_usage_from_stream(chunk, ctx)
        end
        if eof and ctx._sui_buf and ctx._sui_buf ~= "" then
            ngx.arg[1] = (ngx.arg[1] or "") .. ctx._sui_buf
            ctx._sui_buf = ""
        end
        return
    end

    -- OpenAI: filter out usage-only chunks
    if not ctx._usage_injected then return end

    if chunk and chunk ~= "" then
        local filtered = filter_usage_chunks(chunk, ctx)
        ngx.arg[1] = filtered
    end

    if eof and ctx._sui_buf and ctx._sui_buf ~= "" then
        ngx.arg[1] = (ngx.arg[1] or "") .. ctx._sui_buf
        ctx._sui_buf = ""
    end
end

return _M
