# Coding Agents

The gateway exposes an OpenAI-compatible API. Most coding agents and AI tools that support a custom OpenAI base URL should work.

!!! warning "Compatibility not guaranteed"
    Only [Open WebUI](/docs/openwebui/) is actively tested. The patterns below are based on each tool's documented configuration — your mileage may vary.

## General pattern

Most OpenAI-compatible tools need two things:

1. **API key** — your gateway key from the [Portal](/portal/){:target="_blank"}
2. **Base URL** — `https://ai-gateway.portal.chalmers.se/llm/openai/v1`

Look for settings like `OPENAI_API_KEY` / `OPENAI_BASE_URL`, or equivalent config options in the tool's documentation.

### Environment variables

Many tools pick up these automatically:

```bash
export OPENAI_API_KEY="YOUR_API_KEY"
export OPENAI_BASE_URL="https://ai-gateway.portal.chalmers.se/llm/openai/v1"
```

### Config file (JSON)

Tools that use a JSON config typically need fields like:

```json
{
  "provider": "openai",
  "model": "gpt-4o-mini",
  "apiKey": "YOUR_API_KEY",
  "apiBase": "https://ai-gateway.portal.chalmers.se/llm/openai/v1"
}
```

## Anthropic-native tools (Claude Code)

Tools that use the Anthropic API directly (not OpenAI-compatible) need the `/llm/anthropic/v1` endpoint instead:

```bash
export ANTHROPIC_API_KEY="YOUR_API_KEY"
export ANTHROPIC_BASE_URL="https://ai-gateway.portal.chalmers.se/llm/anthropic"
```

!!! note
    The `/llm/anthropic/v1` endpoint is not available to all users - contact admin if you want access.
