#!/bin/bash
# Apache Multi-Domain Deployment Script - Infrastructure as Code
# Idempotent deployment for APISIX Gateway domain separation

set -euo pipefail

# Configuration
APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
APACHE_SITES_ENABLED="/etc/apache2/sites-enabled"
DOCS_APACHE_DIR="$(dirname "$0")/../../docs/apache"

# Our managed sites
LAMASSU_SITE="lamassu-ita-chalmers.conf"
AI_GATEWAY_SITE="ai-gateway-portal-chalmers.conf"

# Old sites to disable
OLD_SITES=("apisix-gateway.conf" "apisix-gateway-le-ssl.conf")

# Colors and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $*" >&2; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
log_error() { echo -e "${RED}ERROR:${NC} $*" >&2; }

# Preflight checks
preflight_checks() {
    log_info "=== PREFLIGHT CHECKS ==="

    local all_good=true

    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log_error "Sudo access required for Apache deployment"
        all_good=false
    fi

    # Check required config files exist
    for site in "$LAMASSU_SITE" "$AI_GATEWAY_SITE"; do
        if [[ ! -f "$DOCS_APACHE_DIR/$site" ]]; then
            log_error "Missing config file: $DOCS_APACHE_DIR/$site"
            all_good=false
        else
            log_success "Found: $DOCS_APACHE_DIR/$site"
        fi
    done

    # Check Apache is installed and running
    if ! systemctl is-active apache2 >/dev/null 2>&1; then
        log_warning "Apache2 is not running"
    else
        log_success "Apache2 is running"
    fi

    # Check required modules
    local required_modules=("proxy" "proxy_http" "ssl" "headers" "rewrite")
    for module in "${required_modules[@]}"; do
        if apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
            log_success "Module enabled: $module"
        else
            log_warning "Module not enabled: $module (will be enabled during deploy)"
        fi
    done

    # Check current enabled sites
    log_info "Currently enabled sites:"
    ls -la "$APACHE_SITES_ENABLED" 2>/dev/null | grep -E "\\.conf" | awk '{print "  " $NF}' || echo "  (none)"

    # Show what will be changed
    log_info "Changes that will be made during deploy:"
    for old_site in "${OLD_SITES[@]}"; do
        if [[ -L "$APACHE_SITES_ENABLED/$old_site" ]]; then
            log_info "  DISABLE: $old_site (broken ServerAlias)"
        fi
    done
    log_info "  ENABLE: $LAMASSU_SITE (lamassu.ita.chalmers.se → 9080)"
    log_info "  ENABLE: $AI_GATEWAY_SITE (ai-gateway.portal.chalmers.se → 9081)"

    # Check certificate status
    if [[ -d "/etc/letsencrypt/live/lamassu.ita.chalmers.se" ]]; then
        log_success "Lamassu certificate exists"
    else
        log_warning "Lamassu certificate missing"
    fi

    if [[ -d "/etc/letsencrypt/live/ai-gateway.portal.chalmers.se" ]]; then
        log_success "AI Gateway certificate exists"
    else
        log_warning "AI Gateway certificate missing (HTTPS will be skipped)"
    fi

    if [[ "$all_good" == "true" ]]; then
        log_success "Preflight checks passed"
        return 0
    else
        log_error "Preflight checks failed"
        return 1
    fi
}

# Create timestamped backup
create_backup() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="/tmp/apache-backup-$timestamp"

    log_info "Creating backup: $backup_dir"
    sudo mkdir -p "$backup_dir"
    sudo cp -r "$APACHE_SITES_AVAILABLE" "$backup_dir/sites-available"
    sudo cp -r "$APACHE_SITES_ENABLED" "$backup_dir/sites-enabled"

    echo "$backup_dir"
}

