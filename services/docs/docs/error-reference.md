# Error Reference

Common HTTP errors from the gateway and how to fix them.

## 401 — Unauthorized

**Your API key is missing or invalid.**

**Causes:**

- No `Authorization` header in request
- Typo in the API key
- Key was recycled (old key is now invalid)

**Fixes:**

- Check your `Authorization: Bearer YOUR_KEY` header
- Get your current key from the [Portal](/portal/)
- If you recently recycled your key, update it in all tools/scripts

## 403 — Forbidden

**Your consumer group does not have access to this model.**

**Causes:**

- Using a premium model (`gpt-4o`, `claude-sonnet-4-20250514`) with a base-tier key
- Trying to access the Claude Code sidecar without `claude_code_users` group membership

**Fixes:**

- Switch to a base-tier model (e.g., `gpt-4o-mini`, `claude-haiku-4-5`)
- Check your tier on the [Getting Started](index.md#3-available-models) page
- Contact the administrator if you need premium access

## 429 — Too Many Requests

**You've exceeded your rate limit.**

**Causes:**

- Sent too many requests within the rate window
- Automated scripts running without backoff

**Fixes:**

- Check `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers in responses
- Add exponential backoff to your code
- Wait for the rate limit window to reset

## 502 — Bad Gateway

**The upstream model provider returned an error or is unavailable.**

**Causes:**

- OpenAI/Anthropic/vLLM backend is temporarily down
- Request timed out at the provider
- Invalid request format that passed gateway validation but failed upstream

**Fixes:**

- Retry the request after a few seconds
- Check if the specific provider is experiencing outages
- Verify your request body matches the [OpenAI chat completions format](https://platform.openai.com/docs/api-reference/chat)
- For vLLM models, the Alvis HPC cluster may be under maintenance

## Response format

All errors follow this structure:

```json
{
  "error": {
    "message": "Description of what went wrong",
    "type": "error_type",
    "code": "error_code"
  }
}
```
