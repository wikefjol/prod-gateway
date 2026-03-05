# ADR Index

| ADR | Title | Summary |
|---|---|---|
| [000](000-template.md) | Template | Blank template for new ADRs |
| [001](001-unified-llm-endpoint.md) | Unified LLM Endpoint with Model-Based Routing | Single `/v1/chat/completions` route; model field selects upstream |
| [002](002-custom-lua-plugins.md) | Custom Lua Plugins | Extend APISIX with custom Lua instead of chaining built-ins |
| [003](003-traditional-mode-bootstrap.md) | Traditional Mode with Bootstrap Script | Use APISIX traditional mode + `bootstrap.sh` over declarative config |
| [004](004-portal-route-structure.md) | Portal Route Structure | Portal routes served under `/portal/` prefix via APISIX |
| [005](005-documentation-strategy.md) | Documentation Strategy | One-fact-one-place policy; doc ownership per file type |
| [006](006-vllm-multi-port-routing.md) | vLLM Multi-Port Routing Strategy | One route per model at priority 11; scaling options discussed |
| [007](007-black-box-testing.md) | Black-Box Testing with Characterization Fixtures | Capture real gateway responses as fixtures; test against those; commit to git |
| [008](008-swag-reverse-proxy.md) | SWAG Reverse Proxy | Replace host-level Apache2 with in-repo SWAG container; multi-network routing by domain |
| [009](009-mkdocs-direct-routing.md) | MkDocs Direct Routing via SWAG | Serve docs at /docs/ via SWAG directly, bypassing APISIX; public content, no auth |
