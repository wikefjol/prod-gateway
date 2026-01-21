local core = require("apisix.core")

local M = {}

function M.bearer_to_api_key(conf, ctx)
  -- Get the existing x-api-key header
  local api_key = core.request.header(ctx, "x-api-key")

  -- Get the Authorization header
  local auth_header = core.request.header(ctx, "Authorization")

  -- Case 1: If X-Api-Key exists and non-empty
  if api_key and api_key ~= "" then
    -- Do NOT overwrite it from Authorization
    -- Just remove Authorization to avoid conflicts but preserve the existing X-Api-Key
    if auth_header then
      ngx.req.set_header('Authorization', nil)
      core.log.info("Keeping existing x-api-key and removing Authorization header")
    end
  -- Case 2: If X-Api-Key is missing but Authorization exists and is Bearer format
  elseif auth_header and auth_header:sub(1, 7) == 'Bearer ' then
    -- Extract the token part after "Bearer "
    local token = auth_header:sub(8)

    -- Set it as x-api-key header
    ngx.req.set_header('x-api-key', token)

    -- Remove the Authorization header to avoid conflicts
    ngx.req.set_header('Authorization', nil)

    core.log.info("Transformed Bearer token to x-api-key (no x-api-key was present)")
  end

  -- Note: The key-auth plugin's hide_credentials option will handle hiding x-api-key from upstream
  -- if configured properly in the route definition
end

-- Sanitize request ID headers to prevent client override of gateway-generated IDs
-- - Strips incoming X-Request-Id so the request-id plugin generates a fresh one
-- - Preserves client's value by moving it to X-User-Request-Id (if not already set)
function M.sanitize_request_ids(conf, ctx)
  local incoming_request_id = core.request.header(ctx, "X-Request-Id")
  local user_request_id = core.request.header(ctx, "X-User-Request-Id")

  -- If client sent X-Request-Id, move it to X-User-Request-Id (if not already set)
  if incoming_request_id and incoming_request_id ~= "" then
    if not user_request_id or user_request_id == "" then
      ngx.req.set_header("X-User-Request-Id", incoming_request_id)
      core.log.info("Moved client X-Request-Id to X-User-Request-Id: ", incoming_request_id)
    end
    -- Remove X-Request-Id so request-id plugin generates a fresh one
    ngx.req.set_header("X-Request-Id", nil)
  end
end

return M