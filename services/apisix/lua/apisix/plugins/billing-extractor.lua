-- billing-extractor
-- Purpose: Parse SSE streaming responses to extract token usage and provider response ID for billing logs
-- Phase: access (capture ctx), body_filter (parse response body)
-- Priority: 1000
-- Schema: { max_resp_body_bytes: int, provider: "anthropic"|"openai"|"litellm", endpoint: str }
-- Ctx vars set: billing_model, billing_provider_response_id, billing_usage_json, billing_provider,
--               billing_endpoint, billing_is_streaming, billing_usage_present,
--               llm_model, llm_prompt_tokens, llm_completion_tokens, request_llm_model

local core = require("apisix.core")
local cjson = require("cjson.safe")
local sse_parser = require("apisix.core.sse_parser")

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

-- Unified llm_* vars (same as ai-proxy for consistent billing logs)
core.ctx.register_var("llm_model", function(ctx)
    return ctx.llm_model or ""
end)

core.ctx.register_var("llm_prompt_tokens", function(ctx)
    return ctx.llm_prompt_tokens or ""
end)

core.ctx.register_var("llm_completion_tokens", function(ctx)
    return ctx.llm_completion_tokens or ""
end)

core.ctx.register_var("request_llm_model", function(ctx)
    return ctx.request_llm_model or ""
end)

local schema = {
    type = "object",
    properties = {
        max_resp_body_bytes = { type = "integer", minimum = 1, default = 262144 },
        provider = { type = "string", enum = {"anthropic", "openai"} },
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
    ctx.llm_model = req.model or ""  -- unified var for billing logs
    ctx.request_llm_model = req.model or ""  -- requested model (before any mapping)

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
        -- Set unified token vars for billing logs
        if data.usage.prompt_tokens then
            ctx.llm_prompt_tokens = data.usage.prompt_tokens
        end
        if data.usage.completion_tokens then
            ctx.llm_completion_tokens = data.usage.completion_tokens
        end
    end
end

-- Process streaming response with SSE parsing
local function process_streaming_chunk(conf, ctx, chunk, eof)
    local function handle_line(line)
        process_sse_line(line, ctx)
    end

    if chunk and chunk ~= "" then
        sse_parser.feed_lines(ctx, "_sse_buf", chunk, handle_line)
    end

    if eof then
        sse_parser.flush_lines(ctx, "_sse_buf", handle_line)

        -- Set usage_present flag on EOF
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
        -- Set unified token vars for billing logs
        if resp.usage.prompt_tokens then
            ctx.llm_prompt_tokens = resp.usage.prompt_tokens
        end
        if resp.usage.completion_tokens then
            ctx.llm_completion_tokens = resp.usage.completion_tokens
        end
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
