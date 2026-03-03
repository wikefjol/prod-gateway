#!/usr/bin/env bash
# probe-alvis-vllm.sh — Comprehensive vLLM endpoint recon for issue #48
# Run from Lamassu once C3SE confirms firewall access.
# Output: docs/alvis-vllm-compatibility.md (auto-generated)

set -euo pipefail

HOST="alvis-worker1.c3se.chalmers.se"
CHAT_PORTS=(43181 43111 43121)
EMBED_PORT=43211
ALL_PORTS=("${CHAT_PORTS[@]}" "$EMBED_PORT")
MODELS_BY_PORT=(
  [43181]="Qwen/Qwen3-Coder-30B"
  [43111]="google/gemma-3-12b-it"
  [43121]="openai/gpt-oss-20b"
  [43211]="nomic-ai/nomic-embed-text-v1.5"
)
TYPES_BY_PORT=(
  [43181]="chat"
  [43111]="chat"
  [43121]="chat"
  [43211]="embedding"
)

OUTDIR="$(mktemp -d)"
DOCFILE="${1:-docs/alvis-vllm-compatibility.md}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log()  { echo "[$(date +%H:%M:%S)] $*" >&2; }
fail() { echo "FAIL: $*" >&2; }

# ── Preflight ────────────────────────────────────────────────
log "Preflight — checking connectivity"
for PORT in "${ALL_PORTS[@]}"; do
  if ! nc -zv -w 5 "$HOST" "$PORT" 2>/dev/null; then
    fail "Cannot reach $HOST:$PORT — firewall still blocking?"
    exit 1
  fi
done
log "All ports reachable"

# ── Helper: curl wrapper ─────────────────────────────────────
api() {
  local method="$1" url="$2" label="$3"
  shift 3
  local outfile="$OUTDIR/$label"
  local header_file="$OUTDIR/${label}.headers"
  curl -s -w '\n__HTTP_CODE__%{http_code}' \
    -X "$method" "$url" \
    -D "$header_file" \
    "$@" > "$outfile" 2>&1
  # Split HTTP code from body
  local code body
  code=$(grep -oP '__HTTP_CODE__\K\d+' "$outfile" || echo "000")
  body=$(sed 's/__HTTP_CODE__[0-9]*//' "$outfile")
  echo "$body" > "$outfile"
  echo "$code" > "$OUTDIR/${label}.code"
  log "  $label → HTTP $code"
}

# ── Step 1: Discovery ────────────────────────────────────────
log "Step 1: Discovery endpoints"
for PORT in "${ALL_PORTS[@]}"; do
  api GET "http://$HOST:$PORT/health"     "health_$PORT"
  api GET "http://$HOST:$PORT/v1/models"  "models_$PORT"
  api GET "http://$HOST:$PORT/version"    "version_$PORT"
  api GET "http://$HOST:$PORT/metrics"    "metrics_$PORT"
done

# Also probe worker2
log "Step 1b: Worker2 probe"
HOST2="alvis-worker2.c3se.chalmers.se"
for PORT in "${ALL_PORTS[@]}"; do
  if nc -zv -w 3 "$HOST2" "$PORT" 2>/dev/null; then
    api GET "http://$HOST2:$PORT/v1/models" "w2_models_$PORT"
  else
    echo "unreachable" > "$OUTDIR/w2_models_$PORT"
    echo "000" > "$OUTDIR/w2_models_$PORT.code"
    log "  w2:$PORT unreachable"
  fi
done

# ── Step 2: Chat Non-streaming ───────────────────────────────
log "Step 2: Chat completions (non-streaming)"
for PORT in "${CHAT_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  api POST "http://$HOST:$PORT/v1/chat/completions" "chat_${PORT}" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$MODEL\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}],
      \"max_tokens\": 32
    }"
done

# ── Step 3: Chat Streaming ───────────────────────────────────
log "Step 3: Chat completions (streaming)"
for PORT in "${CHAT_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  curl -s -N \
    -X POST "http://$HOST:$PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -D "$OUTDIR/stream_${PORT}.headers" \
    -d "{
      \"model\": \"$MODEL\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}],
      \"max_tokens\": 32,
      \"stream\": true,
      \"stream_options\": {\"include_usage\": true}
    }" > "$OUTDIR/stream_${PORT}" 2>&1
  log "  stream_$PORT done ($(wc -l < "$OUTDIR/stream_${PORT}") lines)"
done

# ── Step 4: Embeddings ───────────────────────────────────────
log "Step 4: Embeddings"
# Single input
api POST "http://$HOST:$EMBED_PORT/v1/embeddings" "embed_single" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-ai/nomic-embed-text-v1.5",
    "input": "Hello world"
  }'

