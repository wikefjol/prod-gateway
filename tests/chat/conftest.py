"""Chat completions test constants."""

from conftest import API_PREFIX

CHAT_PATH = f"{API_PREFIX}/v1/chat/completions"

# Ground truth: models base tier can access for chat completions
BASE_ALLOWED = {
    "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo-0125",
    "gpt-4.1-2025-04-14",
    "claude-3-haiku-20240307", "claude-sonnet-4-20250514", "claude-opus-4-20250514",
    "claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4-5",
    "qwen3-coder-30b", "gemma-3-12b-it", "gpt-oss-20b", "nomic-embed-text-v1.5",
}