# Deploy Apache configurations
deploy_apache_configs() {
    log_info "=== DEPLOYING APACHE CONFIGURATIONS ==="

    # Create backup
    local backup_dir
    backup_dir=$(create_backup)
    log_success "Backup created: $backup_dir"

    # Enable required modules
    log_info "Enabling required Apache modules"
    local modules=("proxy" "proxy_http" "ssl" "headers" "rewrite")
    for module in "${modules[@]}"; do
        sudo a2enmod "$module" >/dev/null 2>&1 || true
    done

    # Disable old broken sites (idempotent)
    log_info "Disabling old broken sites"
    for old_site in "${OLD_SITES[@]}"; do
        if [[ -L "$APACHE_SITES_ENABLED/$old_site" ]]; then
            log_info "  Disabling: $old_site"
            sudo a2dissite "$old_site" >/dev/null 2>&1 || true
        else
            log_info "  Already disabled: $old_site"
        fi
    done

    # Copy our configurations to sites-available
    log_info "Deploying configuration files"
    sudo cp "$DOCS_APACHE_DIR/$LAMASSU_SITE" "$APACHE_SITES_AVAILABLE/"
    sudo cp "$DOCS_APACHE_DIR/$AI_GATEWAY_SITE" "$APACHE_SITES_AVAILABLE/"
    log_success "Configuration files copied"

    # Enable sites in safe order
    log_info "Enabling sites"

    # 1. Enable lamassu (has existing cert, safe)
    sudo a2ensite "$LAMASSU_SITE" >/dev/null 2>&1 || true
    log_success "Enabled: $LAMASSU_SITE"

    # 2. Enable ai-gateway HTTP (port 80 only if no cert exists)
    if [[ ! -d "/etc/letsencrypt/live/ai-gateway.portal.chalmers.se" ]]; then
        log_warning "AI Gateway certificate missing - creating HTTP-only version"
        # Create HTTP-only version of ai-gateway config
        local temp_config="/tmp/ai-gateway-http-only.conf"
        sed '/<VirtualHost \*:443>/,/<\/VirtualHost>/d' "$APACHE_SITES_AVAILABLE/$AI_GATEWAY_SITE" | \
        sudo tee "$APACHE_SITES_AVAILABLE/ai-gateway-portal-chalmers-http.conf" >/dev/null
        sudo a2ensite "ai-gateway-portal-chalmers-http.conf" >/dev/null 2>&1 || true
        log_success "Enabled: ai-gateway-portal-chalmers-http.conf (HTTP only)"
    else
        # 3. Enable full ai-gateway (has cert, safe)
        sudo a2ensite "$AI_GATEWAY_SITE" >/dev/null 2>&1 || true
        log_success "Enabled: $AI_GATEWAY_SITE (HTTP + HTTPS)"
    fi

    # Test configuration
    log_info "Testing Apache configuration"
    if sudo apachectl configtest >/dev/null 2>&1; then
        log_success "Apache configuration is valid"
    else
        log_error "Apache configuration test failed"
        log_error "Restoring from backup: $backup_dir"
        sudo rm -rf "$APACHE_SITES_AVAILABLE"/* "$APACHE_SITES_ENABLED"/*
        sudo cp -r "$backup_dir/sites-available"/* "$APACHE_SITES_AVAILABLE/"
        sudo cp -r "$backup_dir/sites-enabled"/* "$APACHE_SITES_ENABLED/"
        sudo systemctl reload apache2
        return 1
    fi

    # Reload Apache
    log_info "Reloading Apache"
    sudo systemctl reload apache2
    log_success "Apache reloaded successfully"

    log_success "Deployment completed successfully"
    log_info "Backup available at: $backup_dir"
}

# Enable AI Gateway HTTPS (after certificate exists)
enable_ai_gateway_https() {
    log_info "=== ENABLING AI GATEWAY HTTPS ==="

    # Check if certificate exists
    if [[ ! -d "/etc/letsencrypt/live/ai-gateway.portal.chalmers.se" ]]; then
        log_error "AI Gateway certificate not found at /etc/letsencrypt/live/ai-gateway.portal.chalmers.se"
        log_error "Run: sudo certbot certonly --webroot -w /var/www/html -d ai-gateway.portal.chalmers.se"
        return 1
    fi

    # Disable HTTP-only version if it exists
    if [[ -L "$APACHE_SITES_ENABLED/ai-gateway-portal-chalmers-http.conf" ]]; then
        log_info "Disabling HTTP-only version"
        sudo a2dissite "ai-gateway-portal-chalmers-http.conf" >/dev/null 2>&1 || true
    fi

    # Enable full HTTPS version
    log_info "Enabling full HTTPS configuration"
    sudo a2ensite "$AI_GATEWAY_SITE" >/dev/null 2>&1 || true

    # Test and reload
    if sudo apachectl configtest >/dev/null 2>&1; then
        sudo systemctl reload apache2
        log_success "AI Gateway HTTPS enabled successfully"
    else
        log_error "Configuration test failed - check certificate paths"
        return 1
    fi
}

# Verify deployment
verify_deployment() {
    log_info "=== VERIFYING DEPLOYMENT ==="

    local all_good=true

    # Check apache2ctl -S output
    log_info "Apache virtual host configuration:"
    sudo apache2ctl -S 2>/dev/null | grep -E "VirtualHost|ServerName" | head -10

    # Verify no ServerAlias cross-wiring
    log_info "Checking for ServerAlias cross-wiring..."
    if sudo grep -r "ServerAlias ai-gateway.portal.chalmers.se" "$APACHE_SITES_ENABLED" >/dev/null 2>&1; then
        log_error "Found ServerAlias ai-gateway.portal.chalmers.se in enabled sites (should not exist)"
        all_good=false
    else
        log_success "No ServerAlias cross-wiring found"
    fi

    # Test domain routing with Host headers
    log_info "Testing domain routing separation..."

    # Test lamassu domain
    local lamassu_response
    lamassu_response=$(curl -sSI -H 'Host: lamassu.ita.chalmers.se' http://127.0.0.1/ 2>/dev/null | head -1 || echo "FAILED")
    if echo "$lamassu_response" | grep -E "(301|302|200)" >/dev/null; then
        log_success "Lamassu domain responding: $lamassu_response"
    else
        log_error "Lamassu domain not responding properly: $lamassu_response"
        all_good=false
    fi

    # Test ai-gateway domain
    local ai_gateway_response
    ai_gateway_response=$(curl -sSI -H 'Host: ai-gateway.portal.chalmers.se' http://127.0.0.1/ 2>/dev/null | head -1 || echo "FAILED")
    if echo "$ai_gateway_response" | grep -E "(404|301|302|200)" >/dev/null; then
        log_success "AI Gateway domain responding: $ai_gateway_response"
    else
        log_error "AI Gateway domain not responding properly: $ai_gateway_response"
        all_good=false
    fi

    # Verify different backends (lamassu should NOT get 404 from APISIX, ai-gateway should)
    if echo "$lamassu_response" | grep -q "404" && echo "$ai_gateway_response" | grep -q "404"; then
        log_warning "Both domains returning 404 - may indicate same backend (check routing)"
    elif echo "$lamassu_response" | grep -E "(301|302)" && echo "$ai_gateway_response" | grep -q "404"; then
        log_success "Routing separation confirmed: lamassu (Apache redirect) vs ai-gateway (APISIX 404)"
    fi

    # Test admin API blocking (if HTTPS is enabled)
    log_info "Testing admin API blocking..."
    local admin_test_domains=()

    # Test lamassu admin blocking (should have HTTPS)
    if [[ -d "/etc/letsencrypt/live/lamassu.ita.chalmers.se" ]]; then
        admin_test_domains+=("lamassu.ita.chalmers.se")
    fi

    # Test ai-gateway admin blocking (if HTTPS enabled)
    if [[ -d "/etc/letsencrypt/live/ai-gateway.portal.chalmers.se" ]] && \
       [[ -L "$APACHE_SITES_ENABLED/$AI_GATEWAY_SITE" ]]; then
        admin_test_domains+=("ai-gateway.portal.chalmers.se")
    fi

    for domain in "${admin_test_domains[@]}"; do
        local admin_response
        admin_response=$(curl -k -sSI "https://$domain/apisix/admin/routes" 2>/dev/null | head -1 || echo "FAILED")
        if echo "$admin_response" | grep -q "403"; then
            log_success "Admin API blocked on $domain: $admin_response"
        else
            log_warning "Admin API blocking test failed for $domain: $admin_response"
        fi
    done

    # Summary
    if [[ "$all_good" == "true" ]]; then
        log_success "All verification checks passed"
        return 0
    else
        log_error "Some verification checks failed"
        return 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 {preflight|deploy|enable-ai-gateway-https|verify}"
    echo ""
    echo "Commands:"
    echo "  preflight                Check requirements and show planned changes"
    echo "  deploy                   Deploy Apache configurations (idempotent)"
    echo "  enable-ai-gateway-https  Enable HTTPS for AI Gateway (after certificate exists)"
    echo "  verify                   Verify deployment and routing separation"
    echo ""
    echo "Safe deployment order:"
    echo "  1. $0 preflight          # Check requirements"
    echo "  2. $0 deploy             # Deploy HTTP configurations"
    echo "  3. sudo certbot ...      # Issue AI Gateway certificate"
    echo "  4. $0 enable-ai-gateway-https  # Enable HTTPS"
    echo "  5. $0 verify             # Verify everything works"
}

# Main execution
main() {
    case "${1:-}" in
        "preflight")
            preflight_checks
            ;;
        "deploy")
            preflight_checks
            deploy_apache_configs
            ;;
        "enable-ai-gateway-https")
            enable_ai_gateway_https
            ;;
        "verify")
            verify_deployment
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"