# Batch input
api POST "http://$HOST:$EMBED_PORT/v1/embeddings" "embed_batch" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-ai/nomic-embed-text-v1.5",
    "input": ["Hello world", "Goodbye world", "Test embedding"]
  }'

# Chat on embed port (expect error)
api POST "http://$HOST:$EMBED_PORT/v1/chat/completions" "embed_chat_error" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-ai/nomic-embed-text-v1.5",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 32
  }'

# ── Step 5: Auth & Error Behavior ────────────────────────────
log "Step 5: Auth & error behavior"
PORT="${CHAT_PORTS[0]}"
MODEL="${MODELS_BY_PORT[$PORT]}"

# No auth (already tested in step 2, but explicit)
api POST "http://$HOST:$PORT/v1/chat/completions" "auth_none" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}],
    \"max_tokens\": 8
  }"

# Fake auth header
api POST "http://$HOST:$PORT/v1/chat/completions" "auth_fake" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer fake-key-12345" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}],
    \"max_tokens\": 8
  }"

# Wrong model name
api POST "http://$HOST:$PORT/v1/chat/completions" "err_wrong_model" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nonexistent/model-xyz",
    "messages": [{"role": "user", "content": "Hi"}],
    "max_tokens": 8
  }'

# Missing body
api POST "http://$HOST:$PORT/v1/chat/completions" "err_no_body" \
  -H "Content-Type: application/json"

# Malformed JSON
api POST "http://$HOST:$PORT/v1/chat/completions" "err_malformed" \
  -H "Content-Type: application/json" \
  -d '{broken json}'

# Missing messages field
api POST "http://$HOST:$PORT/v1/chat/completions" "err_no_messages" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"$MODEL\", \"max_tokens\": 8}"

# ── Step 6: Tool/Function Calling ────────────────────────────
log "Step 6: Tool/function calling"
TOOL_PAYLOAD='{
  "messages": [{"role": "user", "content": "What is the weather in Stockholm?"}],
  "max_tokens": 256,
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get current weather for a city",
      "parameters": {
        "type": "object",
        "properties": {
          "city": {"type": "string", "description": "City name"}
        },
        "required": ["city"]
      }
    }
  }],
  "tool_choice": "auto"
}'

for PORT in "${CHAT_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  PAYLOAD=$(echo "$TOOL_PAYLOAD" | jq --arg m "$MODEL" '. + {model: $m}')
  api POST "http://$HOST:$PORT/v1/chat/completions" "tools_${PORT}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
done

# ── Step 7: Metrics Snapshot ─────────────────────────────────
log "Step 7: Metrics snapshot"
for PORT in "${ALL_PORTS[@]}"; do
  curl -s "http://$HOST:$PORT/metrics" 2>/dev/null | \
    grep -E '^vllm:(num_requests|gpu_cache|num_preemptions|avg_generation|num_requests_running|num_requests_waiting)' \
    > "$OUTDIR/metrics_snapshot_$PORT" 2>/dev/null || true
  log "  metrics_$PORT: $(wc -l < "$OUTDIR/metrics_snapshot_$PORT") key metrics"
done

# ══════════════════════════════════════════════════════════════
# Generate compatibility doc
# ══════════════════════════════════════════════════════════════
log "Writing $DOCFILE"

cat > "$DOCFILE" << 'HEADER'
# Alvis vLLM Compatibility Report

> Auto-generated by `scripts/probe-alvis-vllm.sh` — do not edit manually.
> Re-run the script to refresh.

HEADER

echo "**Generated:** $TIMESTAMP" >> "$DOCFILE"
echo "**Host:** \`$HOST\`" >> "$DOCFILE"
echo "" >> "$DOCFILE"

# ── Connectivity & Discovery ─────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 1. Connectivity & Discovery

### Worker1 Endpoints

EOF

for PORT in "${ALL_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  TYPE="${TYPES_BY_PORT[$PORT]}"
  HEALTH_CODE=$(cat "$OUTDIR/health_$PORT.code" 2>/dev/null || echo "?")
  VERSION=$(cat "$OUTDIR/version_$PORT" 2>/dev/null | jq -r '.version // "?"' 2>/dev/null || echo "?")
  MODELS_RESP=$(cat "$OUTDIR/models_$PORT" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || echo "?")

  cat >> "$DOCFILE" << EOF
#### Port $PORT — $MODEL ($TYPE)

