local core = require("apisix.core")

local M = {}

function M.bearer_to_api_key(conf, ctx)
  -- Get the Authorization header using apisix.core
  local auth_header = core.request.header(ctx, "Authorization")

  -- Check if it starts with "Bearer "
  if auth_header and auth_header:sub(1, 7) == 'Bearer ' then
    -- Extract the token part after "Bearer "
    local token = auth_header:sub(8)

    -- Set it as x-api-key header
    ngx.req.set_header('x-api-key', token)

    -- Remove the Authorization header to avoid confusion
    ngx.req.set_header('Authorization', nil)

    -- Log for debugging (optional, can be removed in production)
    core.log.info("Transformed Bearer token to x-api-key")
  end
end

return M