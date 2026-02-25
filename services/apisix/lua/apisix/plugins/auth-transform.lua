-- auth-transform
-- Purpose: Convert Authorization: Bearer <token> to X-Api-Key: <token>; sanitize request IDs
-- Phase: rewrite
-- Priority: 12020 (before key-auth at 2500)
-- Schema: { mode: "bearer_to_api_key", sanitize_request_ids: bool }
-- Ctx vars set: none (modifies headers in place)

local core = require("apisix.core")

local plugin_name = "auth-transform"

local schema = {
    type = "object",
    properties = {
        mode = {
            type = "string",
            enum = {"bearer_to_api_key"},
            default = "bearer_to_api_key"
        },
        sanitize_request_ids = {
            type = "boolean",
            default = true
        }
    }
}

local _M = {
    version = 0.1,
    priority = 12020,  -- Run before auth plugins (key-auth is 2500)
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

-- Sanitize request ID headers to prevent client override of gateway-generated IDs
-- - Strips incoming X-Request-Id so the request-id plugin generates a fresh one
-- - Preserves client's value by moving it to X-User-Request-Id (if not already set)
local function sanitize_request_ids(ctx)
    local incoming_request_id = core.request.header(ctx, "X-Request-Id")
    local user_request_id = core.request.header(ctx, "X-User-Request-Id")

    if incoming_request_id and incoming_request_id ~= "" then
        if not user_request_id or user_request_id == "" then
            core.request.set_header(ctx, "X-User-Request-Id", incoming_request_id)
            core.log.info("Moved client X-Request-Id to X-User-Request-Id: ", incoming_request_id)
        end
        core.request.set_header(ctx, "X-Request-Id", nil)
    end
end

-- Convert Authorization: Bearer <token> to X-Api-Key: <token>
local function bearer_to_api_key(ctx)
    local api_key = core.request.header(ctx, "x-api-key")
    local auth_header = core.request.header(ctx, "Authorization")

    -- Case 1: X-Api-Key exists - preserve it, remove Authorization
    if api_key and api_key ~= "" then
        if auth_header then
            core.request.set_header(ctx, "Authorization", nil)
            core.log.info("Keeping existing x-api-key and removing Authorization header")
        end
    -- Case 2: Authorization: Bearer exists - convert to X-Api-Key
    elseif auth_header and auth_header:sub(1, 7) == "Bearer " then
        local token = auth_header:sub(8)
        core.request.set_header(ctx, "x-api-key", token)
        core.request.set_header(ctx, "Authorization", nil)
        core.log.info("Transformed Bearer token to x-api-key")
    end
end

function _M.rewrite(conf, ctx)
    if conf.sanitize_request_ids ~= false then
        sanitize_request_ids(ctx)
    end

    if conf.mode == "bearer_to_api_key" or conf.mode == nil then
        bearer_to_api_key(ctx)
    end
end

return _M