| Check | Result |
|-------|--------|
| Health | HTTP $HEALTH_CODE |
| vLLM version | $VERSION |
| Model ID(s) | \`$MODELS_RESP\` |

EOF
done

# Worker2
echo "### Worker2" >> "$DOCFILE"
echo "" >> "$DOCFILE"
for PORT in "${ALL_PORTS[@]}"; do
  W2_RESP=$(cat "$OUTDIR/w2_models_$PORT" 2>/dev/null || echo "?")
  W2_CODE=$(cat "$OUTDIR/w2_models_$PORT.code" 2>/dev/null || echo "?")
  if [ "$W2_RESP" = "unreachable" ]; then
    echo "- Port $PORT: **unreachable**" >> "$DOCFILE"
  else
    W2_MODELS=$(echo "$W2_RESP" | jq -r '.data[].id' 2>/dev/null || echo "?")
    echo "- Port $PORT: HTTP $W2_CODE — \`$W2_MODELS\`" >> "$DOCFILE"
  fi
done
echo "" >> "$DOCFILE"

# ── Chat Non-streaming ───────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 2. Chat Completions — Non-streaming

EOF

for PORT in "${CHAT_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  CODE=$(cat "$OUTDIR/chat_$PORT.code" 2>/dev/null || echo "?")
  RESP=$(cat "$OUTDIR/chat_$PORT" 2>/dev/null || echo "{}")

  cat >> "$DOCFILE" << EOF
### $MODEL (port $PORT) — HTTP $CODE

\`\`\`json
$(echo "$RESP" | jq '.' 2>/dev/null || echo "$RESP")
\`\`\`

**Fields check:**
EOF

  # Extract key fields
  for FIELD in '.id' '.model' '.usage.prompt_tokens' '.usage.completion_tokens' '.usage.total_tokens' '.choices[0].message.role' '.choices[0].finish_reason'; do
    VAL=$(echo "$RESP" | jq -r "$FIELD" 2>/dev/null || echo "?")
    echo "- \`$FIELD\`: \`$VAL\`" >> "$DOCFILE"
  done

  # Check for extra fields vs standard OpenAI
  EXTRA=$(echo "$RESP" | jq -r 'keys - ["id","object","created","model","choices","usage","system_fingerprint"] | .[]' 2>/dev/null || echo "none")
  echo "- Extra top-level keys: \`${EXTRA:-none}\`" >> "$DOCFILE"
  echo "" >> "$DOCFILE"
done

# ── Chat Streaming ────────────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 3. Chat Completions — Streaming

EOF

for PORT in "${CHAT_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  STREAM_FILE="$OUTDIR/stream_$PORT"
  HEADER_FILE="$OUTDIR/stream_$PORT.headers"
  CT=$(grep -i 'content-type' "$HEADER_FILE" 2>/dev/null | head -1 || echo "?")
  LINE_COUNT=$(wc -l < "$STREAM_FILE" 2>/dev/null || echo "0")
  HAS_DONE=$(grep -c '\[DONE\]' "$STREAM_FILE" 2>/dev/null || echo "0")

  # Extract first and last data lines
  FIRST_CHUNK=$(grep '^data: {' "$STREAM_FILE" 2>/dev/null | head -1 || echo "?")
  LAST_CHUNK=$(grep '^data: {' "$STREAM_FILE" 2>/dev/null | tail -1 || echo "?")
  FIRST_ID=$(echo "$FIRST_CHUNK" | sed 's/^data: //' | jq -r '.id' 2>/dev/null || echo "?")
  USAGE_CHUNK=$(grep 'usage' "$STREAM_FILE" 2>/dev/null | tail -1 || echo "none")

  cat >> "$DOCFILE" << EOF
### $MODEL (port $PORT)

| Check | Result |
|-------|--------|
| Content-Type | \`$CT\` |
| Total SSE lines | $LINE_COUNT |
| \`data: [DONE]\` sentinel | $([ "$HAS_DONE" -gt 0 ] && echo "yes" || echo "no") |
| Chunk ID | \`$FIRST_ID\` |

<details><summary>First chunk</summary>

\`\`\`
$FIRST_CHUNK
\`\`\`
</details>

<details><summary>Last data chunk (usage)</summary>

\`\`\`
$LAST_CHUNK
\`\`\`
</details>

EOF
done

# ── Embeddings ────────────────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 4. Embeddings

EOF

for LABEL in embed_single embed_batch; do
  CODE=$(cat "$OUTDIR/$LABEL.code" 2>/dev/null || echo "?")
  RESP=$(cat "$OUTDIR/$LABEL" 2>/dev/null || echo "{}")
  INPUT_TYPE=$([[ "$LABEL" == *batch* ]] && echo "batch (3 inputs)" || echo "single string")

  cat >> "$DOCFILE" << EOF
### $INPUT_TYPE — HTTP $CODE

\`\`\`json
$(echo "$RESP" | jq 'if .data then .data |= map(.embedding |= (.[0:3] + ["... (truncated)"])) else . end' 2>/dev/null || echo "$RESP")
\`\`\`

EOF

  if [ "$CODE" = "200" ]; then
    DIM=$(echo "$RESP" | jq '.data[0].embedding | length' 2>/dev/null || echo "?")
    PROMPT_TOK=$(echo "$RESP" | jq '.usage.prompt_tokens' 2>/dev/null || echo "?")
    TOTAL_TOK=$(echo "$RESP" | jq '.usage.total_tokens' 2>/dev/null || echo "?")
    NUM_ITEMS=$(echo "$RESP" | jq '.data | length' 2>/dev/null || echo "?")
    echo "- Dimensions: **$DIM**" >> "$DOCFILE"
    echo "- Items returned: $NUM_ITEMS" >> "$DOCFILE"
    echo "- \`usage.prompt_tokens\`: $PROMPT_TOK" >> "$DOCFILE"
    echo "- \`usage.total_tokens\`: $TOTAL_TOK" >> "$DOCFILE"
    echo "" >> "$DOCFILE"
  fi
done

# Chat on embed port
EMBED_CHAT_CODE=$(cat "$OUTDIR/embed_chat_error.code" 2>/dev/null || echo "?")
EMBED_CHAT_RESP=$(cat "$OUTDIR/embed_chat_error" 2>/dev/null || echo "?")
cat >> "$DOCFILE" << EOF
### Chat on embed port — HTTP $EMBED_CHAT_CODE

\`\`\`json
$(echo "$EMBED_CHAT_RESP" | jq '.' 2>/dev/null || echo "$EMBED_CHAT_RESP")
\`\`\`

EOF

# ── Auth & Errors ─────────────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 5. Auth & Error Behavior

EOF

for LABEL in auth_none auth_fake err_wrong_model err_no_body err_malformed err_no_messages; do
  CODE=$(cat "$OUTDIR/$LABEL.code" 2>/dev/null || echo "?")
  RESP=$(cat "$OUTDIR/$LABEL" 2>/dev/null || echo "?")
  DESC=""
  case "$LABEL" in
    auth_none)      DESC="No auth header" ;;
    auth_fake)      DESC="Fake Bearer token" ;;
    err_wrong_model) DESC="Wrong model name" ;;
    err_no_body)    DESC="Missing request body" ;;
    err_malformed)  DESC="Malformed JSON" ;;
    err_no_messages) DESC="Missing messages field" ;;
  esac

  cat >> "$DOCFILE" << EOF
### $DESC — HTTP $CODE

\`\`\`json
$(echo "$RESP" | jq '.' 2>/dev/null || echo "$RESP")
\`\`\`

EOF
done

# ── Tool Calling ──────────────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 6. Tool/Function Calling

EOF

for PORT in "${CHAT_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  CODE=$(cat "$OUTDIR/tools_$PORT.code" 2>/dev/null || echo "?")
  RESP=$(cat "$OUTDIR/tools_$PORT" 2>/dev/null || echo "{}")
  FINISH=$(echo "$RESP" | jq -r '.choices[0].finish_reason' 2>/dev/null || echo "?")
  TOOL_CALLS=$(echo "$RESP" | jq -r '.choices[0].message.tool_calls // "null"' 2>/dev/null || echo "null")

  cat >> "$DOCFILE" << EOF
### $MODEL (port $PORT) — HTTP $CODE

- \`finish_reason\`: \`$FINISH\`
- \`tool_calls\`: $([ "$TOOL_CALLS" != "null" ] && echo "**supported**" || echo "**not returned**")

<details><summary>Full response</summary>

\`\`\`json
$(echo "$RESP" | jq '.' 2>/dev/null || echo "$RESP")
\`\`\`
</details>

EOF
done

# ── Metrics Snapshot ──────────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 7. Capacity Snapshot

EOF

for PORT in "${ALL_PORTS[@]}"; do
  MODEL="${MODELS_BY_PORT[$PORT]}"
  METRICS_FILE="$OUTDIR/metrics_snapshot_$PORT"

  cat >> "$DOCFILE" << EOF
### $MODEL (port $PORT)

\`\`\`
$(cat "$METRICS_FILE" 2>/dev/null || echo "no metrics available")
\`\`\`

EOF
done

# ── Summary ───────────────────────────────────────────────────
cat >> "$DOCFILE" << 'EOF'
## 8. Summary — Differences vs Standard OpenAI API

| Aspect | OpenAI | vLLM (observed) | Notes |
|--------|--------|-----------------|-------|
| Auth | Required (Bearer) | TBD | |
| Model IDs | `gpt-4o`, etc. | HuggingFace paths | |
| Streaming usage | `stream_options` | TBD | |
| Tool calling | All models | TBD | |
| Embeddings | `/v1/embeddings` | TBD | |
| Extra fields | `system_fingerprint` | TBD | |

> **TBD** fields will be filled after successful probe run.
EOF

log "Done! Output: $DOCFILE"
log "Raw probe data preserved in: $OUTDIR"
echo ""
echo "Probe complete. Review: $DOCFILE"
