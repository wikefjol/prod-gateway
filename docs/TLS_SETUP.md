# Phase 2: TLS Termination Setup Guide

## Overview
This guide configures Apache as a reverse proxy with Let's Encrypt SSL for `lamassu.ita.chalmers.se`, providing HTTPS termination for the APISIX Gateway.

## Architecture
```
Internet → Apache (443/80) → APISIX Gateway (127.0.0.1:9080) → Portal/APIs
```

## Prerequisites
- Domain `lamassu.ita.chalmers.se` resolves to this server's public IPv4 address
- If IPv6 is configured, ensure AAAA record exists and IPv6 connectivity works, or remove AAAA record
- Ports 80 and 443 allowed through firewall (Phase 1 complete)
- APISIX Gateway running on localhost:9080 only (Phase 1 complete)
- Portal backend has no external port binding (Phase 1 complete)

## Installation Commands

### 1. Install Apache and Certbot
```bash
sudo apt update
sudo apt install -y apache2 certbot python3-certbot-apache
sudo systemctl enable apache2
sudo systemctl start apache2
```

### 2. Enable Required Apache Modules
```bash
sudo a2enmod ssl
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### 3. Create Apache Virtual Host Configuration
```bash
# Copy the configuration file (prepared by Claude)
sudo cp /home/filbern/dev/apisix-gateway/docs/apache-apisix-gateway.conf /etc/apache2/sites-available/apisix-gateway.conf

# Enable the site and disable default
sudo a2ensite apisix-gateway.conf
sudo a2dissite 000-default.conf
sudo systemctl reload apache2
```

### 4. Obtain SSL Certificate with Let's Encrypt
```bash
# Important: This requires the domain to resolve to this server's public IP
sudo certbot --apache --redirect -d lamassu.ita.chalmers.se --non-interactive --agree-tos --email admin@ita.chalmers.se

# Verify certificate installation
sudo certbot certificates
```

### 5. Test Auto-Renewal
```bash
sudo certbot renew --dry-run

# Check renewal timer (may vary by system)
sudo systemctl status certbot.timer
# Alternative check if systemd timer not found:
# sudo systemctl list-timers | grep -i certbot
# ls -la /etc/cron.d/certbot
```

## Configuration Details

### Apache Virtual Host Features
- **Port 80**: ACME challenge support + HTTPS redirect
- **Port 443**: TLS termination + reverse proxy to localhost:9080
- **Headers**: X-Forwarded-Proto, X-Forwarded-For, X-Real-IP
- **Host Preservation**: ProxyPreserveHost On
- **SSL Security**: Modern TLS configuration

### Let's Encrypt Integration
- Automatic certificate provisioning
- 90-day certificate lifecycle
- Automatic renewal via systemd timer
- ACME challenge via HTTP-01

## Verification Steps

After installation, verify:

1. **HTTP Redirect Test**:
   ```bash
   curl -I http://lamassu.ita.chalmers.se
   # Expected: 301/308 redirect to HTTPS
   ```

2. **HTTPS Access Test**:
   ```bash
   curl -I https://lamassu.ita.chalmers.se/portal/
   # Expected: 302 (OIDC redirect) or 200
   ```

3. **Certificate Verification**:
   ```bash
   sudo certbot certificates
   # Expected: Valid certificate for lamassu.ita.chalmers.se
   ```

4. **SSL Security Test**:
   ```bash
   openssl s_client -connect lamassu.ita.chalmers.se:443 -servername lamassu.ita.chalmers.se
   # Expected: Valid TLS handshake
   ```

5. **Auto-Renewal Check**:
   ```bash
   sudo systemctl status certbot.timer
   # Expected: active (waiting)
   ```

## Security Configuration

### SSL/TLS Settings
- **Protocol**: TLS 1.2+ only
- **Ciphers**: Modern cipher suites
- **HSTS**: Enabled with 1-year max-age
- **Security Headers**: X-Content-Type-Options, X-Frame-Options

### Proxy Security
- **Host Header**: Preserved for APISIX routing
- **Real IP**: Forwarded to backend
- **Protocol Info**: HTTPS status forwarded

## Troubleshooting

### Common Issues
1. **DNS Resolution**: Ensure `lamassu.ita.chalmers.se` resolves to server IP
2. **Firewall**: Verify ports 80/443 are accessible externally
3. **APISIX Connectivity**: Confirm localhost:9080 accessible from Apache
4. **Certificate Challenge**: Check domain accessibility during certbot run

### Log Files
- **Apache Error Log**: `/var/log/apache2/error.log`
- **Apache Access Log**: `/var/log/apache2/access.log`
- **Certbot Log**: `/var/log/letsencrypt/letsencrypt.log`

## Next Steps
After successful TLS setup:
- Phase 3: Update OIDC redirect URIs to HTTPS
- Phase 4: Configure rate limiting
- Phase 5: Production hardening
- Phase 6: Final verification

## Rollback Procedure
If issues occur:
```bash
# Disable Apache and revert to direct access
sudo systemctl stop apache2
sudo systemctl disable apache2

# Temporarily allow direct APISIX access for troubleshooting
sudo ufw allow 9080/tcp
```

Note: This should only be used for troubleshooting - proper fix is to resolve TLS issues.