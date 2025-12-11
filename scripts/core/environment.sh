#!/bin/bash
# Core Environment Management Functions
# Provides configuration loading, validation, and management capabilities

set -euo pipefail

# Get script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Logging functions
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_warning() {
    echo "⚠️  $*"
}

log_error() {
    echo "❌ $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "🔍 DEBUG: $*" >&2
    fi
}

# Validation functions
require_vars() {
    local missing_vars=()
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
}

# Configuration loading functions
load_shared_config() {
    local shared_dir="$PROJECT_ROOT/config/shared"

    log_debug "Loading shared configuration from $shared_dir"

    # Load base configuration
    if [[ -f "$shared_dir/base.env" ]]; then
        log_debug "Loading base.env"
        # shellcheck source=/dev/null
        source "$shared_dir/base.env"
    else
        log_error "Missing required file: $shared_dir/base.env"
        return 1
    fi

    # Load APISIX configuration
    if [[ -f "$shared_dir/apisix.env" ]]; then
        log_debug "Loading apisix.env"
        # shellcheck source=/dev/null
        source "$shared_dir/apisix.env"
    else
        log_error "Missing required file: $shared_dir/apisix.env"
        return 1
    fi
}

load_provider_config() {
    local provider="${1:-}"
    local environment="${2:-dev}"

    if [[ -z "$provider" ]]; then
        log_error "Provider not specified"
        return 1
    fi

    local provider_dir="$PROJECT_ROOT/config/providers/$provider"
    local provider_file="$provider_dir/$environment.env"

    log_debug "Loading provider configuration: $provider ($environment)"

    # Validate provider exists
    if [[ ! -d "$provider_dir" ]]; then
        log_error "Unknown provider: $provider"
        log_error "Available providers: $(ls "$PROJECT_ROOT/config/providers" 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    # Load provider configuration
    if [[ -f "$provider_file" ]]; then
        log_debug "Loading $provider_file"
        # shellcheck source=/dev/null
        source "$provider_file"
    else
        log_error "Missing provider configuration: $provider_file"
        return 1
    fi
}

load_secrets() {
    local provider="${1:-}"
    local environment="${2:-dev}"

    if [[ -z "$provider" ]]; then
        log_error "Provider not specified for secrets loading"
        return 1
    fi

    local secrets_file="$PROJECT_ROOT/secrets/$provider-$environment.env"

    log_debug "Attempting to load secrets from $secrets_file"

    # Load secrets if available (optional)
    if [[ -f "$secrets_file" ]]; then
        log_debug "Loading secrets from $secrets_file"
        # shellcheck source=/dev/null
        source "$secrets_file"
    else
        log_warning "No secrets file found: $secrets_file"
        log_warning "Using placeholder values - ensure secrets are properly configured"
    fi
}

# Provider validation functions
validate_provider_config() {
    local provider="${1:-}"

    if [[ -z "$provider" ]]; then
        log_error "Provider not specified for validation"
        return 1
    fi

    log_debug "Validating $provider provider configuration"

    case "$provider" in
        "entraid")
            validate_entraid_config
            ;;
        "keycloak")
            validate_keycloak_config
            ;;
        *)
            log_error "Unknown provider for validation: $provider"
            return 1
            ;;
    esac
}

