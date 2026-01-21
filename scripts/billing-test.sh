#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# billing-test.sh
# Fires test requests to Anthropic (/v1/messages) and OpenAI (/v1/chat/completions)
# to generate billing events in Kafka.
# Tests both non-streaming and streaming modes for each provider.
# Prints request info and gateway request ID for correlation with Kafka events.
# -----------------------------------------------------------------------------

# Configuration - override with environment variables
HTTP_PORT="${GATEWAY_HTTP_PORT:-9080}"
GW_KEY="${GW_KEY:-}"  # Your gateway API key (required)

OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-3-5-sonnet-20241022}"

BASE="http://localhost:${HTTP_PORT}"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: GW_KEY=<your-key> $0 [options]

Options:
  --openai-only     Run only OpenAI scenarios
  --anthropic-only  Run only Anthropic scenarios
  --help            Show this help

Environment variables:
  GW_KEY              Gateway API key (required)
  GATEWAY_HTTP_PORT   Gateway port (default: 9080)
  OPENAI_MODEL        OpenAI model (default: gpt-4o-mini)
  ANTHROPIC_MODEL     Anthropic model (default: claude-3-5-sonnet-20241022)

Examples:
  GW_KEY=my-api-key $0
  GW_KEY=my-api-key ANTHROPIC_MODEL=claude-3-haiku-20240307 $0 --anthropic-only

To watch Kafka events in another terminal:
  docker exec apisix-dev-kafka-1 kafka-console-consumer \\
    --bootstrap-server localhost:9092 \\
    --topic llm_gateway_events \\
    --from-beginning
EOF
  exit 0
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

JQ_OK=0
if need_cmd jq; then JQ_OK=1; fi

call_api() {
  local label="$1"
  local provider="$2"
  local url="$3"
  local payload="$4"

  local hdr body http_code
  hdr="$(mktemp)"
  body="$(mktemp)"

  http_code="$(
    curl -sS \
      -o "$body" \
      -D "$hdr" \
      -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${GW_KEY}" \
      "$url" \
      --data-binary "$payload" \
      || true
  )"

  # Gateway request ID (from request-id plugin)
  local gw_request_id
  gw_request_id="$(grep -i '^x-request-id:' "$hdr" | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true)"

  # Provider request IDs (for cross-reference)
  local rid_anthropic
  rid_anthropic="$(grep -i '^request-id:' "$hdr" | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true)"

  # Extract model from request payload
  local model="(unknown)"
  if [[ "$JQ_OK" -eq 1 ]]; then
    model="$(echo "$payload" | jq -r '.model // "(unknown)"' 2>/dev/null || echo "(unknown)")"
  fi

  # Extract usage from response body (if available)
  local usage=""
  if [[ "$JQ_OK" -eq 1 ]] && [[ -f "$body" ]]; then
    usage="$(jq -c '.usage // empty' "$body" 2>/dev/null || true)"
  fi

  printf "\n[%s] %s\n" "$provider" "$label"
  printf "  url:            %s\n" "$url"
  printf "  model:          %s\n" "$model"
  printf "  http:           %s\n" "$http_code"
  printf "  x-request-id:  %s\n" "${gw_request_id:-(none)}"
  [[ -n "$rid_anthropic" ]] && printf "  provider-id:    %s\n" "$rid_anthropic"
  [[ -n "$usage" ]] && printf "  usage:          %s\n" "$usage"

  rm -f "$hdr" "$body"
}

