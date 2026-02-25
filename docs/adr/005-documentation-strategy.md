# ADR-005: Documentation Strategy

**Status:** Accepted
**Date:** 2026-02-25

## Context

9 doc files (1508 lines) with heavy overlap and duplication of code-level facts (model lists, plugin configs, route tables). Every route change required ~6 doc updates — chronic drift and unsustainable maintenance.

## Decision

Consolidate to 5 docs + diagrams dir + ADRs. Apply "one fact, one place" principle: code-level facts live in code, docs reference rather than restate.

**Kept:**
- `README.md` — quick start, endpoint table, project structure
- `docs/CLAUDE.md` — agent onboarding, dev workflow, doc policy
- `docs/USER_GUIDE.md` — user-facing API reference (merged from llm-gateway-api.md)
- `docs/gateway-architecture.md` — architecture reference (rewritten ~150 lines)
- `docs/adr/` — architectural decisions

**Deleted:**
- `docs/plugin-inventory.md` → plugin docs move to Lua header comments
- `docs/llm-gateway-api.md` → unique content merged into USER_GUIDE.md
- `routes.txt` → replaced by `ctl.sh routes`
- `CLEANUP-WORKFLOW.md` → historical, cleanup sprint done
- `docs/diagrams.md` → split into `docs/diagrams/` (one file per diagram)

**New:**
- `docs/diagrams/` — one diagram per file for focused diffs and agent maintainability

**Plugin docs:** Structured header comments in Lua files (Purpose, Phase, Priority, Schema, Ctx vars set). Not separate doc files.

## Consequences

- Route changes: update 1–3 docs instead of 6
- Model list: one place only (`model-policy.lua` MODEL_REGISTRY)
- Plugin config: one place only (Lua header + actual schema)
- New contributors read CLAUDE.md → ADRs, not a sprawling wiki
- Diagrams easier to maintain (one change, one file)

## Alternatives Considered

- **Keep all files, just prune content:** still requires 6-file updates per route change
- **Single mega-doc:** poor discoverability, merge conflicts
- **External wiki:** disconnected from code, same drift problem