validate_entraid_config() {
    log_debug "Validating EntraID configuration"

    local required_vars=(
        "OIDC_CLIENT_ID"
        "OIDC_CLIENT_SECRET"
        "OIDC_DISCOVERY_ENDPOINT"
        "OIDC_REDIRECT_URI"
        "OIDC_SESSION_SECRET"
    )

    require_vars "${required_vars[@]}"

    # Check for placeholder values
    if [[ "$OIDC_CLIENT_ID" == "placeholder-client-id-for-testing" ]]; then
        log_warning "EntraID client ID is still using placeholder value"
        log_warning "Please update secrets/entraid-dev.env with actual credentials"
    fi

    # Validate discovery endpoint format
    if [[ ! "$OIDC_DISCOVERY_ENDPOINT" =~ ^https://login\.microsoftonline\.com/.*/v2\.0/\.well-known/openid-configuration$ ]]; then
        log_warning "EntraID discovery endpoint format may be incorrect"
        log_warning "Expected format: https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration"
    fi
}

validate_keycloak_config() {
    log_debug "Validating Keycloak configuration"

    local required_vars=(
        "OIDC_CLIENT_ID"
        "OIDC_CLIENT_SECRET"
        "OIDC_DISCOVERY_ENDPOINT"
        "OIDC_REDIRECT_URI"
        "OIDC_SESSION_SECRET"
        "KEYCLOAK_ADMIN_URL"
    )

    require_vars "${required_vars[@]}"
}

# Main configuration setup function
setup_environment() {
    local provider="${1:-}"
    local environment="${2:-dev}"

    if [[ -z "$provider" ]]; then
        log_error "Provider not specified"
        log_error "Usage: setup_environment <provider> [environment]"
        log_error "Available providers: keycloak, entraid"
        return 1
    fi

    log_info "Setting up $environment environment with $provider provider"

    # Load configuration in order: shared -> secrets -> provider
    # (secrets loaded before provider so provider config can reference secret variables)
    load_shared_config
    load_secrets "$provider" "$environment"
    load_provider_config "$provider" "$environment"

    # Validate configuration
    validate_provider_config "$provider"

    # Export provider info for other scripts
    export OIDC_PROVIDER_NAME="$provider"
    export ENVIRONMENT="$environment"

    # Export all Docker Compose variables
    export ADMIN_KEY
    export APISIX_ADMIN_API
    export APISIX_ADMIN_API_CONTAINER
    export APISIX_NODE_LISTEN
    export APISIX_ADMIN_PORT
    export DATA_PLANE
    export ADMIN_API
    export ETCD_HOST
    export OIDC_CLIENT_ID
    export OIDC_CLIENT_SECRET
    export OIDC_DISCOVERY_ENDPOINT
    export OIDC_REDIRECT_URI
    export OIDC_SESSION_SECRET
    export OIDC_PROVIDER_NAME
    export PORTAL_BACKEND_HOST
    export PORTAL_BACKEND_PORT
    export BACKEND_HOST
    export KEYCLOAK_ADMIN_URL
    export APISIX_NETWORK_CONTEXT
    export UID
    export GID

    log_success "Environment configuration loaded successfully"
    log_info "Provider: $provider"
    log_info "Environment: $environment"
    log_info "Client ID: ${OIDC_CLIENT_ID}"
    log_info "Discovery: ${OIDC_DISCOVERY_ENDPOINT}"
    log_info "Redirect URI: ${OIDC_REDIRECT_URI}"

    return 0
}

# Docker Compose command generation
generate_compose_command() {
    local provider="${1:-}"
    local environment="${2:-dev}"
    local debug_mode="${3:-false}"

    local compose_files=()

    # Base infrastructure
    compose_files+=("-f" "$PROJECT_ROOT/infrastructure/docker/base.yml")

    # Provider services
    compose_files+=("-f" "$PROJECT_ROOT/infrastructure/docker/providers.yml")

    # Debug tools if requested
    if [[ "$debug_mode" == "true" ]]; then
        compose_files+=("-f" "$PROJECT_ROOT/infrastructure/docker/debug.yml")
    fi

    # Export for use by calling scripts
    export COMPOSE_FILES="${compose_files[*]}"
    export COMPOSE_PROFILES="$provider"

    if [[ "$debug_mode" == "true" ]]; then
        export COMPOSE_PROFILES="$provider,debug"
    fi

    log_debug "Generated compose command with files: ${COMPOSE_FILES}"
    log_debug "Using profiles: ${COMPOSE_PROFILES}"
}

# Utility functions
list_available_providers() {
    local providers_dir="$PROJECT_ROOT/config/providers"

    if [[ -d "$providers_dir" ]]; then
        echo "Available providers:"
        for provider in "$providers_dir"/*; do
            if [[ -d "$provider" ]]; then
                echo "  - $(basename "$provider")"
            fi
        done
    else
        echo "No providers directory found: $providers_dir"
    fi
}

show_current_config() {
    echo "Current Configuration Summary:"
    echo "============================="
    echo "Provider: ${OIDC_PROVIDER_NAME:-not set}"
    echo "Environment: ${ENVIRONMENT:-not set}"
    echo "Client ID: ${OIDC_CLIENT_ID:-not set}"
    echo "Discovery: ${OIDC_DISCOVERY_ENDPOINT:-not set}"
    echo "Redirect URI: ${OIDC_REDIRECT_URI:-not set}"
    echo "APISIX Admin: ${APISIX_ADMIN_API:-not set}"
    echo "============================="
}

# Centralized environment loader for script consistency
ensure_environment() {
    # Smart environment loading that works for all scripts
    local provider="${OIDC_PROVIDER_NAME:-${1:-keycloak}}"
    local environment="${ENVIRONMENT:-${2:-dev}}"

    # Skip if already loaded (performance optimization)
    if [[ -n "${OIDC_CLIENT_ID:-}" && -n "${ADMIN_KEY:-}" ]]; then
        log_debug "Environment already loaded for provider: $provider"
        return 0
    fi

    log_debug "Loading environment for provider: $provider, environment: $environment"

    # Load environment with error handling
    if ! setup_environment "$provider" "$environment"; then
        log_error "Failed to load environment for provider: $provider"
        log_error "Available providers: keycloak, entraid"
        log_error "Ensure secrets are configured in secrets/$provider-$environment.env"
        return 1
    fi

    log_debug "Environment loaded successfully"
    return 0
}

# Export functions for use by other scripts
export -f log_info log_success log_warning log_error log_debug
export -f require_vars load_shared_config load_provider_config load_secrets
export -f validate_provider_config validate_entraid_config validate_keycloak_config
export -f setup_environment generate_compose_command ensure_environment
export -f list_available_providers show_current_config