# Streaming API call - consumes SSE stream and extracts final usage
call_api_streaming() {
  local label="$1"
  local provider="$2"
  local url="$3"
  local payload="$4"

  local hdr body http_code
  hdr="$(mktemp)"
  body="$(mktemp)"

  # Use -N for unbuffered streaming output
  http_code="$(
    curl -sS -N \
      -o "$body" \
      -D "$hdr" \
      -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${GW_KEY}" \
      "$url" \
      --data-binary "$payload" \
      || true
  )"

  # Gateway request ID (from request-id plugin)
  local gw_request_id
  gw_request_id="$(grep -i '^x-request-id:' "$hdr" | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true)"

  # Provider request IDs (for cross-reference)
  local rid_anthropic
  rid_anthropic="$(grep -i '^request-id:' "$hdr" | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true)"

  # Extract model from request payload
  local model="(unknown)"
  if [[ "$JQ_OK" -eq 1 ]]; then
    model="$(echo "$payload" | jq -r '.model // "(unknown)"' 2>/dev/null || echo "(unknown)")"
  fi

  # Extract usage from streaming response (look for usage in SSE data lines)
  local usage=""
  if [[ "$JQ_OK" -eq 1 ]] && [[ -f "$body" ]]; then
    # For Anthropic: usage appears in message_delta event
    # For OpenAI: usage appears in final chunk (when include_usage is set)
    usage="$(grep '^data:' "$body" | sed 's/^data: //' | grep -v '^\[DONE\]' | while read -r line; do
      echo "$line" | jq -c '.usage // empty' 2>/dev/null | grep -v '^$'
    done | tail -n 1 || true)"
  fi

  # Count chunks for info
  local chunk_count=0
  if [[ -f "$body" ]]; then
    chunk_count="$(grep -c '^data:' "$body" 2>/dev/null || echo 0)"
  fi

  printf "\n[%s] %s (STREAMING)\n" "$provider" "$label"
  printf "  url:            %s\n" "$url"
  printf "  model:          %s\n" "$model"
  printf "  http:           %s\n" "$http_code"
  printf "  x-request-id:  %s\n" "${gw_request_id:-(none)}"
  printf "  sse-chunks:     %s\n" "$chunk_count"
  [[ -n "$rid_anthropic" ]] && printf "  provider-id:    %s\n" "$rid_anthropic"
  [[ -n "$usage" ]] && printf "  usage:          %s\n" "$usage"

  rm -f "$hdr" "$body"
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------

RUN_OPENAI=1
RUN_ANTHROPIC=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openai-only)
      RUN_ANTHROPIC=0
      shift
      ;;
    --anthropic-only)
      RUN_OPENAI=0
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Validate
# -----------------------------------------------------------------------------

if [[ -z "$GW_KEY" ]]; then
  echo "Error: GW_KEY environment variable is required"
  echo "Usage: GW_KEY=<your-key> $0"
  exit 1
fi

echo "Gateway base: ${BASE}"
echo "OpenAI model: ${OPENAI_MODEL}"
echo "Anthropic model: ${ANTHROPIC_MODEL}"
echo
echo "Tip: Correlate x-request-id with Kafka events (x_request_id field) in llm_gateway_events topic"
echo

# -----------------------------------------------------------------------------
# OpenAI scenarios (using /v1/chat/completions)
# -----------------------------------------------------------------------------

if [[ "$RUN_OPENAI" -eq 1 ]]; then
  echo "=== OpenAI Scenarios ==="

  # O1) Baseline small
  OPENAI_O1="$(cat <<JSON
{
  "model": "${OPENAI_MODEL}",
  "messages": [{"role":"user","content":"Say hello in one short sentence."}],
  "max_tokens": 32
}
JSON
)"

  # O2) Large output
  OPENAI_O2="$(cat <<JSON
{
  "model": "${OPENAI_MODEL}",
  "messages": [{"role":"user","content":"Write a detailed, step-by-step guide to brewing coffee at home. Include a checklist."}],
  "max_tokens": 500
}
JSON
)"

  # O3) Multi-turn context
  OPENAI_O3="$(cat <<JSON
{
  "model": "${OPENAI_MODEL}",
  "messages": [
    {"role":"user","content":"We are designing an API gateway for LLM providers."},
    {"role":"assistant","content":"What are your priorities: auth, logging, routing, rate limits, or cost tracking?"},
    {"role":"user","content":"Focus on cost tracking. Suggest what fields to log."}
  ],
  "max_tokens": 200
}
JSON
)"

  # O4) Streaming baseline
  OPENAI_O4="$(cat <<JSON
{
  "model": "${OPENAI_MODEL}",
  "messages": [{"role":"user","content":"Say hello in one short sentence."}],
  "max_tokens": 32,
  "stream": true
}
JSON
)"

  # O5) Streaming with include_usage (to get usage in stream)
  OPENAI_O5="$(cat <<JSON
{
  "model": "${OPENAI_MODEL}",
  "messages": [{"role":"user","content":"Say hello in one short sentence."}],
  "max_tokens": 32,
  "stream": true,
  "stream_options": {"include_usage": true}
}
JSON
)"

  call_api "O1 baseline (small input/output)" \
    "OpenAI" "${BASE}/v1/chat/completions" "$OPENAI_O1"

  call_api "O2 large output (max_tokens=500)" \
    "OpenAI" "${BASE}/v1/chat/completions" "$OPENAI_O2"

  call_api "O3 multi-turn context" \
    "OpenAI" "${BASE}/v1/chat/completions" "$OPENAI_O3"

  call_api_streaming "O4 streaming baseline (no usage)" \
    "OpenAI" "${BASE}/v1/chat/completions" "$OPENAI_O4"

  call_api_streaming "O5 streaming with include_usage" \
    "OpenAI" "${BASE}/v1/chat/completions" "$OPENAI_O5"
