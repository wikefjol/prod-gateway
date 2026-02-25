local core = require("apisix.core")
local cjson = require("cjson.safe")

local plugin_name = "model-policy"

-- MODEL_REGISTRY: Single source of truth for all models
-- Add new models here; no other place should define model lists
local MODEL_REGISTRY = {
    { id = "gpt-4o", provider = "openai", owned_by = "system", created = 1715367049 },
    { id = "gpt-4o-mini", provider = "openai", owned_by = "system", created = 1721172741 },
    { id = "gpt-4-turbo", provider = "openai", owned_by = "system", created = 1712361441 },
    { id = "gpt-4", provider = "openai", owned_by = "openai", created = 1687882411 },
    { id = "gpt-3.5-turbo-0125", provider = "openai", owned_by = "openai", created = 1677610602 },
    { id = "o1", provider = "openai", owned_by = "system", created = 1734393600 },
    { id = "o1-mini", provider = "openai", owned_by = "system", created = 1725926400 },
    { id = "o1-preview", provider = "openai", owned_by = "system", created = 1725926400 },
    { id = "o3-mini", provider = "openai", owned_by = "system", created = 1738195200 },
    { id = "claude-3-haiku-20240307", provider = "anthropic", owned_by = "anthropic", created = 1709769600 },
    { id = "claude-sonnet-4-20250514", provider = "anthropic", owned_by = "anthropic", created = 1747180800 },
    { id = "claude-opus-4-20250514", provider = "anthropic", owned_by = "anthropic", created = 1747180800 },
    -- Side-by-side testing models (match LiteLLM names)
    { id = "gpt-4.1-2025-04-14", provider = "openai", owned_by = "system", created = 1744588800 },
    { id = "o3-mini-2025-01-31", provider = "openai", owned_by = "system", created = 1738281600 },
    { id = "claude-sonnet-4-5", provider = "anthropic", owned_by = "anthropic", created = 1759276800 },
    { id = "claude-opus-4-5", provider = "anthropic", owned_by = "anthropic", created = 1759276800 },
    { id = "claude-haiku-4-5", provider = "anthropic", owned_by = "anthropic", created = 1759276800 },
}

-- Access control: models allowed per consumer group
-- "*" means all models in MODEL_REGISTRY
local ALLOWED_MODELS_BY_GROUP = {
    base_user = {
        "gpt-4o-mini",
        "gpt-3.5-turbo-0125",
        "claude-3-haiku-20240307",
        "claude-haiku-4-5",
    },
    premium_user = "*",  -- All models
    claude_code_users = "*",  -- For sidecar
}

-- Build lookup tables for efficiency
local MODEL_BY_ID = {}
for _, m in ipairs(MODEL_REGISTRY) do
    MODEL_BY_ID[m.id] = m
end

local schema = {
    type = "object",
    properties = {
        action = {
            type = "string",
            enum = {"enforce", "render"},
            default = "enforce"
        }
    },
    required = {"action"}
}

-- Register ctx vars for logging
core.ctx.register_var("model_requested", function(ctx)
    return ctx.model_requested or ""
end)

core.ctx.register_var("model_effective", function(ctx)
    return ctx.model_effective or ""
end)

core.ctx.register_var("upstream_provider", function(ctx)
    return ctx.upstream_provider or ""
end)

local _M = {
    version = 0.1,
    priority = 2000,  -- Run after auth (key-auth is 2500, openai-auth is 2500)
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

-- Send OpenAI-format error response
local function send_error(status, message, err_type, code)
    local body = core.json.encode({
        error = {
            message = message,
            type = err_type or "invalid_request_error",
            code = code,
            param = core.json.null
        }
    })
    core.response.set_header("Content-Type", "application/json")
    return status, body
end

-- Check if model is allowed for consumer group
local function is_model_allowed(model_id, group_id)
    local allowed = ALLOWED_MODELS_BY_GROUP[group_id]
    if not allowed then
        return false
    end
    if allowed == "*" then
        return true
    end
    for _, m in ipairs(allowed) do
        if m == model_id then
            return true
        end
    end
    return false
end

-- Enforce model access for chat completions (action=enforce)
local function enforce_chat_model_access(conf, ctx)
    local body, err = core.request.get_body()
    if not body then
        return send_error(400, "Request body required", "invalid_request_error", "missing_body")
    end

    local req = cjson.decode(body)
    if not req then
        return send_error(400, "Invalid JSON", "invalid_request_error", "invalid_json")
    end

    local model = req.model
    if not model or model == "" then
        return send_error(400, "Model is required", "invalid_request_error", "missing_model")
    end

    ctx.model_requested = model

    -- Validate model exists in registry
    local model_info = MODEL_BY_ID[model]
    if not model_info then
        return send_error(400,
            string.format("Unknown model: %s", model),
            "invalid_request_error",
            "unknown_model"
        )
    end

    -- Check consumer group access
    local group_id = ctx.consumer_group_id
    if group_id and not is_model_allowed(model, group_id) then
        return send_error(403,
            string.format("Model '%s' not available for your subscription tier", model),
            "invalid_request_error",
            "model_not_allowed"
        )
    end

    -- Set ctx vars for logging and routing
    ctx.model_effective = model
    ctx.upstream_provider = model_info.provider

    core.log.info("model-policy: model=", model, " provider=", model_info.provider, " group=", group_id or "none")
end

-- Render /models response filtered by consumer group (action=render)
local function render_models_for_group(conf, ctx)
    local group_id = ctx.consumer_group_id
    local models = {}

    for _, m in ipairs(MODEL_REGISTRY) do
        if not group_id or is_model_allowed(m.id, group_id) then
            table.insert(models, {
                id = m.id,
                object = "model",
                created = m.created,
                owned_by = m.owned_by
            })
        end
    end

    local response = {
        object = "list",
        data = models
    }

    core.response.set_header("Content-Type", "application/json")
    return 200, core.json.encode(response)
end

function _M.access(conf, ctx)
    if conf.action == "enforce" then
        return enforce_chat_model_access(conf, ctx)
    elseif conf.action == "render" then
        return render_models_for_group(conf, ctx)
    end
end

return _M
