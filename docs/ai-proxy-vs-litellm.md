# ai-proxy vs litellm: Jämförelse

## Rutter

| | ai-proxy | litellm |
|--|----------|---------|
| **Antal routefiler (json)** | 3 (openai, anthropic, models) | 2 (chat, models) |
| **Rutt per provider** | Ja | Nej |
| **Routing-logik** | `vars` + regex på model | LiteLLM internt |
| **Upstream-config** | Nej (ai-proxy hanterar) | Ja |

## Custom Plugins

| | ai-proxy | litellm |
|--|----------|---------|
| **model-policy.lua** | Krävs (199 rader) | Nej |
| **billing-extractor.lua** | Nej | Krävs (237 rader) |
| **provider-response-id.lua** | Ja | Nej |

## Infrastruktur

| | ai-proxy | litellm |
|--|----------|---------|
| **Extern tjänst** | Ingen | LiteLLM container |
| **Modellregister** | Lua-fil (hårdkodat) | LiteLLM config |
| **Ny provider** | Ny route + uppdatera regex | LiteLLM config |
| **Ny modell** | Uppdatera MODEL_REGISTRY | LiteLLM config |

## Rekommendation

**ai-proxy passar bättre när:**
- Få providers (2-3)
- Allt i APISIX (ingen extra tjänst)
- Stabil modellista

**litellm passar bättre när:**
- Många providers/modeller
- Centraliserad modellhantering önskas
- LiteLLM redan körs
- Behöver LiteLLM-features (load balancing, fallbacks, caching)
