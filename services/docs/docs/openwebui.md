# OpenWebUI Guide

OpenWebUI is a browser-based chat interface that connects to the AI Gateway, giving you a ChatGPT-like experience with all available models.

## What is OpenWebUI?

A self-hosted web UI for interacting with LLMs. It supports:

- Multi-model conversations
- File uploads and analysis
- System prompts and presets
- Conversation history (stored locally)

## How to access

1. Go to [openwebui.portal.chalmers.se](https://openwebui.portal.chalmers.se)
2. Sign in with your Chalmers credentials
3. Select a model from the dropdown and start chatting

## Model selector

Use the dropdown in the top-left to switch between models. All models from the [Getting Started](index.md#3-available-models) table are available.

## Tips

### System prompts

Click the settings icon next to the model selector to set a system prompt. Useful for:

- Setting the assistant's role ("You are a helpful math tutor")
- Constraining output format ("Always respond in Swedish")
- Providing context about your project

### File uploads

Drag and drop files into the chat to analyze them. Works well with:

- Code files for review
- CSV/text data for analysis
- Documents for summarization

### Conversation history

Conversations are stored in your browser. Use the sidebar to:

- Browse past conversations
- Search by keyword
- Delete old chats

### Privacy

- Conversations pass through the AI Gateway to the model provider
- OpenWebUI stores chat history in your browser only
- The gateway logs request metadata (model, token count) but not message content
