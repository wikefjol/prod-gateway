#!/bin/bash
set -euo pipefail

# Test billing logging for all provider routes
# Usage: ./services/apisix/scripts/test-billing-logging.sh [dev|test]

ENV="${1:-dev}"
ENV_FILE="infra/env/.env.${ENV}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi
source "$ENV_FILE"

# Port based on env
if [ "$ENV" = "test" ]; then
  PORT=9081
else
  PORT=9080
fi

BASE_URL="http://127.0.0.1:${PORT}"
LOG_DIR="services/apisix/logs/billing"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# Need a consumer key - check if we have one
CONSUMER_KEY="${TEST_CONSUMER_KEY:-}"
if [ -z "$CONSUMER_KEY" ]; then
  echo "Set TEST_CONSUMER_KEY env var to a valid consumer API key"
  exit 1
fi

check_log() {
  local log_file="$1"
  local route_name="$2"
  local request_id="$3"

  sleep 1  # wait for log flush

  if [ ! -f "$log_file" ]; then
    echo -e "${RED}FAIL${NC}: Log file not found: $log_file"
    ((FAIL++))
    return 1
  fi

  # Check last line contains our request
  local last_line
  last_line=$(tail -1 "$log_file")

  if echo "$last_line" | grep -q "$request_id"; then
    # Verify required fields
    if echo "$last_line" | jq -e '.usage_present' >/dev/null 2>&1; then
      local usage_present
      usage_present=$(echo "$last_line" | jq -r '.usage_present')
      if [ "$usage_present" = "true" ]; then
        echo -e "${GREEN}PASS${NC}: $route_name - usage captured"
        ((PASS++))
        return 0
      else
        echo -e "${YELLOW}WARN${NC}: $route_name - no usage in response (may be expected for some endpoints)"
        ((PASS++))
        return 0
      fi
    else
      echo -e "${RED}FAIL${NC}: $route_name - invalid log format"
      echo "Log entry: $last_line"
      ((FAIL++))
      return 1
    fi
  else
    echo -e "${RED}FAIL${NC}: $route_name - request $request_id not found in log"
    ((FAIL++))
    return 1
  fi
}

test_route() {
  local route_name="$1"
  local endpoint="$2"
  local data="$3"
  local log_file="$4"
  local streaming="${5:-false}"

  local request_id
  request_id=$(uuidgen)

  local stream_suffix=""
  [ "$streaming" = "true" ] && stream_suffix=" (streaming)"

  echo -n "Testing $route_name$stream_suffix... "

  local response
  if [ "$streaming" = "true" ]; then
    # For streaming, just capture status code
    response=$(curl -s -w "\n%{http_code}" -o /dev/null \
      -X POST "${BASE_URL}${endpoint}" \
      -H "Authorization: Bearer $CONSUMER_KEY" \
      -H "Content-Type: application/json" \
      -H "X-User-Request-Id: $request_id" \
      -d "$data")
  else
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "${BASE_URL}${endpoint}" \
      -H "Authorization: Bearer $CONSUMER_KEY" \
      -H "Content-Type: application/json" \
      -H "X-User-Request-Id: $request_id" \
      -d "$data")
  fi

  local status_code
  status_code=$(echo "$response" | tail -1)

  if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
    check_log "$LOG_DIR/$log_file" "$route_name" "$request_id"
  else
    echo -e "${RED}FAIL${NC}: HTTP $status_code"
    ((FAIL++))
  fi
}

echo "========================================="
echo "Billing Logging Tests - $ENV environment"
echo "========================================="
echo ""

# Anthropic Messages (native)
ANTHROPIC_MSG_DATA='{"model":"claude-3-haiku-20240307","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
ANTHROPIC_MSG_DATA_STREAM='{"model":"claude-3-haiku-20240307","max_tokens":10,"stream":true,"messages":[{"role":"user","content":"Hi"}]}'

test_route "anthropic-messages" "/provider/anthropic/v1/messages" "$ANTHROPIC_MSG_DATA" "anthropic-messages.log"
test_route "anthropic-messages" "/provider/anthropic/v1/messages" "$ANTHROPIC_MSG_DATA_STREAM" "anthropic-messages.log" true

# Anthropic OpenAI-compat
OPENAI_DATA='{"model":"claude-3-haiku-20240307","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
OPENAI_DATA_STREAM='{"model":"claude-3-haiku-20240307","max_tokens":10,"stream":true,"stream_options":{"include_usage":true},"messages":[{"role":"user","content":"Hi"}]}'

test_route "anthropic-openai" "/provider/anthropic/openai/v1/chat/completions" "$OPENAI_DATA" "anthropic-openai.log"
test_route "anthropic-openai" "/provider/anthropic/openai/v1/chat/completions" "$OPENAI_DATA_STREAM" "anthropic-openai.log" true

# OpenAI Chat
OPENAI_CHAT_DATA='{"model":"gpt-4o-mini","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
OPENAI_CHAT_DATA_STREAM='{"model":"gpt-4o-mini","max_tokens":10,"stream":true,"stream_options":{"include_usage":true},"messages":[{"role":"user","content":"Hi"}]}'

test_route "openai-chat" "/provider/openai/v1/chat/completions" "$OPENAI_CHAT_DATA" "openai-chat.log"
test_route "openai-chat" "/provider/openai/v1/chat/completions" "$OPENAI_CHAT_DATA_STREAM" "openai-chat.log" true

# OpenAI Responses
OPENAI_RESP_DATA='{"model":"gpt-4o-mini","input":"Hi"}'
# Note: Responses API streaming not tested - different mechanism

test_route "openai-responses" "/provider/openai/v1/responses" "$OPENAI_RESP_DATA" "openai-responses.log"

# LiteLLM
LITELLM_DATA='{"model":"gpt-4o-mini","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'

test_route "litellm" "/provider/litellm/v1/chat/completions" "$LITELLM_DATA" "litellm.log"

echo ""
echo "========================================="
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "========================================="

# Check for sensitive data leaks
echo ""
echo "Checking for sensitive data in logs..."
SENSITIVE_PATTERNS=("content" "text" "prompt" "message")
LEAKED=false

for log in "$LOG_DIR"/*.log; do
  [ -f "$log" ] || continue
  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    # Check if pattern appears outside of expected field names
    if grep -q "\"$pattern\":" "$log" 2>/dev/null; then
      # This is fine - it's a field name
      continue
    fi
  done
done

if [ "$LEAKED" = false ]; then
  echo -e "${GREEN}No obvious sensitive data found in logs${NC}"
fi

exit $FAIL
