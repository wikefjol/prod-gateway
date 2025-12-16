# APISIX Gateway Public Deployment - Implementation Roadmap

## Git Strategy & Branch Structure

### Branch Model
```
main (production-ready)
├── test-environment (stable baseline)
├── feature/phase-0-security-hygiene
├── feature/phase-1-attack-surface-reduction
├── feature/phase-2-tls-termination
├── feature/phase-3-oidc-domain-fix
├── feature/phase-4-rate-limiting
├── feature/phase-5-production-mode
└── feature/phase-6-verification
```

### Git Workflow Process
1. **Create TEST baseline**: Branch `test-environment` from current working `main`
2. **Phase branches**: Each phase gets its own feature branch
3. **Merge strategy**: Phase branches merge to `main` only after full verification
4. **Rollback safety**: `test-environment` always contains last known good state
5. **Final deployment**: `main` branch represents production-ready code

## Phase Implementation Structure

### Phase 0: Security Hygiene (Pre-Publication)
**Branch**: `feature/phase-0-security-hygiene`
**Goal**: Clean up secrets and sensitive data before public exposure

#### Issues:
- [ ] **Issue #1**: Rotate APISIX Admin Key
  - **DoD**: New admin key generated, all configs updated, old key revoked
  - **Verification**: Admin API accessible with new key only

- [ ] **Issue #2**: Rotate OIDC Session Secrets
  - **DoD**: New session secret generated, configs updated
  - **Verification**: OIDC flow works with new secret

- [ ] **Issue #3**: Scrub Repository for Secrets
  - **DoD**: No secrets, IPs, or hostnames in git history or docs
  - **Verification**: `git log --all -S "secret_pattern"` returns no matches

- [ ] **Issue #4**: Sanitize Documentation
  - **DoD**: All internal hostnames/IPs replaced with placeholders
  - **Verification**: No internal infrastructure details in docs

**Acceptance Criteria**:
- All secrets rotated and functional
- No sensitive data in repository
- Documentation sanitized
- Current functionality preserved

### Phase 1: Attack Surface Reduction
**Branch**: `feature/phase-1-attack-surface-reduction`
**Goal**: Remove direct external access to internal services

#### Issues:
- [ ] **Issue #5**: Remove Portal Backend External Access
  - **DoD**: Portal backend only accessible via Docker network
  - **Files**: `infrastructure/docker/base.yml`
  - **Change**: Remove `0.0.0.0:3001->3000/tcp` port mapping
  - **Verification**: `curl http://external-ip:3001` fails

- [ ] **Issue #6**: Remove APISIX Gateway External Access
  - **DoD**: APISIX only accessible via localhost
  - **Files**: `infrastructure/docker/base.yml`
  - **Change**: Change `0.0.0.0:9080->9080/tcp` to `127.0.0.1:9080->9080/tcp`
  - **Verification**: External access blocked, localhost access works

- [ ] **Issue #7**: Configure Host Firewall Rules
  - **DoD**: Only ports 22, 80, 443 accessible externally
  - **Commands**:
    ```bash
    sudo ufw allow 22/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw deny 9080/tcp
    sudo ufw deny 3001/tcp
    sudo ufw deny 9180/tcp
    sudo ufw --force enable
    ```
  - **Verification**: `nmap -p 9080,3001,9180 external-ip` shows filtered/closed

**Acceptance Criteria**:
- External direct access to APISIX/Portal blocked
- Services still accessible via localhost
- Firewall rules active and verified
- Docker network communication preserved

### Phase 2: TLS Termination Setup
**Branch**: `feature/phase-2-tls-termination`
**Goal**: Add HTTPS termination with Apache/Nginx + certbot

#### Issues:
- [ ] **Issue #8**: Install and Configure Apache/Nginx
  - **DoD**: Web server installed, configured, serving on 80/443
  - **Files**:
    - `/etc/apache2/sites-available/apisix-gateway.conf` (or nginx equivalent)
    - `docs/TLS_SETUP.md` (documentation)
  - **Config Requirements**:
    ```apache
    # Port 80 - ACME + Redirect
    <VirtualHost *:80>
        ServerName your-domain.com
        DocumentRoot /var/www/html
        RewriteEngine On
        RewriteCond %{REQUEST_URI} !^/.well-known/acme-challenge/
        RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
    </VirtualHost>

    # Port 443 - TLS + Proxy
    <VirtualHost *:443>
        ServerName your-domain.com
        SSLEngine on
        ProxyPreserveHost On
        ProxyPass / http://127.0.0.1:9080/
        ProxyPassReverse / http://127.0.0.1:9080/
        Header always set X-Forwarded-Proto "https"
    </VirtualHost>
    ```
  - **Verification**: `curl -I http://domain` returns 301 redirect

