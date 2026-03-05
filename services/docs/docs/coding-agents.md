# Coding Agents

Configure AI-powered coding tools to use the gateway. All tools use environment variables or config files to set the API endpoint.

## Claude Code

```bash
export ANTHROPIC_API_KEY="YOUR_API_KEY"
export ANTHROPIC_BASE_URL="https://ai-gateway.portal.chalmers.se/llm/claude-code/v1"
```

Then run `claude` as normal. The gateway routes to Anthropic's API.

!!! note
    Claude Code uses the `/llm/claude-code/v1` endpoint (Anthropic native protocol), not the ai-proxy endpoint. Access requires the `claude_code_users` consumer group.

## Cursor

1. Open Cursor Settings (`Ctrl+,`)
2. Go to **Models** > **OpenAI API Key**
3. Set:
    - **API Key:** your gateway key
    - **Base URL:** `https://ai-gateway.portal.chalmers.se/llm/ai-proxy/v1`
4. Select a model (e.g., `gpt-4o-mini`)

Alternatively, set environment variables before launching Cursor:

```bash
export OPENAI_API_KEY="YOUR_API_KEY"
export OPENAI_BASE_URL="https://ai-gateway.portal.chalmers.se/llm/ai-proxy/v1"
cursor .
```

## Continue.dev

Add to your `~/.continue/config.json`:

```json
{
  "models": [
    {
      "title": "GPT-4o Mini (Gateway)",
      "provider": "openai",
      "model": "gpt-4o-mini",
      "apiKey": "YOUR_API_KEY",
      "apiBase": "https://ai-gateway.portal.chalmers.se/llm/ai-proxy/v1"
    }
  ]
}
```

## Aider

```bash
export OPENAI_API_KEY="YOUR_API_KEY"
export OPENAI_API_BASE="https://ai-gateway.portal.chalmers.se/llm/ai-proxy/v1"
aider --model gpt-4o-mini
```

## General pattern

Most OpenAI-compatible tools need two things:

1. **API key** — your gateway key from the [Portal](/portal/)
2. **Base URL** — `https://ai-gateway.portal.chalmers.se/llm/ai-proxy/v1`

Look for settings like `OPENAI_API_KEY` / `OPENAI_BASE_URL`, or equivalent config options in the tool's documentation.
