# Pre-Rebase Audit Report

Generated: 2026-02-13

This report consolidates findings from three automated analyses: Code Quality, Legacy Identification, and Security Audit.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Legacy Identifier Analysis](#legacy-identifier-analysis)
3. [Code Quality Analysis](#code-quality-analysis)
4. [Security Audit](#security-audit)
5. [Recommended Actions](#recommended-actions)

---

## Executive Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Security | 1 | 1 | 4 | 3 |
| Legacy | 0 | 2 | 1 | 2 |
| Code Quality | 0 | 2 | 3 | 3 |

**Key Blockers for Rebase:**
- 13 orphaned route files to delete
- 8 new files to stage
- 3 deleted files to commit
- Log path inconsistency across routes

---

## Legacy Identifier Analysis

### 1. Orphaned Route Files (Not in bootstrap.sh)

Routes that exist in `services/apisix/routes/` but are NOT loaded by `bootstrap.sh`:

| File | URI Pattern | Status |
|------|-------------|--------|
| `ai-chat-fallback.json` | `/ai/v1/chat/completions` | Orphaned - old `/ai/*` namespace |
| `openwebui-direct.json` | `/openwebui/direct/v1/*` | Orphaned - deprecated per routes.txt |
| `openwebui-route.json` | `/webui/*` | Orphaned - OIDC proxy to openwebui:8080 |
| `openwebui-central.json` | `/openwebui/central/v1/*` | Orphaned - deprecated per routes.txt |
| `openwebui-redirect-route.json` | `/webui` | Orphaned - redirect helper |
| `provider-anthropic-count-tokens.json` | `/provider/anthropic/v1/messages/count_tokens` | Orphaned - deprecated per routes.txt |
| `provider-anthropic-models.json` | `/provider/anthropic/v1/models` | Orphaned - deprecated per routes.txt |
| `provider-anthropic-messages.json` | `/provider/anthropic/v1/messages` | Orphaned - deprecated per routes.txt |
| `provider-anthropic-openai.json` | `/provider/anthropic/openai/v1/*` | Orphaned - deprecated per routes.txt |
| `provider-litellm.json` | `/provider/litellm/*` | Orphaned - deprecated per routes.txt |
| `provider-openai-models.json` | `/provider/openai/v1/models` | Orphaned - deprecated per routes.txt |
| `provider-openai-chat.json` | `/provider/openai/v1/chat/completions` | Orphaned - deprecated per routes.txt |
| `provider-openai-responses.json` | `/provider/openai/v1/responses` | Orphaned - deprecated per routes.txt |

**Active routes in bootstrap.sh:**
- Core: `health-route.json`, `portal-redirect-route.json`, `oidc-generic-route.json`, `root-redirect-route.json`
- LLM: `llm-litellm-chat.json`, `llm-litellm-models.json`, `llm-ai-proxy-chat-openai.json`, `llm-ai-proxy-chat-anthropic.json`, `llm-ai-proxy-models.json`, `llm-claude-code-messages.json`, `llm-claude-code-count-tokens.json`

### 2. Deprecated URI Patterns

| Old Pattern | New Pattern | Notes |
|-------------|-------------|-------|
| `/ai/v1/*` | `/llm/ai-proxy/v1/*` | Deleted files (ai-chat-anthropic.json, ai-chat-openai.json, ai-models.json), fallback still exists |
| `/provider/*` | `/llm/*` | 9 orphaned `provider-*.json` routes |
| `/openwebui/*` | N/A | OpenWebUI integration deprecated |

### 3. Variable Naming Inconsistency

#### file-logger.json uses mixed naming:
- `$billing_provider` - old `billing_*` prefix
- `$llm_model`, `$llm_prompt_tokens`, `$llm_completion_tokens` - new `llm_*` prefix

#### billing-extractor.lua registers both:
- Old: `billing_model`, `billing_provider_response_id`, `billing_usage_json`, `billing_provider`, `billing_endpoint`, `billing_is_streaming`, `billing_usage_present`
- New: `llm_model`, `llm_prompt_tokens`, `llm_completion_tokens`, `request_llm_model`

**Note:** Dual registration is intentional for backward compatibility during migration.

### 4. Git Status - Files to Commit

#### Deleted files (staged for deletion):
```
D  services/apisix/routes/ai-chat-anthropic.json
D  services/apisix/routes/ai-chat-openai.json
D  services/apisix/routes/ai-models.json
```

#### Modified files (unstaged):
```
M  infra/ctl/ctl.sh
M  routes.txt
M  services/apisix/Dockerfile
M  services/apisix/compose.yaml
M  services/apisix/config.yaml
M  services/apisix/consumer-groups/base-user-group.json
M  services/apisix/consumer-groups/premium-user-group.json
M  services/apisix/lua/apisix/plugins/auth-transform.lua
M  services/apisix/lua/apisix/plugins/billing-extractor.lua
M  services/apisix/lua/apisix/plugins/model-policy.lua
M  services/apisix/lua/apisix/plugins/response-wiretap.lua
M  services/apisix/plugin-metadata/file-logger.json
M  services/apisix/scripts/bootstrap.sh
M  services/portal/templates/dashboard.html
```

#### Untracked files - candidates for git add:
```
services/apisix/lua/apisix/plugins/provider-response-id.lua  (new plugin)
services/apisix/routes/llm-ai-proxy-chat-anthropic.json
services/apisix/routes/llm-ai-proxy-chat-openai.json
services/apisix/routes/llm-ai-proxy-models.json
services/apisix/routes/llm-claude-code-count-tokens.json
services/apisix/routes/llm-claude-code-messages.json
services/apisix/routes/llm-litellm-chat.json
services/apisix/routes/llm-litellm-models.json
utils/learning-tests/  (directory)
```

#### Untracked files - candidates for .gitignore:
```
.claude_session_id.env   (session file, should be gitignored)
docs/*.md                (6 doc files - decide: add or gitignore)
```

### 5. TODO/FIXME Comments

| File | Content |
|------|---------|
| `services/openwebui/compose.yaml` | `# TODO: implement` |
| `services/litellm/compose.yaml` | `# TODO: implement` |

### 6. Plugin-Related Findings

#### stream-usage-injector.lua
- Referenced only by **orphaned routes**: `provider-openai-chat.json`, `provider-anthropic-openai.json`, `openwebui-central.json`, `openwebui-direct.json`
- Active `/llm/*` routes do NOT use this plugin
- **Candidate for removal** once orphaned routes are deleted

#### Enabled plugins in config.yaml not used by active routes:
- `ai-proxy-multi` - enabled but no routes use it
- `stream-usage-injector` - only used by orphaned routes

---

## Code Quality Analysis

### 1. Lua Plugins Analysis

#### 1.1 Inconsistent Patterns Between Plugins

| Issue | Details | Affected Files |
|-------|---------|----------------|
| Priority values inconsistent | `response-wiretap.lua` states priority 900 but header comment says 500 | `response-wiretap.lua` vs `plugin-inventory.md` |
| Schema validation pattern | `check_schema` function: some use `schema_type` param, none actually use it | All plugins |
| Logging style varies | `auth-transform` uses `core.log.info`, `billing-extractor` uses `core.log.warn` for similar info-level messages | Multiple plugins |
| cjson import inconsistency | Some use `require("cjson.safe")`, while `model-policy` and `openai-auth` use `core.json.encode` | See table below |

**JSON encoding/decoding inconsistency:**

| Plugin | Uses cjson.safe | Uses core.json |
|--------|-----------------|----------------|
| billing-extractor.lua | Yes (decode) | No |
| model-policy.lua | Yes (decode) | Yes (encode) |
| openai-auth.lua | No | Yes (encode) |
| provider-response-id.lua | Yes | No |
| response-wiretap.lua | Yes | No |
| stream-usage-injector.lua | Yes | No |

#### 1.2 Code Duplication - SSE Parsing

**Critical duplication**: Four plugins implement SSE parsing with nearly identical logic.

| Plugin | SSE Buffer | Line Parsing | Frame Extraction |
|--------|------------|--------------|------------------|
| `billing-extractor.lua` | `ctx._sse_buf` | Lines 108-126 | Lines 152-179 |
| `provider-response-id.lua` | `ctx._prid_buf` | Lines 34-59 | Lines 62-84 |
| `response-wiretap.lua` | `ctx._wiretap_sse_buf` | Lines 104-126 | Lines 128-166 |
| `stream-usage-injector.lua` | `ctx._sui_buf` | Lines 81-98 | Lines 117-148, 151-192 |

**Specific duplication examples:**

1. **Buffer management pattern** (appears 4 times):
```lua
ctx._xxx_buf = (ctx._xxx_buf or "") .. chunk
-- ... find last newline ...
if #ctx._xxx_buf > 32768 then
    ctx._xxx_buf = ctx._xxx_buf:sub(-32768)
end
```

2. **SSE line parsing** (appears 3 times):
```lua
line = line:gsub("\r$", "")
if not line:match("^data:") then return end
local json_str = line:match("^data:%s*(.+)$")
if not json_str or json_str == "[DONE]" then return end
```

3. **Frame delimiter detection** (appears 3 times):
```lua
local frame_end = buf:find("\n\n", pos, true)
if not frame_end then
    frame_end = buf:find("\r\n\r\n", pos, true)
end
```

#### 1.3 Missing Error Handling

| Plugin | Location | Issue |
|--------|----------|-------|
| `response-wiretap.lua` | Line 200 | `io.open` failure logged but file handle not checked before close |
| `response-wiretap.lua` | Line 79 | `core.request.get_body()` error discarded silently |
| `stream-usage-injector.lua` | Line 33 | `core.request.get_body()` error not logged |
| `billing-extractor.lua` | Line 73-77 | Body parsing failures set flag but no debug logging |
| `provider-response-id.lua` | Line 110 | `cjson.decode` failure returns nil, not logged |

#### 1.4 Unused Variables/Functions

| Plugin | Issue |
|--------|-------|
| `auth-transform.lua` | `schema_type` param in `check_schema` never used |
| `model-policy.lua` | `schema_type` param in `check_schema` never used |
| `openai-auth.lua` | `schema_type` param in `check_schema` never used |
| `response-wiretap.lua` | `conf` not used in several places |
| `billing-extractor.lua` | `err` from `core.request.get_body()` discarded |

#### 1.5 Potential Bugs

| Plugin | Line | Issue |
|--------|------|-------|
| `stream-usage-injector.lua` | 129 | Frame delimiter offset calculation differs from other plugins |
| `response-wiretap.lua` | Line 46 | Schema has `always_capture` property used in routes but not defined in schema |

### 2. Route JSON Files Analysis

#### 2.1 Inconsistent Plugin Configurations

**Auth approach inconsistency:**

| Route Pattern | Auth Plugin | Auth Transform |
|---------------|-------------|----------------|
| `/llm/ai-proxy/*` | `openai-auth` | `auth-transform` plugin |
| `/llm/litellm/*` | `openai-auth` | `auth-transform` plugin |
| `/llm/claude-code/*` | `key-auth` | `auth-transform` plugin |
| `/provider/anthropic/v1/messages` | `key-auth` | `serverless-pre-function` inline |
| `/provider/openai/*` | `openai-auth` | `serverless-pre-function` inline |

**Logging path inconsistency:**

| Route | file-logger path | Pattern |
|-------|------------------|---------|
| `llm-claude-code-messages.json` | `/var/log/apisix/billing/llm-claude-code.log` | `/var/log/apisix/` |
| `llm-ai-proxy-chat-openai.json` | `/usr/local/apisix/logs/billing/llm-ai-proxy-chat.log` | `/usr/local/apisix/logs/` |
| `provider-anthropic-messages.json` | `/var/log/apisix/billing/anthropic-messages.log` | `/var/log/apisix/` |

#### 2.2 response-wiretap Schema Mismatch

Routes use `always_capture: true` but plugin schema does not define this property.

#### 2.3 CORS Configuration vs Documentation

Per `docs/gateway-sprint-plan.md`: "CORS is NOT enabled on /llm/* routes"

But actual routes have CORS enabled on all `/llm/*` routes.

#### 2.4 Hardcoded upstream in provider-litellm.json

`provider-litellm.json` has hardcoded upstream `anast.ita.chalmers.se:4000` while other LiteLLM routes use `$LITELLM_HOST:$LITELLM_PORT`.

### 3. Documentation Analysis

#### 3.1 Outdated Information

| Document | Issue |
|----------|-------|
| `ai-proxy-model-routing.md` | References deleted route files |
| `ai-proxy-model-routing.md` | Documents `/ai/v1/*` routes but current implementation uses `/llm/ai-proxy/v1/*` |
| `gateway-architecture.md` | References old `/ai/v1/*` routes in section 4 |
| `gateway-architecture.md` | Lists route files that no longer exist |
| `plugin-inventory.md` | `response-wiretap` listed as priority 500 but code shows 900 |
| `llm-gateway-api.md` | Lists `gpt-3.5-turbo` but MODEL_REGISTRY has `gpt-3.5-turbo-0125` |
| `gateway-sprint-plan.md` | Says "CORS is NOT enabled" but routes have CORS |

---

## Security Audit

### 1. Credential Exposure

#### CRITICAL: Hardcoded Secrets in .env.dev

**File:** `infra/env/.env.dev`

**Severity:** CRITICAL

**Finding:** Production API keys are hardcoded in plaintext:
- OIDC_CLIENT_SECRET
- OIDC_SESSION_SECRET
- LITELLM_KEY
- ANTHROPIC_API_KEY
- OPENAI_API_KEY

**Mitigating Factor:** `.gitignore` includes `infra/env/.env.*`

**Recommendation:**
- Rotate all exposed keys immediately
- Use external secrets manager
- Add pre-commit hooks to prevent accidental secret commits

#### HIGH: ADMIN_KEY Default Value

**Files:** `infra/env/.env.dev`, `.env.test`

**Severity:** HIGH

**Finding:** Admin API key has hardcoded default fallback:
```
ADMIN_KEY=${ADMIN_KEY:-edd1c9f034335f136f87ad84b625c8f1}
```

**Recommendation:** Remove default value; require explicit setting.

#### MEDIUM: SSL Verification Disabled for OIDC

**File:** `services/apisix/routes/oidc-generic-route.json`

**Severity:** MEDIUM

**Finding:** `ssl_verify: false`

**Recommendation:** Enable `ssl_verify: true` for production.

#### LOW: etcd Without Authentication

**File:** `services/apisix/compose.yaml`

**Severity:** LOW (mitigated by network isolation)

**Finding:** `ALLOW_NONE_AUTHENTICATION: "yes"`

### 2. Route Security

#### MEDIUM: Overly Permissive CORS

**Files:** All `/llm/*` route files

**Severity:** MEDIUM

**Finding:** `allow_origins: "*"` on all LLM routes

**Recommendation:** Restrict to known trusted origins.

#### LOW: Health Route Proxies to External Service

**File:** `services/apisix/routes/health-route.json`

**Severity:** LOW

**Finding:** Health check uses `httpbin.org:443`

**Recommendation:** Implement local health check endpoint.

#### INFO: Positive Findings
- All LLM routes require authentication
- Consumer groups implement rate limiting

### 3. Log Security

#### MEDIUM: Response Wiretap Captures Full Bodies

**File:** `services/apisix/lua/apisix/plugins/response-wiretap.lua`

**Severity:** MEDIUM

**Finding:** Captures full API response bodies including potentially sensitive LLM completions.

**Mitigating Factor:** Requires explicit `X-Debug-Capture: 1` header (opt-in).

**Recommendation:** Implement retention policy, consider log encryption.

#### LOW: Billing Logs Contain Consumer Identity

**File:** `services/apisix/plugin-metadata/file-logger.json`

**Severity:** LOW

**Finding:** Consumer name (OIDC user OID) logged for billing.

**Positive:** Logs do NOT contain API keys, request/response content, or upstream provider keys.

### 4. Portal Security

#### MEDIUM: Dev Mode Environment Check

**File:** `services/portal/src/app.py`

**Severity:** MEDIUM

**Finding:** DEV_MODE only blocked in `production`, `prod`, `live` environments. Staging not blocked.

**Recommendation:** Default to deny; only allow in explicit `local` or `development` environment.

### Security Summary Table

| Finding | Severity | Status |
|---------|----------|--------|
| Hardcoded production secrets in .env.dev | CRITICAL | Action Required |
| ADMIN_KEY has weak default | HIGH | Action Required |
| CORS allow_origins: "*" on LLM routes | MEDIUM | Review Required |
| SSL verification disabled for OIDC | MEDIUM | Review Required |
| Response wiretap captures full bodies | MEDIUM | Monitor (opt-in gated) |
| Dev mode not blocked in staging | MEDIUM | Review Required |
| Health check uses external httpbin.org | LOW | Improve |
| etcd without authentication | LOW | Acceptable if isolated |
| Consumer identity in billing logs | LOW | Acceptable |

---

## Recommended Actions

### Critical (Before Rebase)

1. **Rotate all API keys** exposed in `.env.dev`
2. **Delete 13 orphaned route files** (`provider-*`, `openwebui-*`, `ai-chat-fallback`)
3. **Stage 8 new files** for commit
4. **Fix log path inconsistency** - standardize to `/usr/local/apisix/logs/`

### High Priority

1. Remove ADMIN_KEY default fallback value
2. Fix `response-wiretap` schema (add `always_capture` or remove from routes)
3. Update documentation to reflect new `/llm/*` route structure

### Medium Priority

1. Restrict CORS origins to known domains
2. Enable SSL verification for OIDC in production
3. Extract shared SSE parsing module to reduce duplication
4. Standardize on plugins vs inline Lua

### Low Priority

1. Replace httpbin.org health check with local endpoint
2. Remove unused plugins from config.yaml (`ai-proxy-multi`, `stream-usage-injector`)
3. Clean up placeholder services (`services/litellm/`, `services/openwebui/`)

---

## Git Commands Summary

```bash
# Stage new files
git add services/apisix/routes/llm-*.json
git add services/apisix/lua/apisix/plugins/provider-response-id.lua
git add docs/*.md

# Confirm deletions already staged
git status services/apisix/routes/ai-*.json

# Delete orphaned routes
rm services/apisix/routes/provider-*.json
rm services/apisix/routes/openwebui-*.json
rm services/apisix/routes/ai-chat-fallback.json

# Update .gitignore
echo ".claude_session_id.env" >> .gitignore

# Stage all changes
git add -A
```
