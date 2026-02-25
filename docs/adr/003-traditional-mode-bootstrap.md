# ADR-003: Traditional Mode with Bootstrap Script

**Status:** Accepted
**Date:** 2025-02-25

## Context

APISIX supports two deployment modes:
1. **Standalone mode:** Declarative config via `apisix.yaml`, requires container restart on changes
2. **Traditional mode:** Config stored in etcd, changes via Admin API, no restart needed

We need to manage routes, consumers, and consumer groups dynamically without service interruption.

## Decision

Use Traditional mode with etcd, plus a bootstrap script for Infrastructure-as-Code.

**Runtime:** Config stored in etcd, modified via Admin API (no restarts).

**IaC:** `services/apisix/scripts/bootstrap.sh` loads routes, consumer-groups, and plugin-metadata from JSON files to Admin API using `envsubst` for secret injection.

**Persistence model:**
- Routes, consumer-groups, plugin-metadata: Defined in repo JSON files, loaded via bootstrap
- Consumers (users + credentials): Created via Portal, stored only in etcd

**Recovery scenarios:**
| Scenario | Recovery |
|----------|----------|
| Container crash, etcd volume survives | Restart container, state intact |
| etcd volume lost | Run bootstrap (restores routes/groups), consumers must be recreated via Portal |

## Consequences

**Easier:**
- Add/modify routes without container restart
- Portal can create consumers dynamically
- Bootstrap provides repeatable "known good state"
- `envsubst` injects secrets at bootstrap time (not baked into images)

**Harder:**
- etcd adds operational complexity (volume management critical)
- Consumers not in repo (must recreate if etcd lost)
- Bootstrap is additive by default (use `--clean` for full reset)

## Alternatives Considered

**Standalone mode with apisix.yaml:**
- Rejected: Requires container restart for any config change
- Rejected: Can't dynamically add consumers without restart
- Rejected: Poor fit for self-service portal model

**External config management (Consul, Redis):**
- Rejected: Adds dependencies beyond etcd (which APISIX requires anyway)
- Rejected: Increased operational complexity

**Store consumers in repo:**
- Rejected: Credentials in repo is security risk
- Rejected: Self-service model requires dynamic consumer creation
