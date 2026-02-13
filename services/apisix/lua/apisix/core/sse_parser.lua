-- SSE line-based parser for streaming responses
-- Shared module to reduce duplication across plugins

local _M = {}

--- Feed chunk to line-based SSE parser
-- Calls line_callback for each complete line (stripped of CRLF)
-- Manages buffer in ctx[buf_key]
-- @param ctx      request context table
-- @param buf_key  key for buffer storage in ctx (e.g., "_sse_buf")
-- @param chunk    incoming data chunk
-- @param line_callback  function(line) called for each complete line
-- @param max_buf  optional max buffer size (default 32768)
function _M.feed_lines(ctx, buf_key, chunk, line_callback, max_buf)
    max_buf = max_buf or 32768
    ctx[buf_key] = (ctx[buf_key] or "") .. chunk

    -- Find last newline position
    local last_nl = ctx[buf_key]:match(".*()[\r\n]")
    if last_nl then
        local complete = ctx[buf_key]:sub(1, last_nl)
        ctx[buf_key] = ctx[buf_key]:sub(last_nl + 1)

        for line in complete:gmatch("[^\r\n]+") do
            line_callback(line)
        end
    end

    -- Safety cap on buffer
    if #ctx[buf_key] > max_buf then
        ctx[buf_key] = ctx[buf_key]:sub(-max_buf)
    end
end

--- Flush remaining buffer on EOF
-- Processes any remaining incomplete line
-- @param ctx      request context table
-- @param buf_key  key for buffer storage in ctx
-- @param line_callback  function(line) called if buffer non-empty
function _M.flush_lines(ctx, buf_key, line_callback)
    if ctx[buf_key] and #ctx[buf_key] > 0 then
        line_callback(ctx[buf_key])
        ctx[buf_key] = ""
    end
end

return _M
