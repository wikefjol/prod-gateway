# APISIX Gateway - Dev/Test Environment Split

Dual-environment APISIX setup for development and testing on a single machine.

## Quick Start

```bash
# Start both environments
./scripts/start-both.sh

# Inspect environments
./apisix-inspect.sh -e dev -l summary
./apisix-inspect.sh -e test -l summary

# Stop environments
./scripts/stop-env.sh both
```

## Environment Details

| Environment | Gateway | Admin API | Network |
|-------------|---------|-----------|---------|
| Development | :9080   | :9180     | apisix-dev |
| Test        | :9081   | :9181     | apisix-test |

## Architecture

- **Complete isolation**: Separate etcd, networks, and configurations
- **Profile-based**: Uses custom profile system for environment selection
- **Docker Compose**: Independent compose files per environment
- **Management scripts**: Simple start/stop/inspect commands

## Files

- `docker-compose.{dev,test}.yml` - Environment services
- `apisix/config-{dev,test}-static.yaml` - Static configurations
- `scripts/` - Management utilities
- `current_state.md` - Detailed documentation

## Usage

See `current_state.md` for complete documentation including admin API keys, troubleshooting, and implementation details.