- [ ] **Issue #9**: Set up Let's Encrypt with Certbot
  - **DoD**: SSL certificates issued and auto-renewal configured
  - **Commands**:
    ```bash
    sudo certbot --apache -d your-domain.com
    sudo systemctl status certbot.timer
    ```
  - **Verification**:
    - `curl -I https://domain` returns 200
    - `certbot certificates` shows valid cert
    - Renewal timer active

**Acceptance Criteria**:
- HTTPS accessible on port 443
- HTTP redirects to HTTPS
- Valid SSL certificate installed
- Auto-renewal configured and tested
- APISIX accessible through proxy

### Phase 3: OIDC Domain Configuration
**Branch**: `feature/phase-3-oidc-domain-fix`
**Goal**: Update OIDC configuration for public domain

#### Issues:
- [ ] **Issue #10**: Update OIDC Redirect URI Configuration
  - **DoD**: OIDC config points to public HTTPS domain
  - **Files**: `config/providers/entraid/dev.env`
  - **Change**:
    ```bash
    # FROM: OIDC_REDIRECT_URI=http://localhost:9080/portal/callback
    # TO:   OIDC_REDIRECT_URI=https://your-domain.com/portal/callback
    ```
  - **Verification**: Config loaded correctly in environment

- [ ] **Issue #11**: Update EntraID App Registration
  - **DoD**: Azure app registration includes new redirect URI
  - **Tasks**:
    - Add `https://your-domain.com/portal/callback` to EntraID app
    - Remove localhost redirect URIs (after testing)
  - **Verification**: EntraID admin portal shows correct URIs

- [ ] **Issue #12**: Update APISIX Route Configuration
  - **DoD**: Running APISIX routes use new redirect URI
  - **Commands**: Restart services to apply new config
  - **Verification**:
    ```bash
    curl -H "X-API-KEY: $ADMIN_KEY" http://localhost:9180/apisix/admin/routes | jq '.list[].value.plugins."openid-connect".redirect_uri'
    ```

**Acceptance Criteria**:
- OIDC redirect URI uses public HTTPS domain
- EntraID app registration updated
- OIDC flow works end-to-end via HTTPS
- No localhost references in active config

### Phase 4: Rate Limiting Implementation
**Branch**: `feature/phase-4-rate-limiting`
**Goal**: Add abuse protection to all public routes

#### Issues:
- [ ] **Issue #13**: Implement Portal Route Rate Limiting
  - **DoD**: Portal routes have appropriate rate limits
  - **Files**: New rate limiting route templates
  - **Config**:
    ```json
    "limit-req": {
        "rate": 10,
        "burst": 5,
        "rejected_code": 429,
        "key": "remote_addr"
    }
    ```
  - **Verification**: Burst testing triggers 429 responses

- [ ] **Issue #14**: Implement API Route Rate Limiting
  - **DoD**: All `/v1/providers/*/chat` routes rate-limited
  - **Strategy**: Rate limit by API key (consumer) + remote_addr
  - **Config**:
    ```json
    "limit-req": {
        "rate": 60,
        "burst": 10,
        "rejected_code": 429,
        "key": "consumer_name"
    }
    ```
  - **Verification**: API key rate limiting works correctly

- [ ] **Issue #15**: Rate Limiting Documentation & Monitoring
  - **DoD**: Rate limits documented, monitoring alerts configured
  - **Files**:
    - `docs/RATE_LIMITING.md`
    - Rate limiting test scripts
  - **Verification**: Documentation complete and accurate

**Acceptance Criteria**:
- All public routes have appropriate rate limits
- Rate limiting tested and functional
- Documentation updated
- Monitoring/alerting configured (optional)

### Phase 5: Production Mode Enforcement
**Branch**: `feature/phase-5-production-mode`
**Goal**: Disable development features

#### Issues:
- [ ] **Issue #16**: Disable Portal Development Features
  - **DoD**: DEV_MODE explicitly disabled in production
  - **Files**: Environment configuration, Docker configs
  - **Changes**:
    - Set `DEV_MODE=false` explicitly
    - Remove DEV_ADMIN_PASSWORD from environment
  - **Verification**: Dev admin UI not accessible

