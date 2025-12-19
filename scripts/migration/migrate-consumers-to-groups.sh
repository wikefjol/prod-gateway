#!/bin/sh
# Migrate existing consumers to base_user group

set -eu

# Import logging functions
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_error() {
    echo "❌ $*" >&2
}

log_warning() {
    echo "⚠️  $*"
}

# Check if required environment variables are set
check_environment() {
    if [ -z "${ADMIN_KEY:-}" ]; then
        log_error "ADMIN_KEY environment variable is required"
        exit 1
    fi

    if [ -z "${APISIX_ADMIN_API:-}" ]; then
        log_error "APISIX_ADMIN_API environment variable is required"
        exit 1
    fi
}

migrate_existing_consumers() {
    local apisix_admin="${APISIX_ADMIN_API}"

    log_info "Starting migration of existing consumers to base_user group..."
    log_info "Using APISIX Admin API: $apisix_admin"

    # Get all consumers
    local consumers_response
    if consumers_response=$(curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$apisix_admin/consumers" 2>/dev/null); then
        local consumer_count=0
        local migrated_count=0
        local skipped_count=0
        local error_count=0

        # Parse JSON response to extract consumer usernames
        echo "$consumers_response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4 | while read -r username; do
            if [ -n "$username" ]; then
                consumer_count=$((consumer_count + 1))
                log_info "Processing consumer: $username"

                if migrate_single_consumer "$apisix_admin" "$username"; then
                    case $? in
                        0) migrated_count=$((migrated_count + 1)) ;;
                        1) skipped_count=$((skipped_count + 1)) ;;
                        2) error_count=$((error_count + 1)) ;;
                    esac
                fi
            fi
        done

        log_success "Consumer migration completed"
        log_info "Summary: $consumer_count consumers processed"
        log_info "  - Migrated: $migrated_count"
        log_info "  - Skipped (already in group): $skipped_count"
        log_info "  - Errors: $error_count"
    else
        log_error "Failed to retrieve consumers for migration"
        return 1
    fi
}

migrate_single_consumer() {
    local apisix_admin="$1"
    local username="$2"

    # Get current consumer data
    local consumer_data
    if consumer_data=$(curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$apisix_admin/consumers/$username" 2>/dev/null); then
        # Check if already has group_id
        if echo "$consumer_data" | grep -q '"group_id"'; then
            log_info "Consumer $username already has group assignment, skipping"
            return 1  # Skipped
        fi

        # Extract the consumer value and add group_id
        local consumer_value
        consumer_value=$(echo "$consumer_data" | sed -n 's/.*"value":\({.*}\).*/\1/p')

        if [ -z "$consumer_value" ]; then
            log_error "Failed to extract consumer data for: $username"
            return 2  # Error
        fi

        # Add group_id to the consumer data
        local updated_data
        updated_data=$(echo "$consumer_value" | sed 's/{/{"group_id":"base_user",/')

        # Update consumer
        if curl -fsS -X PUT \
            -H "X-API-KEY: $ADMIN_KEY" \
            -H "Content-Type: application/json" \
            -d "$updated_data" \
            "$apisix_admin/consumers/$username" >/dev/null 2>&1; then
            log_success "Migrated consumer: $username"
            return 0  # Migrated
        else
            log_error "Failed to migrate consumer: $username"
            return 2  # Error
        fi
    else
        log_error "Failed to retrieve consumer data for: $username"
        return 2  # Error
    fi
}

# Verify consumer groups exist before migration
verify_consumer_groups() {
    local apisix_admin="${APISIX_ADMIN_API}"

    log_info "Verifying consumer groups exist before migration..."

    # Check base_user group
    if ! curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$apisix_admin/consumer_groups/base_user" >/dev/null 2>&1; then
        log_error "base_user consumer group not found. Please run bootstrap first."
        return 1
    fi

    # Check premium_user group
    if ! curl -fsS -H "X-API-KEY: $ADMIN_KEY" "$apisix_admin/consumer_groups/premium_user" >/dev/null 2>&1; then
        log_warning "premium_user consumer group not found. This is optional but recommended."
    fi

    log_success "Consumer groups verified"
    return 0
}

# Main execution
main() {
    echo "🔄 APISIX Consumer Group Migration"
    echo "================================"
    echo ""

    # Check environment
    check_environment

    # Verify consumer groups exist
    verify_consumer_groups

    # Run migration
    migrate_existing_consumers

    echo ""
    log_success "🎉 Migration completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify consumer groups: curl -H 'X-API-KEY: $ADMIN_KEY' ${APISIX_ADMIN_API}/consumer_groups"
    echo "  2. Check a migrated consumer: curl -H 'X-API-KEY: $ADMIN_KEY' ${APISIX_ADMIN_API}/consumers/[username]"
    echo "  3. Test rate limiting with API calls"
    echo ""
}

# Execute main function
main "$@"