fi

# -----------------------------------------------------------------------------
# Anthropic scenarios (using /v1/messages)
# -----------------------------------------------------------------------------

if [[ "$RUN_ANTHROPIC" -eq 1 ]]; then
  echo
  echo "=== Anthropic Scenarios ==="

  # A1) Baseline small
  ANTHROPIC_A1="$(cat <<JSON
{
  "model": "${ANTHROPIC_MODEL}",
  "max_tokens": 64,
  "messages": [{"role":"user","content":"Say hello in one short sentence."}]
}
JSON
)"

  # A2) Large output
  ANTHROPIC_A2="$(cat <<JSON
{
  "model": "${ANTHROPIC_MODEL}",
  "max_tokens": 500,
  "messages": [{"role":"user","content":"Write a detailed, step-by-step guide to brewing coffee at home. Include a checklist."}]
}
JSON
)"

  # A3) Multi-turn context
  ANTHROPIC_A3="$(cat <<JSON
{
  "model": "${ANTHROPIC_MODEL}",
  "max_tokens": 200,
  "messages": [
    {"role":"user","content":"We are designing an API gateway for LLM providers."},
    {"role":"assistant","content":"What are your priorities: auth, logging, routing, rate limits, or cost tracking?"},
    {"role":"user","content":"Focus on cost tracking. Suggest what fields to log without leaking secrets."}
  ]
}
JSON
)"

  # A4) Streaming baseline
  ANTHROPIC_A4="$(cat <<JSON
{
  "model": "${ANTHROPIC_MODEL}",
  "max_tokens": 64,
  "stream": true,
  "messages": [{"role":"user","content":"Say hello in one short sentence."}]
}
JSON
)"

  # A5) Streaming larger output
  ANTHROPIC_A5="$(cat <<JSON
{
  "model": "${ANTHROPIC_MODEL}",
  "max_tokens": 200,
  "stream": true,
  "messages": [{"role":"user","content":"Write a haiku about APIs."}]
}
JSON
)"

  call_api "A1 baseline (small)" \
    "Anthropic" "${BASE}/v1/messages" "$ANTHROPIC_A1"

  call_api "A2 large output (max_tokens=500)" \
    "Anthropic" "${BASE}/v1/messages" "$ANTHROPIC_A2"

  call_api "A3 multi-turn context" \
    "Anthropic" "${BASE}/v1/messages" "$ANTHROPIC_A3"

  call_api_streaming "A4 streaming baseline" \
    "Anthropic" "${BASE}/v1/messages" "$ANTHROPIC_A4"

  call_api_streaming "A5 streaming larger output" \
    "Anthropic" "${BASE}/v1/messages" "$ANTHROPIC_A5"
fi

# -----------------------------------------------------------------------------
# Request ID Policy Verification Tests
# -----------------------------------------------------------------------------

echo
echo "=== Request ID Policy Verification ==="

# Test 0: No user headers → user_request_id should be empty
echo
echo "[TEST 0] No user headers → user_request_id should be empty in Kafka"

TEST0_HDR="$(mktemp)"
TEST0_BODY="$(mktemp)"
curl -sS -D "$TEST0_HDR" -o "$TEST0_BODY" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GW_KEY}" \
  "${BASE}/v1/chat/completions" \
  -d '{"model": "'"${OPENAI_MODEL}"'", "max_tokens": 10, "messages": [{"role": "user", "content": "Hi"}]}'

TEST0_X_REQUEST_ID="$(grep -i '^x-request-id:' "$TEST0_HDR" | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true)"
rm -f "$TEST0_HDR" "$TEST0_BODY"