- [ ] **Issue #17**: Remove Development Debugging Access
  - **DoD**: No debug containers or development bypasses active
  - **Checks**:
    - No debug containers in production compose
    - No header-based auth bypasses externally accessible
  - **Verification**: Only intended public interfaces available

**Acceptance Criteria**:
- All development features disabled
- No debug/admin interfaces exposed
- Production-only configuration active

### Phase 6: Verification & Go-Live
**Branch**: `feature/phase-6-verification`
**Goal**: Comprehensive verification before public announcement

#### Issues:
- [ ] **Issue #18**: External Accessibility Verification
  - **DoD**: External access works correctly via HTTPS only
  - **Tests**:
    ```bash
    # HTTP redirect
    curl -I http://domain.com | grep "301\|308"

    # HTTPS portal access
    curl -I https://domain.com/portal/ | grep "302\|200"

    # API endpoint accessible
    curl -X POST https://domain.com/v1/providers/anthropic/chat \
         -H "apikey: test-key" -H "content-type: application/json" \
         -d '{"model":"claude-3","messages":[{"role":"user","content":"test"}]}'
    ```
  - **Verification**: All tests pass from external machine

- [ ] **Issue #19**: Security Port Scan Verification
  - **DoD**: Only intended ports accessible externally
  - **Tests**:
    ```bash
    nmap -sS -O external-ip
    # Should show only 22, 80, 443 open
    ```
  - **Verification**: No unintended ports exposed

- [ ] **Issue #20**: End-to-End OIDC Flow Verification
  - **DoD**: Complete OIDC authentication works via public domain
  - **Tests**:
    - Navigate to https://domain.com/portal/
    - Complete EntraID authentication
    - Generate API key
    - Use API key for provider requests
  - **Verification**: Full user journey works

**Acceptance Criteria**:
- All external access tests pass
- Security verification complete
- End-to-end user flows functional
- No development/admin interfaces exposed
- Rate limiting functional

## Implementation Strategy

### 1. Setup TEST Environment (Safety Net)
```bash
# Create stable baseline
git checkout main
git checkout -b test-environment
git push -u origin test-environment

# Document current working state
echo "Working demo state as of $(date)" > TEST_BASELINE.md
./scripts/testing/behavior-test.sh > TEST_BASELINE_RESULTS.txt
git add . && git commit -m "Create TEST environment baseline"
```

### 2. Phase Implementation Process
For each phase:
```bash
# Start phase
git checkout main
git checkout -b feature/phase-X-name

# Implement phase
# (work on issues in phase)

# Verify phase
./scripts/testing/behavior-test.sh
# (run phase-specific verification)

# Merge phase (only if verification passes)
git checkout main
git merge feature/phase-X-name
git push origin main

# Safety check - if anything breaks
git checkout test-environment  # Known good state
```

### 3. Rollback Procedures
- **Individual Phase Rollback**: `git revert <merge-commit>`
- **Full Rollback**: `git reset --hard test-environment`
- **Service Rollback**: `git checkout test-environment && ./scripts/lifecycle/start.sh`

### 4. Definition of Done (DoD) Template
Each issue must meet:
- [ ] **Functional**: Feature works as specified
- [ ] **Verified**: Automated/manual testing passes
- [ ] **Documented**: Changes documented appropriately
- [ ] **Secure**: No new security vulnerabilities introduced
- [ ] **Reversible**: Rollback procedure tested and documented

## Timeline Estimate

- **Phase 0** (Security Hygiene): 1-2 days
- **Phase 1** (Attack Surface): 1 day
- **Phase 2** (TLS Setup): 1-2 days
- **Phase 3** (OIDC Config): 1 day
- **Phase 4** (Rate Limiting): 1-2 days
- **Phase 5** (Production Mode): 0.5 days
- **Phase 6** (Verification): 1 day

**Total**: 6.5-9.5 days (allowing buffer for testing/issues)

## Success Criteria

### Technical Success
- [ ] HTTPS-only public access with valid certificates
- [ ] OIDC authentication working with public domain
- [ ] API key authentication and AI provider access functional
- [ ] Rate limiting preventing abuse
- [ ] No internal services exposed directly
- [ ] Admin API remains localhost-only

### Operational Success
- [ ] TEST environment preserved as rollback option
- [ ] All changes properly documented
- [ ] Verification procedures executed and passed
- [ ] Public announcement ready (after Phase 6)

This roadmap provides a safe, systematic approach to your public deployment while maintaining your working demo throughout the process.