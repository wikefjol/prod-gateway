# APISIX Gateway - Dev/Test Environment Split

Dual-environment APISIX setup for development and testing with complete isolation.

## Quick Start

```bash
# Start individual environments
./scripts/start-dev.sh    # Development environment
./scripts/start-test.sh   # Test environment

# Start both environments
./scripts/start-both.sh

# Inspect environments
./apisix-inspect.sh -e dev -l summary
./apisix-inspect.sh -e test -l summary

# Stop environments
./scripts/stop-env.sh dev|test|both
```

## Environment Details

| Environment | Gateway | Admin API | Network | Features |
|-------------|---------|-----------|---------|----------|
| Development | :9080   | :9180     | apisix-dev | OIDC authentication |
| Test        | :9081   | :9181     | apisix-test | Clean slate |

## File Structure

### Environment Services
- `docker-compose.dev.yml` - Development services (etcd-dev, apisix-dev, loader-dev)
- `docker-compose.test.yml` - Test services (etcd-test, apisix-test)

### Configuration
- `.dev.env` - Development environment variables (ports, keys, Azure OIDC config)
- `.test.env` - Test environment variables (isolated ports/keys)
- `admin.env` - Shared admin API keys
- `apisix/config-{dev,test}-static.yaml` - Static APISIX configurations
- `apisix/config-template.yaml` - Configuration template

### Scripts & Tools
- `scripts/start-{dev,test,both}.sh` - Environment startup scripts
- `scripts/stop-env.sh` - Stop script for all environments
- `scripts/bootstrap-oidc-dev.sh` - OIDC route provisioning for dev
- `apisix-inspect.sh` - Multi-environment inspection tool

### Container Setup
- `apisix/Dockerfile` - Custom APISIX image build
- `apisix/entrypoint-simple.sh` - Container entrypoint with profile-based config

### Legacy Files
- `bin/` - Archived legacy files (safe to ignore)

## Architecture

- **Complete isolation**: Separate etcd, networks, volumes, and configurations
- **Profile-based**: Uses `CUSTOM_PROFILE` environment variable for config selection
- **Infrastructure as Code**: OIDC routes provisioned via sidecar loader pattern
- **Port separation**: Dev (908x), Test (918x) - no conflicts