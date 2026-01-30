local core = require("apisix.core")
local consumer_mod = require("apisix.consumer")

local plugin_name = "openai-auth"

local schema = {
    type = "object",
    properties = {
        header = {
            type = "string",
            default = "x-api-key"
        },
        hide_credentials = {
            type = "boolean",
            default = true
        }
    }
}

local _M = {
    version = 0.1,
    priority = 2500,
    type = "auth",
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

local function send_openai_error(status, message, err_type, code)
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

function _M.rewrite(conf, ctx)
    local header_name = conf.header or "x-api-key"
    local api_key = core.request.header(ctx, header_name)

    if not api_key or api_key == "" then
        return send_openai_error(
            401,
            "Missing API key. Include your API key in an 'Authorization' header with 'Bearer <key>'.",
            "invalid_request_error",
            "missing_api_key"
        )
    end

    -- Use key-auth credentials so existing consumers work
    local consumer, consumer_conf, err = consumer_mod.find_consumer("key-auth", "key", api_key)
    if not consumer then
        core.log.warn("openai-auth: failed to find consumer: ", err or "invalid api key")
        return send_openai_error(
            401,
            "Invalid API key provided.",
            "invalid_request_error",
            "invalid_api_key"
        )
    end

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)

    if conf.hide_credentials then
        core.request.set_header(ctx, header_name, nil)
    end

    core.log.info("openai-auth: consumer ", consumer.username, " authenticated")
end

return _M
