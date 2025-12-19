#!/bin/sh
# Configure APISIX Consumer Groups

set -eu

# Logging functions (import from main bootstrap)
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_error() {
    echo "❌ $*" >&2
}

configure_consumer_groups() {
    local apisix_admin="$1"

    log_info "Configuring Consumer Groups..."

    # Configure base_user group
    configure_base_user_group "$apisix_admin"

    # Configure premium_user group
    configure_premium_user_group "$apisix_admin"
}

configure_base_user_group() {
    local apisix_admin="$1"
    local template_file="/opt/apisix-gateway/apisix/consumer-groups/base-user-group.json"

    if [ ! -f "$template_file" ]; then
        log_error "Base user group template not found: $template_file"
        return 1
    fi

    log_info "Applying base_user consumer group..."

    # Apply the consumer group configuration
    if curl -fsS -X PUT \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "$(cat "$template_file")" \
        "$apisix_admin/consumer_groups/base_user" >/dev/null; then
        log_success "base_user consumer group configured successfully"
    else
        log_error "Failed to configure base_user consumer group"
        return 1
    fi
}

configure_premium_user_group() {
    local apisix_admin="$1"
    local template_file="/opt/apisix-gateway/apisix/consumer-groups/premium-user-group.json"

    if [ ! -f "$template_file" ]; then
        log_error "Premium user group template not found: $template_file"
        return 1
    fi

    log_info "Applying premium_user consumer group..."

    # Apply the consumer group configuration
    if curl -fsS -X PUT \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "$(cat "$template_file")" \
        "$apisix_admin/consumer_groups/premium_user" >/dev/null; then
        log_success "premium_user consumer group configured successfully"
    else
        log_error "Failed to configure premium_user consumer group"
        return 1
    fi
}