# Check if X-Request-Id looks like UUID (contains dashes, not req_*)
if [[ "$TEST0_X_REQUEST_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "  PASS: X-Request-Id is UUID format: $TEST0_X_REQUEST_ID"
elif [[ "$TEST0_X_REQUEST_ID" =~ ^req_ ]]; then
  echo "  FAIL: X-Request-Id has upstream format (req_*): $TEST0_X_REQUEST_ID"
  echo "        Gateway should own X-Request-Id, not pass through upstream"
else
  echo "  WARN: X-Request-Id has unexpected format: $TEST0_X_REQUEST_ID"
fi

echo "  Check Kafka for: \"user_request_id\": \"\" (should be empty)"
echo "  Also check: \"_dbg_http_x_request_id\" and \"_dbg_upstream_x_request_id\""

# Test 1: Gateway generates X-Request-Id (client cannot override)
echo
echo "[TEST 1] Client X-Request-Id should be ignored (gateway generates new one)"

TEST1_RESPONSE_ID="$(
  curl -sS -D - -o /dev/null \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GW_KEY}" \
    -H "X-Request-Id: client-supplied-id-should-be-ignored" \
    "${BASE}/v1/chat/completions" \
    -d '{"model": "'"${OPENAI_MODEL}"'", "max_tokens": 10, "messages": [{"role": "user", "content": "Hi"}]}' \
    2>&1 | grep -i '^x-request-id:' | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true
)"

if [[ "$TEST1_RESPONSE_ID" == "client-supplied-id-should-be-ignored" ]]; then
  echo "  FAIL: Gateway returned client-supplied X-Request-Id (should generate new one)"
elif [[ -z "$TEST1_RESPONSE_ID" ]]; then
  echo "  FAIL: No X-Request-Id in response"
elif [[ "$TEST1_RESPONSE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "  PASS: Gateway generated new UUID: $TEST1_RESPONSE_ID"
  echo "  Check Kafka: user_request_id should be \"client-supplied-id-should-be-ignored\" (moved)"
elif [[ "$TEST1_RESPONSE_ID" =~ ^req_ ]]; then
  echo "  FAIL: Got upstream format (req_*): $TEST1_RESPONSE_ID"
else
  echo "  WARN: Unexpected format: $TEST1_RESPONSE_ID"
fi

# Test 2: X-User-Request-Id is preserved
echo
echo "[TEST 2] X-User-Request-Id header should be accepted"

TEST2_PAYLOAD='{"model": "'"${OPENAI_MODEL}"'", "max_tokens": 10, "messages": [{"role": "user", "content": "Hi"}]}'

curl -sS -o /dev/null \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GW_KEY}" \
  -H "X-User-Request-Id: my-correlation-id-123" \
  "${BASE}/v1/chat/completions" \
  -d "$TEST2_PAYLOAD"

echo "  Request sent with X-User-Request-Id: my-correlation-id-123"
echo "  Check Kafka for: \"user_request_id\": \"my-correlation-id-123\""

# Test 3: Client X-Request-Id moves to X-User-Request-Id
echo
echo "[TEST 3] Client X-Request-Id should move to X-User-Request-Id"

TEST3_PAYLOAD='{"model": "'"${OPENAI_MODEL}"'", "max_tokens": 10, "messages": [{"role": "user", "content": "Hi"}]}'

curl -sS -o /dev/null \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GW_KEY}" \
  -H "X-Request-Id: client-id-should-become-user-id" \
  "${BASE}/v1/chat/completions" \
  -d "$TEST3_PAYLOAD"

echo "  Request sent with X-Request-Id: client-id-should-become-user-id"
echo "  Check Kafka for: \"user_request_id\": \"client-id-should-become-user-id\""

# Test 4: Anthropic provider_request_id captured
if [[ "$RUN_ANTHROPIC" -eq 1 ]]; then
  echo
  echo "[TEST 4] Anthropic provider_request_id (req_*) should be captured"

  TEST4_HDR="$(mktemp)"
  curl -sS -D "$TEST4_HDR" -o /dev/null \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GW_KEY}" \
    "${BASE}/v1/messages" \
    -d '{"model": "'"${ANTHROPIC_MODEL}"'", "max_tokens": 10, "messages": [{"role": "user", "content": "Hi"}]}'

  ANTHROPIC_REQ_ID="$(grep -i '^request-id:' "$TEST4_HDR" | tail -n 1 | cut -d' ' -f2- | tr -d '\r' || true)"
  rm -f "$TEST4_HDR"

  if [[ -n "$ANTHROPIC_REQ_ID" ]]; then
    echo "  Anthropic returned request-id: $ANTHROPIC_REQ_ID"
    echo "  Check Kafka for: \"provider_request_id\": \"$ANTHROPIC_REQ_ID\""
  else
    echo "  Note: No request-id header from Anthropic (may vary)"
  fi
fi

echo
echo "Done. Check Kafka events with:"
echo "  docker exec apisix-dev-kafka-1 kafka-console-consumer \\"
echo "    --bootstrap-server localhost:9092 \\"
echo "    --topic llm_gateway_events --from-beginning"
