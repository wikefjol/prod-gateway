# APISIX Gateway Maintainer's Guide

This comprehensive guide is for maintainers who need to operate, modify, troubleshoot, and extend the APISIX Gateway system. It provides detailed technical information, operational procedures, and architectural guidance.

## 📋 Table of Contents

- [System Overview for Maintainers](#system-overview-for-maintainers)
- [File Organization & Structure](#file-organization--structure)
- [CLI Operations Guide](#cli-operations-guide)
- [Configuration Management](#configuration-management)
- [Environment Management](#environment-management)
- [Container Architecture](#container-architecture)
- [Route Management](#route-management)
- [Security Model](#security-model)
- [Operational Procedures](#operational-procedures)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Modification Procedures](#modification-procedures)
- [Testing & Validation](#testing--validation)
- [Performance Monitoring](#performance-monitoring)
- [Backup & Recovery](#backup--recovery)
- [Upgrade Procedures](#upgrade-procedures)

---

## System Overview for Maintainers

### Architecture Layers

1. **Presentation Layer**: Apache HTTP Server (TLS termination, domain routing)
2. **Gateway Layer**: APISIX instances (authentication, routing, proxying)
3. **Application Layer**: Portal Backend (API key management)
4. **Data Layer**: etcd (configuration storage)
5. **External Services**: OIDC providers, AI providers

### Critical Design Principles

- **Environment Isolation**: Complete separation using Docker Compose projects
- **Security First**: Admin APIs bound to localhost, proper authentication flows
- **Configuration as Code**: All settings managed through version-controlled files
- **Provider Abstraction**: Clean separation between different OIDC providers
- **Modular Architecture**: Compose files with service profiles for clean deployment

---

## File Organization & Structure

### Root Directory Layout

```
/home/filbern/dev/apisix-gateway/
├── README.md                    # User-facing documentation
├── MAINTAINERS_GUIDE.md         # This file - detailed maintenance guide
├── CLI_USAGE.md                 # CLI usage documentation
├── gw                          # CLI wrapper script (executable)
├── cli/                        # Python CLI implementation
│   ├── gw.py                   # Main CLI application
│   ├── commands/               # CLI command implementations
│   ├── lib/                    # CLI libraries (environment, docker utils)
│   ├── venv/                   # Python virtual environment
│   └── requirements.txt        # Python dependencies
├── apisix/                      # APISIX configuration templates and routes
├── config/                      # Hierarchical configuration system
├── docs/                        # Technical documentation
├── infrastructure/              # Docker Compose infrastructure
├── portal-backend/              # Self-service portal application
├── scripts/                     # Operational scripts
├── secrets/                     # Gitignored credential files
└── tests/                       # Testing framework
```

### Critical Files for Maintainers

| File | Purpose | Modification Frequency |
|------|---------|----------------------|
| `gw` | CLI wrapper script | Never - managed automatically |
| `cli/gw.py` | Main CLI application | Rarely - CLI feature additions |
| `cli/commands/*.py` | CLI command implementations | Occasionally - command enhancements |
| `scripts/core/environment.sh` | Configuration loading engine | Rarely - core system |
| `scripts/lifecycle/start.sh` | Universal startup script | Occasionally - new features |
| `infrastructure/docker/base.yml` | Core Docker services | Rarely - infrastructure changes |
| `config/shared/base.env` | Core APISIX settings | Occasionally - system tuning |
| `portal-backend/src/app.py` | Portal backend implementation | Regularly - feature development |
| `apisix/config-*-template.yaml` | APISIX configuration templates | Occasionally - gateway tuning |

---

## CLI Operations Guide

### CLI Architecture

The CLI is implemented in Python using the Typer framework and provides a unified interface for all gateway operations. It follows these principles:

- **Reliability First**: Uses proven `bootstrap-core.sh` script that maintainers know works
- **Safety by Design**: Explicit environment targeting, safe cleanup defaults
- **Rich UX**: Colored output, progress indicators, comprehensive error messages
- **Thin Wrappers**: Orchestrates existing scripts rather than reimplementing Docker Compose logic

### CLI Command Categories

#### Core Operations
```bash
./gw up dev|test               # Start infrastructure
./gw down dev|test             # Stop environment
./gw reset dev|test            # Complete reset: down → up → bootstrap → verify
./gw bootstrap dev|test        # Deploy routes using bootstrap-core.sh
```

#### Diagnostics and Monitoring
```bash
./gw status [dev|test]         # Container status, service health, routes
./gw env dev|test              # Show environment configuration
./gw doctor dev|test           # Comprehensive health checks
./gw logs dev|test [service]   # View service logs with options
./gw routes dev|test           # List and inspect APISIX routes
```

### CLI Implementation Details

#### Environment Integration
The CLI integrates with the existing environment system using robust subprocess calls:

```python
def load_environment(provider: str, env: str) -> Dict[str, str]:
    """Load environment by calling existing bash setup"""
    cmd = [
        'bash', '-lc',
        f'source scripts/core/environment.sh; '
        f'setup_environment {provider} {env} >/dev/null; '
        f'env -0'
    ]
    # Null-separated output prevents corruption
    # stderr preserved for debugging
```

#### Safety Features Implementation

**Explicit Environment Validation**:
```python
VALID_ENVS = ["dev", "test"]

def validate_env(env: str) -> str:
    if env not in VALID_ENVS:
        console.print(f"[red]❌ Invalid environment: {env}[/red]")
        raise typer.Exit(1)
    return env
```

**Safe Cleanup with Opt-in Global Prune**:
```python
def down_command(env: str, clean: bool = False, prune_global: bool = False):
    # Project-only cleanup by default
    cmd = ["./scripts/lifecycle/stop.sh", "--environment", env]
    if clean:
        cmd.append("--clean")

    # Global prune requires explicit confirmation
    if prune_global and not i_know_what_im_doing:
        console.print("[red]⚠️ WARNING: Global prune will delete ALL stopped containers![/red]")
        if not typer.confirm("Are you sure?"):
            raise typer.Exit(0)
```

### CLI Operations for Maintainers

#### Environment Lifecycle Management

**Complete Environment Reset** (Recommended for maintainers):
```bash
# Reset development environment
./gw reset dev

# Reset with volume cleanup
./gw reset dev --clean

# Deploy with provider routes (requires API keys)
./gw reset dev --with-providers
```

This single command replaces the complex manual workflow:
1. `./gw down dev --clean` - Stop and clean up
2. `./gw up dev` - Start infrastructure
3. Wait for readiness with deterministic gates
4. `./gw bootstrap dev --core-only` - Deploy routes
5. `./gw doctor dev` - Verify deployment

#### System Monitoring and Diagnostics

**Health Assessment**:
```bash
# Quick health overview
./gw status dev

# Comprehensive diagnostics (91.7% healthy is normal)
./gw doctor dev

# Environment configuration debugging
./gw env dev
```

**Real-time Monitoring**:
```bash
# Follow APISIX logs
./gw logs dev apisix --follow

# Check specific service logs
./gw logs dev portal-backend --tail 100

# View route configuration
./gw routes dev --detailed
```

#### Route Management

**Route Inspection**:
```bash
# List all routes with basic info
./gw routes dev

# Detailed view with upstreams and plugins
./gw routes dev --detailed

# Inspect specific route
./gw routes dev --route-id portal-oidc-route
```

**Route Deployment**:
```bash
# Deploy core routes only (default, safe)
./gw bootstrap dev --core-only

# Deploy including provider routes (requires API keys)
./gw bootstrap dev --with-providers

# Routes deployed via proven bootstrap-core.sh script
```

### CLI Maintenance Procedures

#### CLI Dependencies

The CLI uses a Python virtual environment with managed dependencies:

```bash
# Dependencies are handled automatically by wrapper
./gw --help

# Manual dependency management (rarely needed)
source cli/venv/bin/activate
pip install -r cli/requirements.txt

# Update dependencies
pip list --outdated
pip install --upgrade typer rich requests
pip freeze > cli/requirements.txt
```

#### CLI Troubleshooting

**CLI Installation Issues**:
```bash
# Check virtual environment
ls -la cli/venv/bin/python

# Recreate virtual environment if needed
rm -rf cli/venv
python3 -m venv cli/venv
source cli/venv/bin/activate
pip install -r cli/requirements.txt
```

**CLI Command Issues**:
```bash
# Check CLI is executable
ls -la gw

# Run with verbose Python output for debugging
source cli/venv/bin/activate
python -v cli/gw.py status dev
```

#### Adding CLI Commands

**Procedure for New Commands**:

1. **Create Command Module**:
   ```python
   # Create cli/commands/new_command.py
   def new_command(env: str):
       """New command description"""
       console.print(f"[blue]Executing new command for {env}[/blue]")
       # Command implementation
   ```

2. **Register in Main CLI**:
   ```python
   # Edit cli/gw.py
   from commands.new_command import new_command

   @app.command()
   def new(env: str = typer.Argument(..., help="Environment (dev|test)")):
       """New command"""
       env = validate_env(env)
       new_command(env)
   ```

3. **Test Implementation**:
   ```bash
   ./gw new dev
   ./gw --help  # Verify command appears
   ```

### CLI vs Manual Operations

| Operation | CLI Command | Manual Equivalent |
|-----------|-------------|-------------------|
| Complete Reset | `./gw reset dev` | `./scripts/lifecycle/stop.sh && ./scripts/lifecycle/start.sh --provider entraid && ./scripts/bootstrap/bootstrap-core.sh dev` |
| Health Check | `./gw doctor dev` | Multiple docker, curl, and log commands |
| Environment Check | `./gw env dev` | `source scripts/core/environment.sh && setup_environment entraid dev && printenv` |
| Route Inspection | `./gw routes dev --detailed` | `curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes \| jq` |
| Log Monitoring | `./gw logs dev apisix --follow` | `docker logs apisix-dev-apisix-1 -f` |

**Recommendation for Maintainers**: Use CLI commands for all routine operations. The CLI provides better error handling, safety checks, and user experience while maintaining full compatibility with existing scripts.

---

### Configuration Hierarchy

```
config/
├── shared/                      # Common settings (all environments)
│   ├── base.env                # Core APISIX configuration
│   ├── apisix.env              # Admin keys, etcd settings
│   └── test.env                # Test-specific overrides
├── providers/                   # Provider-specific settings
│   ├── entraid/
│   │   ├── dev.env             # EntraID dev configuration
│   │   └── test.env            # EntraID test configuration
│   └── keycloak/
│       └── dev.env             # Keycloak dev configuration
├── env/                         # Environment files for Docker Compose
│   ├── dev.env                 # Dev environment port mappings
│   ├── test.env                # Test environment port mappings
│   ├── dev.complete.env        # Generated complete configuration
│   └── test.complete.env       # Generated complete configuration
└── secrets/                     # Credentials (gitignored)
    ├── entraid-dev.env         # EntraID dev secrets
    ├── entraid-test.env        # EntraID test secrets
    └── entraid-dev.env.example # Example template
```

**⚠️ CRITICAL**: The `secrets/` directory contains production credentials and is gitignored. Always backup these files separately and never commit them to version control.

---

## Configuration Management

### Environment Loading Process

The system uses a sophisticated hierarchical configuration loading process implemented in `scripts/core/environment.sh`:

```bash
setup_environment() {
    local provider="$1"    # keycloak, entraid
    local environment="$2" # dev, test, prod

    # 1. Load shared configuration
    source config/shared/base.env
    source config/shared/apisix.env

    # 2. Load secrets (optional)
    [[ -f "secrets/${provider}-${environment}.env" ]] && \
        source "secrets/${provider}-${environment}.env"

    # 3. Load provider configuration
    source "config/providers/${provider}/${environment}.env"

    # 4. Load environment-specific settings
    source "config/env/${environment}.env"

    # 5. Generate dynamic values and validate
    generate_dynamic_values "$provider" "$environment"
    validate_configuration

    # 6. Create complete environment file
    export COMPOSE_ENV_FILE="config/env/${environment}.complete.env"
}
```

### Key Configuration Variables

#### Core APISIX Settings (`config/shared/base.env`)

```bash
APISIX_NODE_LISTEN=9080              # Gateway port
APISIX_ADMIN_PORT=9180               # Admin API port (SECURITY: localhost only)
APISIX_ENABLE_ADMIN=true             # Enable admin API
APISIX_CONFIG_CENTER=etcd            # Configuration backend
ETCD_HOST=etcd                       # etcd service name
```

#### Security Settings (`config/shared/apisix.env`)

```bash
ADMIN_KEY=your-admin-key             # APISIX admin API key
VIEWER_KEY=your-viewer-key           # Read-only admin access
```

#### Provider-Specific Settings

**EntraID** (`config/providers/entraid/dev.env`):
```bash
OIDC_CLIENT_ID=a8c920fe-3b30-4c77-aef7-17d85a656ea3
OIDC_DISCOVERY_ENDPOINT=https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration
OIDC_REDIRECT_URI=https://your-domain.com/portal/callback
```

**Secrets** (`secrets/entraid-dev.env`):
```bash
OIDC_CLIENT_SECRET=your-client-secret
OIDC_SESSION_SECRET=your-session-secret-32-chars-min
ANTHROPIC_API_KEY=your-anthropic-key
OPENAI_API_KEY=your-openai-key
LITELLM_KEY=your-litellm-key
```

### Modifying Configuration

#### Adding New Environment Variables

1. **Determine Scope**:
   - Shared setting → `config/shared/base.env`
   - Provider-specific → `config/providers/{provider}/{env}.env`
   - Secret → `secrets/{provider}-{env}.env`
   - Environment-specific → `config/env/{env}.env`

2. **Update Templates**: Add to appropriate template file
3. **Update Validation**: Add to `validate_configuration()` in `environment.sh`
4. **Test**: Run configuration loading and verify with `printenv`

#### Changing Port Mappings

**Example**: Changing dev environment from 9080 to 8080

1. Update `config/env/dev.env`:
   ```bash
   APISIX_HOST_GATEWAY_PORT=8080
   ```

2. Update documentation and example commands

3. Test startup and verify accessibility:
   ```bash
   ./scripts/lifecycle/start.sh --environment dev
   curl http://localhost:8080/health
   ```

---

## Environment Management

### Supported Environments

| Environment | Purpose | Port Offset | Docker Project |
|-------------|---------|-------------|----------------|
| dev | Development, feature testing | 9080/9180 | apisix-dev |
| test | Automated testing, QA | 9081/9181 | apisix-test |
| prod | Production (future) | TBD | apisix-prod |

### Environment Lifecycle

#### Starting an Environment

**CLI Approach (Recommended)**:
```bash
# Complete environment setup (recommended)
./gw reset dev

# Start infrastructure only
./gw up dev

# Start with provider routes
./gw reset dev --with-providers
```

**Manual Approach**:
```bash
# Basic startup
./scripts/lifecycle/start.sh --provider entraid --environment dev

# With debug tools
./scripts/lifecycle/start.sh --provider entraid --environment dev --debug

# Force recreation (rebuilds containers)
./scripts/lifecycle/start.sh --provider entraid --environment dev --force-recreate
```

#### Environment State Management

The startup script performs these critical steps:

1. **Pre-flight Checks**: Docker daemon, compose version, project structure
2. **Environment Loading**: Hierarchical configuration loading and validation
3. **Container Cleanup**: Stop existing containers for the project
4. **Service Startup**: Start core services (etcd, apisix, portal-backend)
5. **Health Verification**: Wait for services to become healthy
6. **Route Deployment**: Bootstrap core routes (if requested)

#### Stopping an Environment

**CLI Approach (Recommended)**:
```bash
# Stop environment
./gw down dev

# Stop with cleanup (remove volumes/networks)
./gw down dev --clean

# Stop with global Docker cleanup (dangerous - requires confirmation)
./gw down dev --prune-global
```

**Manual Approach**:
```bash
# Stop current environment
./scripts/lifecycle/stop.sh

# Stop specific environment
COMPOSE_PROJECT_NAME=apisix-test ./scripts/lifecycle/stop.sh
```

### Multi-Environment Operations

#### Running Multiple Environments Simultaneously

```bash
# Start dev environment
./scripts/lifecycle/start.sh --provider entraid --environment dev

# Start test environment (different ports)
./scripts/lifecycle/start.sh --provider entraid --environment test

# Verify both are running
docker ps --filter "name=apisix"
ss -lntp | grep ':908[01]'
```

#### Environment-Specific Operations

```bash
# Load specific environment
source scripts/core/environment.sh
setup_environment "entraid" "dev"

# Deploy routes to specific environment
./scripts/bootstrap/bootstrap-core.sh dev

# Test specific environment
curl http://localhost:${APISIX_HOST_GATEWAY_PORT}/health
```

---

## Container Architecture

### Docker Compose Structure

The system uses **modular Docker Compose files** with **service profiles** for clean separation:

#### Base Infrastructure (`infrastructure/docker/base.yml`)

```yaml
services:
  etcd:           # Configuration storage
  apisix:         # Main gateway
  loader:         # Route loader utility
  portal-backend: # Portal application
```

#### Provider Services (`infrastructure/docker/providers.yml`)

```yaml
services:
  keycloak:       # Local OIDC provider
    profiles: [keycloak]
```

#### Debug Tools (`infrastructure/docker/debug.yml`)

```yaml
services:
  debug-toolkit:    # curl, jq, network tools
    profiles: [debug]
  http-client:      # Simple HTTP client
    profiles: [debug]
```

### Container Naming Convention

**Pattern**: `{project}-{service}-{instance}`

**Examples**:
- `apisix-dev-apisix-1` (dev APISIX gateway)
- `apisix-dev-etcd-1` (dev etcd instance)
- `apisix-dev-portal-backend-1` (dev portal backend)
- `apisix-test-apisix-1` (test APISIX gateway)

### Network Architecture

```
Docker Networks:
├── apisix-dev_default     # Dev environment network
├── apisix-test_default    # Test environment network
└── (host network access for localhost-bound services)

Host Port Bindings:
├── Dev: 9080 (gateway), 9180 (admin), 3001 (portal)
├── Test: 9081 (gateway), 9181 (admin), 3002 (portal)
└── Shared: 8080 (keycloak when active)
```

### Container Security Model

#### Port Binding Security

```yaml
# SECURE: Admin API bound to localhost only
apisix:
  ports:
    - "127.0.0.1:9180:9180"  # Admin API - localhost only
    - "0.0.0.0:9080:9080"    # Gateway - external access OK

# SECURE: etcd not exposed to host
etcd:
  expose:
    - "2379"  # Container network only
```

#### Volume Security

```yaml
# Configuration is read-only from host perspective
volumes:
  - ./config:/opt/config:ro

# Logs are append-only
  - ./logs:/usr/local/apisix/logs:rw
```

### Managing Containers

#### Viewing Container Status

```bash
# All APISIX containers
docker ps --filter "name=apisix"

# Specific environment
docker ps --filter "name=apisix-dev"

# Container resource usage
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

#### Container Logs

```bash
# Follow logs for specific service
docker logs apisix-dev-apisix-1 -f

# View portal backend logs
docker logs apisix-dev-portal-backend-1 -f --tail 100

# View all logs for an environment
docker compose -f infrastructure/docker/base.yml -p apisix-dev logs -f
```

#### Container Maintenance

```bash
# Restart single service
docker compose -f infrastructure/docker/base.yml -p apisix-dev restart apisix

# Update single container
docker compose -f infrastructure/docker/base.yml -p apisix-dev up -d --force-recreate apisix

# Clean up stopped containers
docker container prune -f

# Clean up unused images
docker image prune -f
```

---

## Route Management

### APISIX Route Architecture

Routes are managed through the **Bootstrap System** which deploys JSON route definitions via the Admin API.

#### Route Categories

1. **Core Routes** (Always Deployed):
   - `health-route.json` - System health endpoint
   - `portal-oidc-route.json` - Portal with OIDC authentication
   - `oidc-generic-route.json` - OIDC callback handling
   - `portal-redirect-route.json` - URL normalization
   - `root-redirect-route.json` - Root redirects

2. **Provider Routes** (Optional):
   - `anthropic-route.json` - Claude API proxying
   - `openai-route.json` - GPT API proxying
   - `litellm-route.json` - LiteLLM proxying

#### Route Deployment Process

```bash
# Deploy core routes (required for basic functionality)
source scripts/core/environment.sh
setup_environment "entraid" "dev"
./scripts/bootstrap/bootstrap-core.sh dev

# Deploy provider routes (AI services)
./scripts/bootstrap/bootstrap-providers.sh dev
```

### Route Configuration Details

#### Portal OIDC Route (`apisix/portal-oidc-route.json`)

**Critical Configuration**:
```json
{
  "id": "portal-oidc-route",
  "uri": "/portal/*",
  "methods": ["GET", "POST", "HEAD"],
  "plugins": {
    "openid-connect": {
      "discovery": "$OIDC_DISCOVERY_ENDPOINT",
      "client_id": "$OIDC_CLIENT_ID",
      "client_secret": "$OIDC_CLIENT_SECRET",
      "redirect_uri": "$OIDC_REDIRECT_URI",
      "session": {
        "secret": "$OIDC_SESSION_SECRET"
      },
      "set_id_token_header": true,
      "set_userinfo_header": true,
      "set_access_token_header": true
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "$PORTAL_BACKEND_HOST": 1
    }
  }
}
```

**Key Variables**:
- `$OIDC_DISCOVERY_ENDPOINT` - Provider discovery URL
- `$OIDC_CLIENT_ID` - OAuth client identifier
- `$OIDC_CLIENT_SECRET` - OAuth client secret
- `$OIDC_REDIRECT_URI` - Callback URL after authentication
- `$PORTAL_BACKEND_HOST` - Backend service hostname

#### AI Provider Routes

**Example Anthropic Route** (`apisix/anthropic-route.json`):
```json
{
  "id": "provider-anthropic-chat",
  "uri": "/v1/providers/anthropic/chat",
  "methods": ["POST"],
  "plugins": {
    "key-auth": {},
    "proxy-rewrite": {
      "uri": "/v1/messages",
      "headers": {
        "set": {
          "x-api-key": "$ANTHROPIC_API_KEY",
          "anthropic-version": "2023-06-01"
        },
        "remove": ["apikey"]
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "scheme": "https",
    "nodes": {
      "api.anthropic.com:443": 1
    }
  }
}
```

### Adding New Routes

#### Procedure for Adding Routes

1. **Create Route Definition**:
   ```bash
   # Create new route file
   cat > apisix/my-new-route.json << 'EOF'
   {
     "id": "my-new-route",
     "uri": "/my-endpoint",
     "methods": ["GET"],
     "upstream": {
       "type": "roundrobin",
       "nodes": {
         "my-backend:8080": 1
       }
     }
   }
   EOF
   ```

2. **Add to Bootstrap Script**:
   Edit `scripts/bootstrap/bootstrap-core.sh` (or create new bootstrap script):
   ```bash
   deploy_route "my-new-route" "apisix/my-new-route.json"
   ```

3. **Test Route Deployment**:
   ```bash
   source scripts/core/environment.sh
   setup_environment "entraid" "dev"
   ./scripts/bootstrap/bootstrap-core.sh dev

   # Verify route exists
   curl -H "X-API-KEY: $ADMIN_KEY" \
        http://localhost:9180/apisix/admin/routes/my-new-route
   ```

#### Route Modification

**⚠️ CRITICAL**: Never modify routes directly via Admin API. Always use the JSON files and bootstrap process to ensure consistency across environments.

```bash
# WRONG - direct API modification
curl -X PUT -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes/portal-oidc-route \
     -d '{...}'

# CORRECT - modify JSON file and redeploy
vim apisix/portal-oidc-route.json
./scripts/bootstrap/bootstrap-core.sh dev
```

### Route Troubleshooting

#### Viewing Route Configuration

```bash
# List all routes
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Get specific route
curl -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes/portal-oidc-route

# Pretty-print with jq
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes | jq '.'
```

#### Route Validation Issues

**Common Problems**:
1. **JSON Syntax Errors**: Use `jq` to validate JSON files
2. **Variable Substitution**: Ensure all `$VARIABLE` placeholders are replaced
3. **Upstream Connectivity**: Verify backend services are accessible
4. **Plugin Configuration**: Check plugin syntax against APISIX documentation

**Validation Process**:
```bash
# Validate JSON syntax
jq '.' apisix/portal-oidc-route.json

# Check variable substitution
envsubst < apisix/portal-oidc-route.json | jq '.'

# Test route after deployment
curl -I http://localhost:9080/portal/
```

---

## Security Model

### Security Architecture Overview

The system implements **defense-in-depth** security with multiple layers:

1. **Network Security**: Port binding restrictions and network isolation
2. **Authentication Security**: OIDC and API key authentication
3. **Administrative Security**: Localhost-only admin access
4. **Data Security**: Proper secret management and secure headers

### Critical Security Controls

#### Admin API Security (MOST CRITICAL)

```yaml
# SECURE CONFIGURATION - Admin API localhost binding
apisix:
  ports:
    - "127.0.0.1:9180:9180"  # NEVER change to 0.0.0.0
```

**Why This Matters**: The Admin API provides **full control** over APISIX configuration. External access would allow attackers to:
- Modify routes and redirect traffic
- Access upstream credentials
- Disable authentication
- Create backdoors

**Verification**:
```bash
# Should work (localhost)
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Should fail (external access)
curl -H "X-API-KEY: $ADMIN_KEY" http://$(hostname -I):9180/apisix/admin/routes
```

#### Authentication Flow Security

**Portal Access (OIDC)**:
1. User → `https://domain.com/portal/`
2. APISIX → Check OIDC session
3. If not authenticated → Redirect to OIDC provider
4. User authenticates with OIDC provider
5. Provider → Callback to APISIX with authorization code
6. APISIX → Exchange code for tokens
7. APISIX → Validate tokens and create session
8. APISIX → Inject user headers and forward to backend

**API Access (Key Authentication)**:
1. Client → Request with `apikey: USER_KEY` header
2. APISIX → Validate key against Consumer database
3. APISIX → Add provider-specific authentication headers
4. APISIX → Proxy to upstream API provider

#### Secret Management

**Secret Storage Locations**:
```bash
secrets/
├── entraid-dev.env      # Development secrets
├── entraid-test.env     # Test secrets
└── entraid-prod.env     # Production secrets (not in repo)
```

**Secret Rotation Procedure**:

1. **OIDC Secrets**:
   ```bash
   # Update client secret in provider
   # Update secrets/entraid-{env}.env
   # Restart environment
   ./scripts/lifecycle/start.sh --provider entraid --force-recreate
   ```

2. **APISIX Admin Keys**:
   ```bash
   # Update config/shared/apisix.env
   # Restart all environments
   # Update any automation that uses admin keys
   ```

3. **AI Provider Keys**:
   ```bash
   # Update secrets/{provider}-{env}.env
   # Redeploy provider routes
   ./scripts/bootstrap/bootstrap-providers.sh
   ```

### Security Monitoring

#### Access Logging

```bash
# APISIX access logs
docker logs apisix-dev-apisix-1 | grep -E "(error|warn|fail)"

# Portal backend logs
docker logs apisix-dev-portal-backend-1 | grep -E "ERROR|WARNING"

# Failed authentication attempts
docker logs apisix-dev-apisix-1 | grep -E "oidc|auth.*fail"
```

#### Security Events to Monitor

1. **Admin API Access**: Unusual admin API usage patterns
2. **Authentication Failures**: High rate of OIDC failures
3. **Invalid API Keys**: Attempts to use invalid keys
4. **Unusual Traffic Patterns**: High request volumes to specific endpoints
5. **Configuration Changes**: Unexpected route modifications

### Production Security Hardening

#### Required Production Changes

1. **TLS Termination**:
   ```apache
   # Apache reverse proxy with TLS
   <VirtualHost *:443>
       SSLEngine on
       SSLCertificateFile /path/to/cert.pem
       SSLCertificateKeyFile /path/to/key.pem

       ProxyPass / http://127.0.0.1:9080/
       ProxyPassReverse / http://127.0.0.1:9080/
   </VirtualHost>
   ```

2. **Network Security**:
   ```bash
   # Firewall rules - allow only necessary ports
   ufw allow 80/tcp   # HTTP (redirect to HTTPS)
   ufw allow 443/tcp  # HTTPS
   ufw deny 9180/tcp  # Block admin API (defense in depth)
   ufw deny 9080/tcp  # Block direct gateway access
   ```

3. **Rate Limiting** (add to routes):
   ```json
   "plugins": {
     "limit-req": {
       "rate": 100,
       "burst": 50,
       "rejected_code": 429
     }
   }
   ```

4. **Security Headers**:
   ```json
   "plugins": {
     "response-rewrite": {
       "headers": {
         "set": {
           "X-Frame-Options": "DENY",
           "X-Content-Type-Options": "nosniff",
           "Strict-Transport-Security": "max-age=31536000"
         }
       }
     }
   }
   ```

---

## Operational Procedures

### Daily Operations

#### System Health Check

**CLI Approach (Recommended)**:
```bash
# Complete health assessment (recommended)
./gw doctor dev

# Quick status overview
./gw status dev

# Check environment configuration
./gw env dev

# View recent logs
./gw logs dev apisix --tail 50
```

**Manual Approach**:
```bash
# 1. Container status
docker ps --filter "name=apisix" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 2. Gateway accessibility
curl -f http://localhost:9080/health

# 3. Admin API accessibility
curl -f -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# 4. Portal backend health
curl -f http://localhost:3001/health

# 5. Check disk usage
df -h /var/lib/docker
du -sh ./logs/
```

#### Log Management

```bash
# Rotate logs manually if needed
docker compose -f infrastructure/docker/base.yml -p apisix-dev exec apisix \
    sh -c 'kill -USR1 $(cat /usr/local/apisix/logs/nginx.pid)'

# Archive old logs
tar -czf logs/archive/apisix-logs-$(date +%Y%m%d).tar.gz logs/*.log

# Clean up old archives (keep 30 days)
find logs/archive/ -name "*.tar.gz" -mtime +30 -delete
```

### Weekly Operations

#### Security Review

```bash
# 1. Check for container updates
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}"

# 2. Review authentication logs
docker logs apisix-dev-apisix-1 --since 7d | grep -E "auth|oidc" | tail -20

# 3. Check admin API access
docker logs apisix-dev-apisix-1 --since 7d | grep "/apisix/admin" | tail -10

# 4. Review portal backend access
docker logs apisix-dev-portal-backend-1 --since 7d | grep -E "ERROR|WARNING"
```

#### Performance Review

```bash
# 1. Container resource usage over time
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# 2. Route performance metrics
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes | \
     jq -r '.list.routes[] | "\(.id): \(.create_time)"'

# 3. etcd health
docker exec apisix-dev-etcd-1 etcdctl endpoint health
```

### Monthly Operations

#### Backup Procedures

```bash
# 1. Backup etcd configuration
./scripts/maintenance/backup-etcd.sh

# 2. Backup configuration files
tar -czf backups/config-$(date +%Y%m%d).tar.gz config/ secrets/

# 3. Export container images
docker save apisix/apisix:latest | gzip > backups/apisix-image-$(date +%Y%m%d).tar.gz

# 4. Document current configuration
./scripts/debug/inspect-config.sh > backups/config-state-$(date +%Y%m%d).txt
```

#### Security Updates

```bash
# 1. Pull latest base images
docker compose -f infrastructure/docker/base.yml pull

# 2. Update containers with zero downtime
docker compose -f infrastructure/docker/base.yml up -d --force-recreate

# 3. Verify functionality
./scripts/testing/behavior-test.sh

# 4. Update documentation if needed
```

### Emergency Procedures

#### Service Recovery

**APISIX Gateway Failure**:

**CLI Approach (Recommended)**:
```bash
# 1. Quick status and diagnostics
./gw status dev
./gw doctor dev

# 2. View recent logs for errors
./gw logs dev apisix --tail 50

# 3. Complete service restart
./gw reset dev

# 4. Verify full functionality
./gw doctor dev
./gw routes dev --detailed
```

**Manual Approach**:
```bash
# 1. Check container status
docker ps --filter "name=apisix-dev-apisix"

# 2. View recent logs
docker logs apisix-dev-apisix-1 --tail 50

# 3. Restart service
docker compose -f infrastructure/docker/base.yml -p apisix-dev restart apisix

# 4. Verify routes are intact
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# 5. Test functionality
curl -I http://localhost:9080/portal/
```

**Complete Environment Failure**:

**CLI Approach (Recommended)**:
```bash
# 1. Complete environment reset (single command)
./gw reset dev --clean

# 2. Verify recovery
./gw doctor dev

# 3. If backup restore needed
./gw down dev --clean
# Restore configuration files from backup
./gw reset dev
```

**Manual Approach**:
```bash
# 1. Stop and clean up
./scripts/lifecycle/stop.sh
docker system prune -f

# 2. Restore from backup
tar -xzf backups/config-latest.tar.gz

# 3. Start environment
./scripts/lifecycle/start.sh --provider entraid --force-recreate

# 4. Restore routes from backup
./scripts/bootstrap/bootstrap-core.sh dev

# 5. Verify full functionality
./scripts/testing/behavior-test.sh
```

**Security Incident Response**:
```bash
# 1. Immediate containment - stop external access
ufw deny 9080/tcp
ufw deny 3001/tcp

# 2. Preserve logs for analysis
docker logs apisix-dev-apisix-1 > incident-logs-$(date +%Y%m%d-%H%M%S).log

# 3. Check admin API access logs
docker logs apisix-dev-apisix-1 | grep "/apisix/admin" > admin-access-$(date +%Y%m%d-%H%M%S).log

# 4. Rotate all secrets immediately
# (Follow secret rotation procedures)

# 5. Rebuild environment with clean state
./scripts/lifecycle/stop.sh
docker system prune -a -f
# Deploy from known good backup
```

---

## Troubleshooting Guide

### Systematic Troubleshooting Approach

#### Level 1: Quick Diagnostics (CLI Recommended)

**CLI Approach (Recommended)**:
```bash
# Complete diagnostics in one command
./gw doctor dev

# Quick status check
./gw status dev

# Environment configuration check
./gw env dev

# View recent error logs
./gw logs dev apisix --tail 20
```

**Manual Approach**:
```bash
# 1. Container health
docker ps --filter "name=apisix"
docker compose -f infrastructure/docker/base.yml -p apisix-dev ps

# 2. Port accessibility
ss -lntp | grep ':908[01]'
curl -I http://localhost:9080/health
curl -I http://localhost:9180

# 3. Basic connectivity
ping -c 3 localhost
telnet localhost 9080
telnet localhost 9180
```

#### Level 2: Service-Specific Diagnostics

**APISIX Gateway Issues**:

**CLI Approach (Recommended)**:
```bash
# Check routes configuration
./gw routes dev --detailed

# Monitor APISIX logs in real-time
./gw logs dev apisix --follow

# Check environment variables affecting APISIX
./gw env dev

# Comprehensive health check
./gw doctor dev
```

**Manual Approach**:
```bash
# Check APISIX configuration
docker exec apisix-dev-apisix-1 cat /usr/local/apisix/conf/config.yaml

# Test admin API
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# Check etcd connectivity
docker exec apisix-dev-etcd-1 etcdctl get --prefix /apisix

# View detailed logs
docker logs apisix-dev-apisix-1 --tail 100 -f
```

**Portal Backend Issues**:
```bash
# Check portal health
curl http://localhost:3001/health

# Test with user headers (bypass OIDC)
curl -H "X-User-Oid: test-123" http://localhost:3001/portal/

# Check database connectivity
curl -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/consumers

# View application logs
docker logs apisix-dev-portal-backend-1 --tail 100 -f
```

**OIDC Authentication Issues**:
```bash
# Test discovery endpoint
curl "$OIDC_DISCOVERY_ENDPOINT"

# Check redirect URI configuration
echo "Configured: $OIDC_REDIRECT_URI"
echo "Expected:   http://localhost:9080/portal/callback"

# Verify OIDC route configuration
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes/portal-oidc-route | jq '.'

# Test OIDC flow manually
./scripts/testing/test-oidc-flow.sh
```

### Common Issues and Solutions

#### Issue: "Connection refused" to Admin API

**Symptoms**:
```
curl: (7) Failed to connect to localhost port 9180: Connection refused
```

**Diagnosis**:
```bash
# Check if APISIX is running
docker ps --filter "name=apisix-dev-apisix"

# Check port binding
ss -lntp | grep ':9180'

# Check APISIX logs
docker logs apisix-dev-apisix-1 --tail 20
```

**Solutions**:
1. **APISIX not started**: `./scripts/lifecycle/start.sh`
2. **Wrong port**: Check `APISIX_ADMIN_PORT` in config
3. **Wrong project**: Ensure `COMPOSE_PROJECT_NAME=apisix-dev`

#### Issue: OIDC authentication loops or errors

**Symptoms**:
```
OIDC redirect loop
"invalid_request" error from provider
HTTP 500 on /portal/ access
```

**Diagnosis**:
```bash
# Check OIDC configuration variables
echo "Discovery: $OIDC_DISCOVERY_ENDPOINT"
echo "Client ID: $OIDC_CLIENT_ID"
echo "Redirect:  $OIDC_REDIRECT_URI"

# Test discovery endpoint
curl -f "$OIDC_DISCOVERY_ENDPOINT"

# Check route configuration
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes/portal-oidc-route | \
     jq '.value.plugins."openid-connect"'
```

**Solutions**:
1. **Wrong redirect URI**: Update in both APISIX config and OIDC provider
2. **Invalid client credentials**: Check `secrets/entraid-dev.env`
3. **Discovery endpoint unreachable**: Check DNS, firewall, network
4. **Session secret too short**: Must be 32+ characters

#### Issue: Routes not deploying

**Symptoms**:
```
❌ Failed to deploy portal-oidc-route (HTTP 400)
{"message":"schema validate failed"}
```

**Diagnosis**:
```bash
# Validate JSON syntax
jq '.' apisix/portal-oidc-route.json

# Check variable substitution
envsubst < apisix/portal-oidc-route.json | jq '.'

# Test admin API connectivity
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
```

**Solutions**:
1. **JSON syntax error**: Fix with `jq` validation
2. **Missing variables**: Check environment loading
3. **Admin API key wrong**: Verify `$ADMIN_KEY` value
4. **Schema validation**: Check APISIX plugin documentation

#### Issue: Portal backend not accessible

**Symptoms**:
```
502 Bad Gateway when accessing /portal/
Portal backend logs show connection errors
```

**Diagnosis**:
```bash
# Check portal backend health
curl http://localhost:3001/health

# Check container connectivity
docker exec apisix-dev-apisix-1 wget -O- http://portal-backend:3000/health

# Check upstream configuration
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes/portal-oidc-route | \
     jq '.value.upstream'
```

**Solutions**:
1. **Wrong upstream hostname**: Update to `apisix-dev-portal-backend-1:3000`
2. **Container not running**: Check `docker ps --filter "name=portal"`
3. **Network issue**: Verify containers are in same network
4. **Port mismatch**: Ensure portal listens on port 3000

### Advanced Debugging

#### Using Debug Containers

Start environment with debug tools:
```bash
./scripts/lifecycle/start.sh --provider entraid --debug

# Access debug toolkit (has curl, jq, dig, etc.)
docker exec -it apisix-debug-toolkit bash

# Inside debug container:
curl http://apisix-dev-apisix-1:9180/apisix/admin/routes -H "X-API-KEY: $ADMIN_KEY"
dig google.com
```

#### Network Debugging

```bash
# Check Docker networks
docker network ls
docker network inspect apisix-dev_default

# Test container-to-container connectivity
docker exec apisix-dev-apisix-1 ping apisix-dev-etcd-1
docker exec apisix-dev-apisix-1 wget -O- http://apisix-dev-portal-backend-1:3000/health

# Check DNS resolution
docker exec apisix-dev-apisix-1 nslookup login.microsoftonline.com
```

#### Configuration Debugging

```bash
# Dump complete environment
source scripts/core/environment.sh
setup_environment "entraid" "dev"
printenv | sort | grep -E "(OIDC|APISIX|ADMIN)"

# Validate configuration loading
./scripts/debug/inspect-config.sh validate

# Check final rendered routes
for route in apisix/*.json; do
    echo "=== $route ==="
    envsubst < "$route" | jq '.'
done
```

---

## Modification Procedures

### Adding New Features

#### Adding a New OIDC Provider

**Example: Adding Google OAuth**

1. **Create Provider Configuration**:
   ```bash
   mkdir -p config/providers/google
   cat > config/providers/google/dev.env << 'EOF'
   OIDC_CLIENT_ID=your-google-client-id
   OIDC_DISCOVERY_ENDPOINT=https://accounts.google.com/.well-known/openid-configuration
   OIDC_REDIRECT_URI=http://localhost:9080/portal/callback
   OIDC_PROVIDER_NAME=google
   OIDC_REALM=google-realm
   EOF
   ```

2. **Create Secrets Template**:
   ```bash
   cat > secrets/google-dev.env.example << 'EOF'
   OIDC_CLIENT_SECRET=your-google-client-secret
   OIDC_SESSION_SECRET=32-character-minimum-session-secret
   EOF
   ```

3. **Update Environment Loading**:
   Edit `scripts/core/environment.sh` to add Google-specific validation.

4. **Test Provider**:
   ```bash
   cp secrets/google-dev.env.example secrets/google-dev.env
   # Edit with real credentials
   ./scripts/lifecycle/start.sh --provider google
   ```

#### Adding a New AI Provider Route

**Example: Adding Cohere API**

1. **Create Route Definition**:
   ```json
   cat > apisix/cohere-route.json << 'EOF'
   {
     "id": "provider-cohere-chat",
     "uri": "/v1/providers/cohere/chat",
     "methods": ["POST"],
     "plugins": {
       "key-auth": {},
       "proxy-rewrite": {
         "uri": "/v1/chat",
         "headers": {
           "set": {
             "Authorization": "Bearer $COHERE_API_KEY"
           },
           "remove": ["apikey"]
         }
       }
     },
     "upstream": {
       "type": "roundrobin",
       "scheme": "https",
       "nodes": {
         "api.cohere.ai:443": 1
       }
     }
   }
   EOF
   ```

2. **Add API Key to Secrets**:
   ```bash
   echo "COHERE_API_KEY=your-cohere-key" >> secrets/entraid-dev.env
   ```

3. **Update Bootstrap Script**:
   Edit `scripts/bootstrap/bootstrap-providers.sh`:
   ```bash
   deploy_route "provider-cohere-chat" "apisix/cohere-route.json"
   ```

4. **Test Deployment**:
   ```bash
   ./scripts/bootstrap/bootstrap-providers.sh dev

   # Test the route
   curl -X POST http://localhost:9080/v1/providers/cohere/chat \
        -H "apikey: test-key" \
        -H "Content-Type: application/json" \
        -d '{"message": "Hello"}'
   ```

### Modifying Existing Functionality

#### Changing APISIX Configuration

**Example: Modifying Gateway Port**

1. **Update Base Configuration**:
   ```bash
   # Edit config/shared/base.env
   APISIX_NODE_LISTEN=8080  # Changed from 9080
   ```

2. **Update Environment Files**:
   ```bash
   # Edit config/env/dev.env
   APISIX_HOST_GATEWAY_PORT=8080  # Changed from 9080
   ```

3. **Update Docker Compose**:
   ```yaml
   # Edit infrastructure/docker/base.yml
   apisix:
     ports:
       - "${APISIX_HOST_GATEWAY_PORT:-8080}:8080"  # Changed from 9080
   ```

4. **Update All References**:
   ```bash
   # Find all references to old port
   grep -r "9080" . --exclude-dir=.git

   # Update scripts, documentation, examples
   ```

5. **Test Changes**:
   ```bash
   ./scripts/lifecycle/start.sh --force-recreate
   curl http://localhost:8080/health  # New port
   ```

#### Modifying Portal Backend

**Example: Adding New API Endpoint**

1. **Add Endpoint to Flask App**:
   ```python
   # Edit portal-backend/src/app.py
   @app.route('/portal/api/stats', methods=['GET'])
   @require_user_headers
   def get_user_stats():
       user_oid = request.headers.get('X-User-Oid')
       # Implementation
       return jsonify({'user': user_oid, 'stats': {}})
   ```

2. **Update Route Configuration**:
   ```json
   # Edit apisix/portal-oidc-route.json
   # Add /portal/api/stats to URI matching pattern if needed
   ```

3. **Test Changes**:
   ```bash
   # Restart portal backend
   docker compose -f infrastructure/docker/base.yml -p apisix-dev restart portal-backend

   # Test new endpoint
   curl -H "X-User-Oid: test" http://localhost:3001/portal/api/stats
   ```

### Configuration Updates

#### Updating OIDC Provider Settings

**Scenario: Changing EntraID tenant or client**

1. **Update Provider Configuration**:
   ```bash
   # Edit config/providers/entraid/dev.env
   OIDC_CLIENT_ID=new-client-id
   OIDC_DISCOVERY_ENDPOINT=https://login.microsoftonline.com/NEW-TENANT/v2.0/.well-known/openid-configuration
   ```

2. **Update Secrets**:
   ```bash
   # Edit secrets/entraid-dev.env
   OIDC_CLIENT_SECRET=new-client-secret
   ```

3. **Redeploy Routes**:
   ```bash
   source scripts/core/environment.sh
   setup_environment "entraid" "dev"
   ./scripts/bootstrap/bootstrap-core.sh dev
   ```

4. **Test Authentication**:
   ```bash
   curl -I http://localhost:9080/portal/
   # Should redirect to new tenant
   ```

#### Adding Environment Variables

**Process for Adding New Variables**:

1. **Determine Scope**:
   - Global: `config/shared/base.env`
   - Provider-specific: `config/providers/{provider}/dev.env`
   - Secret: `secrets/{provider}-dev.env`
   - Environment-specific: `config/env/dev.env`

2. **Add Variable**:
   ```bash
   # Example: Adding new timeout setting
   echo "APISIX_REQUEST_TIMEOUT=60s" >> config/shared/base.env
   ```

3. **Update Validation**:
   Edit `scripts/core/environment.sh`:
   ```bash
   validate_configuration() {
       local required_vars=(
           # ... existing vars ...
           "APISIX_REQUEST_TIMEOUT"
       )
       # ... validation logic ...
   }
   ```

4. **Use in Templates**:
   ```yaml
   # Use in apisix/config-dev-template.yaml
   timeout: $APISIX_REQUEST_TIMEOUT
   ```

5. **Test**:
   ```bash
   source scripts/core/environment.sh
   setup_environment "entraid" "dev"
   echo $APISIX_REQUEST_TIMEOUT  # Should show value
   ```

---

## Testing & Validation

### Testing Framework Overview

The system includes a comprehensive testing framework located in the `tests/` directory:

```
tests/
├── expected-behavior/          # Expected behavior definitions
│   ├── consumer-management.json
│   ├── oidc-flow.json
│   └── portal-backend-api.json
├── results/                    # Test run results with timestamps
│   └── {timestamp}/
│       ├── artifacts/         # Service status and logs
│       ├── processed/         # Processed test summaries
│       ├── raw/              # Raw test responses
│       └── test-run-metadata.json
└── README.md                  # Testing framework documentation
```

### Test Categories

#### 1. Behavior Tests (`./scripts/testing/behavior-test.sh`)

**Purpose**: End-to-end testing of complete system functionality
**Scope**: Portal backend API, consumer management, OIDC flows
**Usage**:
```bash
# Run complete behavior test suite
./scripts/testing/behavior-test.sh

# View results
ls tests/results/$(ls tests/results/ | tail -1)/
```

#### 2. OIDC Flow Tests (`./scripts/testing/test-oidc-flow.sh`)

**Purpose**: Test OIDC authentication flow end-to-end
**Scope**: OIDC discovery, token exchange, session management
**Usage**:
```bash
# Test OIDC flow with current provider
OIDC_PROVIDER_NAME=entraid ./scripts/testing/test-oidc-flow.sh

# Test with specific configuration
source scripts/core/environment.sh
setup_environment "entraid" "dev"
./scripts/testing/test-oidc-flow.sh
```

#### 3. Portal Backend Tests (`./scripts/testing/test-portal-backend.sh`)

**Purpose**: Test portal backend API endpoints directly
**Scope**: API key management, user operations, health checks
**Usage**:
```bash
# Test portal backend functionality
./scripts/testing/test-portal-backend.sh

# Test with debug output
DEBUG=1 ./scripts/testing/test-portal-backend.sh
```

### Testing Procedures for Maintainers

#### Pre-Deployment Testing

**Before making any changes**, run the full test suite:

```bash
# 1. Start environment
./scripts/lifecycle/start.sh --provider entraid

# 2. Deploy routes
./scripts/bootstrap/bootstrap-core.sh dev

# 3. Run comprehensive tests
./scripts/testing/behavior-test.sh

# 4. Check results
echo "Test result: $(cat tests/results/$(ls tests/results/ | tail -1)/test-run-metadata.json | jq -r .overall_result)"
```

#### Post-Deployment Validation

**After making changes**, validate functionality:

```bash
# 1. Basic connectivity
curl -f http://localhost:9080/health
curl -f -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# 2. OIDC authentication
./scripts/testing/test-oidc-flow.sh

# 3. Portal functionality
./scripts/testing/test-portal-backend.sh

# 4. Provider routes (if applicable)
curl -X POST http://localhost:9080/v1/providers/anthropic/chat \
     -H "apikey: invalid-key" \
     -H "Content-Type: application/json" \
     -d '{"model":"claude-3-sonnet","messages":[{"role":"user","content":"test"}]}'
# Should return 401 Unauthorized
```

#### Regression Testing

**When modifying core functionality**, run regression tests:

```bash
# Test both providers
for provider in keycloak entraid; do
    echo "Testing provider: $provider"
    ./scripts/lifecycle/start.sh --provider $provider --force-recreate
    ./scripts/bootstrap/bootstrap-core.sh dev
    ./scripts/testing/behavior-test.sh
    echo "Results: $(cat tests/results/$(ls tests/results/ | tail -1)/test-run-metadata.json | jq -r .overall_result)"
done
```

### Creating New Tests

#### Adding Behavior Tests

1. **Define Expected Behavior**:
   ```json
   # Create tests/expected-behavior/my-new-feature.json
   {
     "test_name": "My New Feature Test",
     "test_type": "api_endpoint",
     "description": "Test new feature functionality",
     "endpoint": "/portal/api/my-feature",
     "method": "GET",
     "expected_status": 200,
     "expected_content": {
       "feature_enabled": true
     }
   }
   ```

2. **Add to Test Script**:
   Edit `scripts/testing/behavior-test.sh` to include new test:
   ```bash
   test_my_new_feature() {
       echo "Testing my new feature..."
       # Test implementation
   }
   ```

3. **Validate Test**:
   ```bash
   ./scripts/testing/behavior-test.sh
   ```

#### Integration Test Development

**For complex feature testing**:

```bash
# Create feature-specific test script
cat > scripts/testing/test-my-feature.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Test setup
source scripts/core/environment.sh
setup_environment "entraid" "dev"

# Test implementation
test_feature_functionality() {
    echo "Testing feature..."
    # Implementation
}

# Run tests
test_feature_functionality
echo "✅ Feature tests passed"
EOF

chmod +x scripts/testing/test-my-feature.sh
```

---

## Performance Monitoring

### Performance Metrics

#### System Resource Monitoring

```bash
# Container resource usage
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# Disk usage monitoring
df -h /var/lib/docker
du -sh ./logs/

# Network performance
ss -i | grep -E ":(908[01]|3001)"
```

#### APISIX Performance Metrics

```bash
# Request throughput (from logs)
docker logs apisix-dev-apisix-1 --since 1h | \
  grep -o '"status":[0-9]*' | sort | uniq -c

# Average response times (requires custom logging)
docker logs apisix-dev-apisix-1 --since 1h | \
  grep '"request_time"' | tail -100

# Active connections
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes | \
     jq '.list.routes | length'
```

#### Portal Backend Performance

```bash
# Health check response time
time curl -s http://localhost:3001/health

# Memory usage
docker exec apisix-dev-portal-backend-1 ps aux

# Request logs analysis
docker logs apisix-dev-portal-backend-1 --since 1h | \
  grep -E "(GET|POST)" | tail -20
```

### Performance Tuning

#### APISIX Tuning

**Worker Processes** (`apisix/config-dev-template.yaml`):
```yaml
nginx_config:
  worker_processes: auto  # Match CPU cores
  worker_connections: 1024  # Connections per worker
```

**Connection Limits**:
```yaml
apisix:
  node_listen: 9080
  admin_listen:
    ip: 127.0.0.1
    port: 9180
  stream_proxy:
    tcp:
      - 9100  # Additional TCP proxy if needed
```

**etcd Performance** (`config/shared/base.env`):
```bash
# etcd client timeout
ETCD_CLIENT_TIMEOUT=30s
# etcd connection pool
ETCD_KEEPALIVE_TIME=30s
```

#### Portal Backend Tuning

**Gunicorn Configuration** (`portal-backend/Dockerfile`):
```dockerfile
# Increase worker processes
CMD ["gunicorn", "--workers=4", "--bind=0.0.0.0:3000", "src.app:app"]
```

**Flask Configuration** (`portal-backend/src/app.py`):
```python
# Connection pooling for APISIX admin API
import requests.adapters
session = requests.Session()
adapter = requests.adapters.HTTPAdapter(
    pool_connections=10,
    pool_maxsize=20
)
session.mount('http://', adapter)
```

### Performance Benchmarking

#### Load Testing

```bash
# Install Apache Bench
sudo apt install apache2-utils

# Test gateway performance
ab -n 1000 -c 10 http://localhost:9080/health

# Test portal backend
ab -n 100 -c 5 http://localhost:3001/health

# Test OIDC protected endpoint (requires valid session)
ab -n 50 -c 2 -H "Cookie: session=..." http://localhost:9080/portal/
```

#### Stress Testing

```bash
# Create stress test script
cat > scripts/testing/stress-test.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "Starting stress test..."

# Concurrent health checks
for i in {1..20}; do
    (
        for j in {1..50}; do
            curl -s http://localhost:9080/health > /dev/null
        done
        echo "Worker $i completed"
    ) &
done

wait
echo "Stress test completed"
EOF

chmod +x scripts/testing/stress-test.sh
./scripts/testing/stress-test.sh
```

#### Performance Baseline

**Establish performance baselines**:

```bash
# Create performance test
cat > scripts/testing/performance-baseline.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Performance Baseline Test ==="
echo "Date: $(date)"
echo "Environment: dev"
echo

# System resources
echo "=== System Resources ==="
docker stats --no-stream --format "{{.Container}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}"

# Response times
echo "=== Response Times ==="
echo -n "Health endpoint: "
time curl -s http://localhost:9080/health > /dev/null

echo -n "Admin API: "
time curl -s -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes > /dev/null

echo -n "Portal backend: "
time curl -s http://localhost:3001/health > /dev/null

# Throughput test
echo "=== Throughput Test ==="
ab -q -n 100 -c 5 http://localhost:9080/health | grep -E "(Requests per second|Time per request)"

echo "=== Baseline Test Complete ==="
EOF

chmod +x scripts/testing/performance-baseline.sh
```

---

## Backup & Recovery

### Backup Strategy

#### Critical Data to Backup

1. **Configuration Files**:
   - `config/` directory (version controlled)
   - `secrets/` directory (NOT version controlled)
   - `apisix/` route definitions

2. **Runtime Data**:
   - etcd configuration store
   - APISIX route configurations
   - Consumer/credential data

3. **Application Data**:
   - Portal backend state
   - Generated API keys
   - User mappings

#### Automated Backup Script

```bash
# Create backup script
cat > scripts/maintenance/backup-system.sh << 'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/backups/apisix-gateway"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$BACKUP_PATH"

echo "Starting system backup to $BACKUP_PATH"

# 1. Backup configuration files
echo "Backing up configuration..."
tar -czf "$BACKUP_PATH/config.tar.gz" config/
tar -czf "$BACKUP_PATH/secrets.tar.gz" secrets/
tar -czf "$BACKUP_PATH/apisix-routes.tar.gz" apisix/

# 2. Backup etcd data
echo "Backing up etcd..."
docker exec apisix-dev-etcd-1 etcdctl snapshot save /tmp/etcd-snapshot.db
docker cp apisix-dev-etcd-1:/tmp/etcd-snapshot.db "$BACKUP_PATH/"

# 3. Export current routes from APISIX
echo "Exporting APISIX routes..."
source scripts/core/environment.sh
setup_environment "entraid" "dev"
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes > \
     "$BACKUP_PATH/current-routes.json"

# 4. Export consumers
echo "Exporting consumers..."
curl -s -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/consumers > \
     "$BACKUP_PATH/current-consumers.json"

# 5. System state
echo "Recording system state..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" > \
    "$BACKUP_PATH/system-state.txt"

# 6. Create metadata
cat > "$BACKUP_PATH/backup-metadata.json" << EOJ
{
  "backup_time": "$(date -Iseconds)",
  "environment": "dev",
  "version": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "containers_backed_up": [
    "apisix-dev-etcd-1",
    "apisix-dev-apisix-1",
    "apisix-dev-portal-backend-1"
  ]
}
EOJ

# 7. Clean up old backups (keep 30 days)
find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

echo "✅ Backup completed: $BACKUP_PATH"
echo "Backup size: $(du -sh "$BACKUP_PATH" | cut -f1)"
EOF

chmod +x scripts/maintenance/backup-system.sh
```

#### Manual Backup Procedures

**Quick Configuration Backup**:
```bash
# Backup current configuration
tar -czf "config-backup-$(date +%Y%m%d).tar.gz" config/ secrets/ apisix/

# Backup etcd snapshot
docker exec apisix-dev-etcd-1 etcdctl snapshot save /tmp/snapshot.db
docker cp apisix-dev-etcd-1:/tmp/snapshot.db etcd-backup-$(date +%Y%m%d).db
```

**Export Current State**:
```bash
# Export all routes
curl -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes > \
     "routes-export-$(date +%Y%m%d).json"

# Export all consumers
curl -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/consumers > \
     "consumers-export-$(date +%Y%m%d).json"
```

### Recovery Procedures

#### Complete System Recovery

**Scenario**: Complete system failure, need to restore from backup

```bash
# 1. Stop all services
./scripts/lifecycle/stop.sh
docker system prune -a -f

# 2. Restore configuration files
tar -xzf config-backup-20241217.tar.gz
tar -xzf secrets-backup-20241217.tar.gz
tar -xzf apisix-routes-backup-20241217.tar.gz

# 3. Start basic services
./scripts/lifecycle/start.sh --provider entraid --environment dev

# 4. Restore etcd data
docker cp etcd-backup-20241217.db apisix-dev-etcd-1:/tmp/restore.db
docker exec apisix-dev-etcd-1 etcdctl snapshot restore /tmp/restore.db \
    --data-dir=/etcd-data-restore
# Note: May require container recreation with new data directory

# 5. Deploy routes from backup
./scripts/bootstrap/bootstrap-core.sh dev

# 6. Validate functionality
./scripts/testing/behavior-test.sh

# 7. Verify route integrity
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
curl -I http://localhost:9080/portal/
```

#### Partial Recovery Scenarios

**Route Recovery** (routes accidentally deleted):
```bash
# 1. Check current routes
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes

# 2. Redeploy from configuration
./scripts/bootstrap/bootstrap-core.sh dev

# 3. Or restore from backup
curl -X PUT -H "X-API-KEY: $ADMIN_KEY" \
     -H "Content-Type: application/json" \
     http://localhost:9180/apisix/admin/routes/import \
     -d @routes-export-20241217.json
```

**Consumer Recovery** (API keys lost):
```bash
# 1. Check current consumers
curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/consumers

# 2. Restore consumers from backup
# (Implementation depends on backup format)

# 3. Or recreate through portal
curl -X POST -H "X-User-Oid: user123" http://localhost:3001/portal/get-key
```

**Configuration Recovery** (wrong configuration deployed):
```bash
# 1. Stop services
./scripts/lifecycle/stop.sh

# 2. Restore configuration from backup
rm -rf config/ secrets/
tar -xzf config-backup-20241217.tar.gz
tar -xzf secrets-backup-20241217.tar.gz

# 3. Restart with restored configuration
./scripts/lifecycle/start.sh --provider entraid --force-recreate
```

### Disaster Recovery Testing

#### Recovery Test Procedure

```bash
# Create disaster recovery test script
cat > scripts/testing/disaster-recovery-test.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Disaster Recovery Test ==="
echo "WARNING: This will destroy the current environment!"
read -p "Continue? (y/N): " confirm
[[ "$confirm" == "y" ]] || exit 0

# 1. Create backup
echo "Creating backup..."
./scripts/maintenance/backup-system.sh
BACKUP_PATH=$(ls -t /opt/backups/apisix-gateway/ | head -1)

# 2. Record current state
echo "Recording current state..."
curl -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes > /tmp/pre-disaster-routes.json

# 3. Simulate disaster
echo "Simulating disaster (destroying environment)..."
./scripts/lifecycle/stop.sh
docker system prune -a -f

# 4. Restore from backup
echo "Restoring from backup: $BACKUP_PATH..."
# (Follow recovery procedures)

# 5. Validate recovery
echo "Validating recovery..."
./scripts/testing/behavior-test.sh

# 6. Compare state
curl -H "X-API-KEY: $ADMIN_KEY" \
     http://localhost:9180/apisix/admin/routes > /tmp/post-recovery-routes.json

if diff /tmp/pre-disaster-routes.json /tmp/post-recovery-routes.json; then
    echo "✅ Disaster recovery test PASSED"
else
    echo "❌ Disaster recovery test FAILED - routes differ"
fi
EOF

chmod +x scripts/testing/disaster-recovery-test.sh
```

---

## Upgrade Procedures

### System Upgrade Strategy

#### Component Upgrade Priorities

1. **Security Updates**: Immediate (Docker images, OS packages)
2. **APISIX Updates**: Quarterly or when needed
3. **Portal Backend**: As needed for features/security
4. **etcd Updates**: Conservative (only for security)
5. **Base OS**: Scheduled maintenance windows

#### Pre-Upgrade Checklist

```bash
# 1. Create full backup
./scripts/maintenance/backup-system.sh

# 2. Document current versions
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}"

# 3. Test current functionality
./scripts/testing/behavior-test.sh

# 4. Check for breaking changes in target versions
# (Consult APISIX changelog, Docker image release notes)

# 5. Plan rollback strategy
echo "Rollback plan: restore from backup dated $(date)"
```

### APISIX Version Upgrades

#### Minor Version Upgrades (e.g., 3.7.0 → 3.8.0)

```bash
# 1. Check compatibility
# (Review APISIX changelog for breaking changes)

# 2. Update Docker compose
# Edit infrastructure/docker/base.yml
apisix:
  image: apache/apisix:3.8.0-debian  # Updated version

# 3. Test in dev environment first
./scripts/lifecycle/start.sh --provider entraid --environment dev --force-recreate

# 4. Validate functionality
./scripts/testing/behavior-test.sh
./scripts/testing/test-oidc-flow.sh

# 5. If successful, update test/prod environments
./scripts/lifecycle/start.sh --provider entraid --environment test --force-recreate
```

#### Major Version Upgrades (e.g., 3.x → 4.x)

**⚠️ CRITICAL**: Major version upgrades require extensive testing and may have breaking changes.

```bash
# 1. Extensive pre-upgrade testing
# - Review ALL breaking changes
# - Test configuration compatibility
# - Update route definitions if needed

# 2. Stage upgrade in isolated environment
# 3. Comprehensive testing including load testing
# 4. Gradual rollout (dev → test → prod)
# 5. Monitor closely for issues
```

### Container Image Updates

#### Security Updates

```bash
# 1. Pull latest images
docker compose -f infrastructure/docker/base.yml pull

# 2. Check for security updates
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}"

# 3. Rolling update with zero downtime
docker compose -f infrastructure/docker/base.yml -p apisix-dev up -d --force-recreate

# 4. Validate services
curl -f http://localhost:9080/health
curl -f -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes
```

#### Custom Image Updates

**Portal Backend Updates**:
```bash
# 1. Update portal backend code
# (Make changes to portal-backend/src/app.py)

# 2. Rebuild container
docker compose -f infrastructure/docker/base.yml -p apisix-dev build portal-backend

# 3. Deploy updated container
docker compose -f infrastructure/docker/base.yml -p apisix-dev up -d portal-backend

# 4. Test functionality
curl -f http://localhost:3001/health
./scripts/testing/test-portal-backend.sh
```

### Configuration Upgrades

#### Environment Configuration Updates

**Adding New Configuration Variables**:
```bash
# 1. Add to appropriate config file
echo "NEW_FEATURE_ENABLED=true" >> config/shared/base.env

# 2. Update validation
# Edit scripts/core/environment.sh to include new variable

# 3. Update templates that use the variable
# Edit apisix/config-dev-template.yaml

# 4. Test configuration loading
source scripts/core/environment.sh
setup_environment "entraid" "dev"
echo $NEW_FEATURE_ENABLED

# 5. Deploy updated configuration
./scripts/lifecycle/start.sh --provider entraid --force-recreate
```

#### Route Configuration Updates

**Updating Route Definitions**:
```bash
# 1. Update route JSON files
# Edit apisix/portal-oidc-route.json

# 2. Validate JSON syntax
jq '.' apisix/portal-oidc-route.json

# 3. Test variable substitution
envsubst < apisix/portal-oidc-route.json | jq '.'

# 4. Deploy updated routes
./scripts/bootstrap/bootstrap-core.sh dev

# 5. Validate functionality
curl -I http://localhost:9080/portal/
```

### Rollback Procedures

#### Immediate Rollback

**If upgrade fails**:
```bash
# 1. Stop current environment
./scripts/lifecycle/stop.sh

# 2. Restore previous container versions
# Edit infrastructure/docker/base.yml back to previous versions

# 3. Restore configuration if changed
# Restore from backup if needed

# 4. Start with previous version
./scripts/lifecycle/start.sh --provider entraid --force-recreate

# 5. Validate rollback
./scripts/testing/behavior-test.sh
```

#### Data Rollback

**If data corruption occurs**:
```bash
# 1. Stop services
./scripts/lifecycle/stop.sh

# 2. Restore etcd from backup
# (Follow backup recovery procedures)

# 3. Restore configuration files
tar -xzf config-backup-$(date +%Y%m%d).tar.gz

# 4. Restart with restored data
./scripts/lifecycle/start.sh --provider entraid --force-recreate

# 5. Redeploy routes
./scripts/bootstrap/bootstrap-core.sh dev
```

### Post-Upgrade Validation

#### Comprehensive Post-Upgrade Testing

```bash
# Create post-upgrade validation script
cat > scripts/testing/post-upgrade-validation.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Post-Upgrade Validation ==="

# 1. System health
echo "Checking system health..."
docker ps --filter "name=apisix"
curl -f http://localhost:9080/health || { echo "❌ Gateway health check failed"; exit 1; }
curl -f -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes || { echo "❌ Admin API failed"; exit 1; }

# 2. Authentication flow
echo "Testing authentication flow..."
./scripts/testing/test-oidc-flow.sh || { echo "❌ OIDC flow failed"; exit 1; }

# 3. Portal backend
echo "Testing portal backend..."
./scripts/testing/test-portal-backend.sh || { echo "❌ Portal backend failed"; exit 1; }

# 4. Route functionality
echo "Testing routes..."
curl -I http://localhost:9080/portal/ | grep -q "302\|200" || { echo "❌ Portal route failed"; exit 1; }

# 5. Performance baseline
echo "Performance check..."
RESPONSE_TIME=$(time curl -s http://localhost:9080/health 2>&1 | grep real | awk '{print $2}')
echo "Health endpoint response time: $RESPONSE_TIME"

# 6. Load test
echo "Basic load test..."
ab -q -n 100 -c 5 http://localhost:9080/health > /dev/null || { echo "❌ Load test failed"; exit 1; }

echo "✅ Post-upgrade validation completed successfully"
EOF

chmod +x scripts/testing/post-upgrade-validation.sh

# Run post-upgrade validation
./scripts/testing/post-upgrade-validation.sh
```

---

This completes the comprehensive MAINTAINERS_GUIDE.md. The guide provides detailed technical information for maintainers to operate, modify, troubleshoot, and extend the APISIX Gateway system effectively.