local core = require("apisix.core")
local cjson = require("cjson.safe")

local M = {}

-- Model registry: canonical list of known models
-- created: unix timestamp (approx release date for SDK compat)
local MODEL_REGISTRY = {
  { id = "gpt-4o", owned_by = "system", provider = "openai", created = 1715367049 },
  { id = "gpt-4o-mini", owned_by = "system", provider = "openai", created = 1721172741 },
  { id = "gpt-4-turbo", owned_by = "system", provider = "openai", created = 1712361441 },
  { id = "o1", owned_by = "system", provider = "openai", created = 1734130800 },
  { id = "o1-mini", owned_by = "system", provider = "openai", created = 1725667200 },
  { id = "o3-mini", owned_by = "system", provider = "openai", created = 1738195200 },
  { id = "claude-sonnet-4-20250514", owned_by = "anthropic", provider = "anthropic", created = 1747267200 },
  { id = "claude-3-5-sonnet-20241022", owned_by = "anthropic", provider = "anthropic", created = 1729555200 },
  { id = "claude-3-5-haiku-20241022", owned_by = "anthropic", provider = "anthropic", created = 1729555200 },
  { id = "claude-3-opus-20240229", owned_by = "anthropic", provider = "anthropic", created = 1709164800 },
}

-- Build lookup table for O(1) checks
local MODEL_LOOKUP = {}
for _, m in ipairs(MODEL_REGISTRY) do
  MODEL_LOOKUP[m.id] = m
end

-- Allowlists per consumer group (explicit model IDs, or "*" for all known)
local ALLOWED_MODELS_BY_GROUP = {
  base_user = {
    ["gpt-4o-mini"] = true,
    ["claude-3-5-haiku-20241022"] = true,
  },
  premium_user = {
    ["*"] = true,  -- all KNOWN models allowed
  },
}

local DEFAULT_GROUP = "base_user"

-- Get consumer group ID (check multiple locations for safety)
function M.get_group_id(ctx)
  -- APISIX exposes group as ctx.consumer_group_id after key-auth
  if ctx.consumer_group_id and ctx.consumer_group_id ~= "" then
    return ctx.consumer_group_id
  end
  -- Fallback: check consumer object
  if ctx.consumer and ctx.consumer.group_id then
    return ctx.consumer.group_id
  end
  return DEFAULT_GROUP
end

-- Get requested model from body (cached)
function M.get_requested_model(ctx)
  if ctx._model_policy_model ~= nil then
    return ctx._model_policy_model
  end
  local body, err = core.request.get_body()
  if not body then
    ctx._model_policy_model = false
    return nil
  end
  local req = cjson.decode(body)
  if not req or not req.model then
    ctx._model_policy_model = false
    return nil
  end
  ctx._model_policy_model = req.model
  return req.model
end

-- Check if model is in registry
function M.is_known(model)
  return MODEL_LOOKUP[model] ~= nil
end

-- Check if model is allowed for group ("*" = all KNOWN models)
function M.is_allowed(group_id, model)
  local allowlist = ALLOWED_MODELS_BY_GROUP[group_id]
  if not allowlist then
    return false
  end
  if allowlist["*"] then
    return M.is_known(model)  -- wildcard only allows known models
  end
  return allowlist[model] == true
end

-- Send OpenAI-style error and exit
function M.reject(status, message, code, param)
  ngx.status = status
  ngx.header["Content-Type"] = "application/json"
  local err = { error = { message = message, type = "invalid_request_error", code = code } }
  if param then err.error.param = param end
  ngx.say(cjson.encode(err))
  ngx.exit(status)
end

-- Main enforcement (call in access phase AFTER key-auth)
function M.enforce_chat_model_access(conf, ctx)
  -- Safety: if consumer not set, key-auth hasn't run or failed - let it handle auth
  if not ctx.consumer and not ctx.consumer_name then
    return  -- don't duplicate auth errors
  end

  local model = M.get_requested_model(ctx)
  if not model then
    return M.reject(400, "Missing required parameter: model", "missing_model", "model")
  end
  if not M.is_known(model) then
    return M.reject(400, "Unknown model: " .. model .. ". Use GET /ai/v1/models for available models.", "model_not_found", "model")
  end

  local group_id = M.get_group_id(ctx)
  if not M.is_allowed(group_id, model) then
    return M.reject(403, "Model '" .. model .. "' is not available for your access tier.", "model_forbidden", "model")
  end
  -- allowed: continue to ai-proxy
end

-- Render filtered /models response
function M.render_models_for_group(conf, ctx)
  local group_id = M.get_group_id(ctx)
  local allowlist = ALLOWED_MODELS_BY_GROUP[group_id] or {}
  local data = {}

  for _, m in ipairs(MODEL_REGISTRY) do
    if allowlist["*"] or allowlist[m.id] then
      data[#data + 1] = { id = m.id, object = "model", created = m.created, owned_by = m.owned_by }
    end
  end

  ngx.status = 200
  ngx.header["Content-Type"] = "application/json"
  ngx.say(cjson.encode({ object = "list", data = data }))
  ngx.exit(200)
end

return M
