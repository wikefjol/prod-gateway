# Legacy Files Analysis Report

**Analysis Date**: December 17, 2025
**Purpose**: Identify files and code that should be moved to the "old" folder for project cleanup
**Scope**: Complete codebase review for deprecated, unused, or legacy components

---

## Executive Summary

After comprehensive analysis of the APISIX Gateway codebase, I have identified several files that should be moved to the "old" folder to clean up the project structure. Most legacy items have already been properly archived, but some backup files and potentially deprecated configurations remain in the active codebase.

**Overall Assessment**: The project is **well-organized** with most legacy items already properly archived in the "old" folder.

---

## Files Recommended for Migration to "old" folder

### 1. Backup Files (Immediate Action Required)

#### **Backup Configuration Files**
```
📁 Current Location → 📁 Recommended Location
config/shared/apisix.env.backup → old/config-backups/apisix.env.backup
secrets/entraid-dev.env.backup → old/secrets-backups/entraid-dev.env.backup
```

**Justification**: These are backup files that are not part of the active configuration system. They should be archived to prevent confusion and maintain clean project structure.

**Risk Assessment**: LOW - These are backup files that won't break functionality if moved.

### 2. Legacy APISIX Configuration Files

#### **Generic Config Template**
```
📁 Current Location → 📁 Recommended Location
apisix/config-template.yaml → old/apisix-configs/config-template.yaml
```

**Analysis**:
- File date: Nov 24 11:00 (older than specific environment templates)
- Current system uses `config-dev-template.yaml` and `config-test-template.yaml`
- Generic template appears superseded by environment-specific templates

**Justification**: This generic config template has been replaced by environment-specific templates (`config-dev-template.yaml`, `config-test-template.yaml`) which provide better separation of concerns.

### 3. Test Results Archives (Optional Cleanup)

#### **Old Test Results**
```
📁 Current Location → 📁 Recommended Action
tests/results/2025-12-09-183445-272156/ → Archive or keep (depends on retention policy)
```

**Analysis**: Test results from December 9, 2025 may be candidates for archival if a retention policy exists.

**Recommendation**: Keep recent test results (last 30 days) but consider archiving older ones based on project retention requirements.

---

## Files That Should **NOT** be Moved

### Current Active Files (Keep in Active Codebase)

#### **Environment-Specific Configurations**
```
✅ KEEP: apisix/config-dev-template.yaml
✅ KEEP: apisix/config-test-template.yaml
✅ KEEP: apisix/config-dev-static.yaml
✅ KEEP: apisix/config-test-static.yaml
```
**Reason**: These are actively used environment-specific configurations.

#### **Current Scripts**
```
✅ KEEP: scripts/bootstrap/bootstrap.sh
✅ KEEP: scripts/bootstrap/bootstrap-core.sh
✅ KEEP: All files in scripts/ directory
```
**Reason**: All scripts in the scripts/ directory are actively used and part of the current system architecture.

#### **Example/Template Files**
```
✅ KEEP: secrets/entraid-test.env.example
```
**Reason**: This is an active template file for setting up test environment credentials.

#### **Route Definitions**
```
✅ KEEP: All *.json files in apisix/ directory
```
**Reason**: These are active route definitions used by the current system.

---

## Code Patterns Analysis

### Potential Legacy Code Patterns Found

#### **Legacy Variable Names in OIDC Routes**

**File**: `apisix/oidc-route.json`
```json
{
  "plugins": {
    "openid-connect": {
      "client_id": "$AZURE_CLIENT_ID",        // ⚠️ Legacy naming
      "client_secret": "$AZURE_CLIENT_SECRET", // ⚠️ Legacy naming
      "discovery": "https://login.microsoftonline.com/$AZURE_TENANT_ID/..."
    }
  }
}
```

**Analysis**: Uses `$AZURE_*` variables instead of the current `$OIDC_*` standard used in `oidc-generic-route.json`.

**Recommendation**:
- **Option 1**: Update variable names to match current standard (`$OIDC_CLIENT_ID`, `$OIDC_CLIENT_SECRET`)
- **Option 2**: Move to old/ folder if this route is no longer used
- **Action Required**: Verify if this route is still actively deployed

#### **Loader Service Legacy Variables**

**File**: `infrastructure/docker/base.yml` (lines 99-103)
```yaml
# Legacy variables for backward compatibility
- AZURE_CLIENT_ID=${AZURE_CLIENT_ID:-${OIDC_CLIENT_ID}}
- AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET:-${OIDC_CLIENT_SECRET}}
- AZURE_TENANT_ID=${AZURE_TENANT_ID:-}
- REDIRECT_URI=${REDIRECT_URI:-${OIDC_REDIRECT_URI}}
```

**Analysis**: These are legacy compatibility mappings that may no longer be needed.

**Recommendation**:
1. Verify if any routes still use `$AZURE_*` or `$REDIRECT_URI` variables
2. If not used, remove these legacy mappings
3. If still needed, document why they are maintained

---

## Already Properly Archived Items

### Well-Organized Legacy Archive

The "old" folder already contains comprehensive legacy items:

#### **Legacy Scripts** ✅ Already Archived
- `bootstrap-oidc-dev.sh` → Replaced by `scripts/bootstrap/bootstrap-core.sh`
- `bootstrap-portal-dev.sh` → Replaced by modular bootstrap system
- `start-dev.sh`, `start-test.sh` → Replaced by `scripts/lifecycle/start.sh`
- `setup-keycloak-dev.sh` → Integrated into current provider system

#### **Legacy Configuration** ✅ Already Archived
- `docker-compose.dev.yml` → Replaced by modular compose files in `infrastructure/docker/`
- `.dev.env`, `.test.env` → Replaced by hierarchical config system in `config/`
- Various legacy environment files

#### **Legacy Documentation** ✅ Already Archived
- `README.md` (old version) → Replaced by new comprehensive README
- `MAINTAINERS_GUIDE.md` (old version) → Replaced by new detailed guide
- `PORTAL_SPECS.md` → Historical specifications
- `IMPLEMENTATION_ROADMAP.md` → Completed implementation

---

## Recommended Actions

### Immediate Actions (Low Risk)

1. **Move Backup Files**:
   ```bash
   # Create backup directories in old/
   mkdir -p old/config-backups
   mkdir -p old/secrets-backups

   # Move backup files
   mv config/shared/apisix.env.backup old/config-backups/
   mv secrets/entraid-dev.env.backup old/secrets-backups/
   ```

2. **Archive Generic Config Template** (if verified as unused):
   ```bash
   mkdir -p old/apisix-configs
   mv apisix/config-template.yaml old/apisix-configs/
   ```

### Investigation Required

1. **Verify OIDC Route Usage**:
   ```bash
   # Check if oidc-route.json is still deployed
   grep -r "oidc-auth-callback" scripts/
   # Check for AZURE_* variable usage
   grep -r "AZURE_CLIENT_ID" apisix/ config/ scripts/
   ```

2. **Clean Up Legacy Variables** (after verification):
   ```bash
   # If AZURE_* variables are not used, remove from base.yml
   # Update any remaining routes to use OIDC_* variables
   ```

### Optional Actions

1. **Test Results Archival** (based on retention policy):
   ```bash
   # Archive test results older than 30 days
   find tests/results/ -type d -mtime +30 -exec mv {} old/test-archives/ \;
   ```

---

## Code Quality Observations

### Positive Findings

1. **Excellent Legacy Management**: Most legacy items are already properly archived
2. **Clean Migration**: Transition from legacy scripts to new architecture is well-documented
3. **Proper Gitignore**: Sensitive files and generated files are properly excluded
4. **Version Control Hygiene**: No obvious version control artifacts or IDE files in main codebase

### Areas for Improvement

1. **Variable Naming Consistency**: Some routes still use legacy `AZURE_*` variable names
2. **Backup File Management**: Backup files should be moved to archive locations
3. **Template File Clarity**: Generic templates should be clearly marked as deprecated or removed

---

## Impact Assessment

### Moving Recommended Files to "old" Folder

**Configuration Impact**:
- ✅ **SAFE**: Moving backup files will not affect system functionality
- ⚠️ **VERIFY FIRST**: Moving `config-template.yaml` requires verification that it's not referenced

**Operational Impact**:
- ✅ **POSITIVE**: Cleaner project structure
- ✅ **POSITIVE**: Reduced confusion about which files are current
- ✅ **NEUTRAL**: No impact on running systems

**Development Impact**:
- ✅ **POSITIVE**: Easier for new developers to understand current vs. legacy
- ✅ **POSITIVE**: Reduced cognitive load when navigating project

---

## Conclusion

The APISIX Gateway project demonstrates **excellent legacy management practices** with most deprecated items already properly archived. The recommended actions are primarily **housekeeping tasks** to move remaining backup files and potentially unused templates.

**Key Findings**:
1. **Most legacy items are already properly archived** in the "old" folder
2. **Backup files should be moved** to maintain clean project structure
3. **Some inconsistent variable naming** exists between old and new OIDC routes
4. **Overall project hygiene is very good**

**Priority Actions**:
1. **HIGH**: Move backup files to old/ folder (safe operation)
2. **MEDIUM**: Investigate and clean up legacy OIDC variable usage
3. **LOW**: Archive old test results based on retention policy

**Estimated Effort**: 1-2 hours for complete cleanup

The project maintainers have done an excellent job managing technical debt and legacy code. The recommended changes are minor improvements rather than critical issues.

---

**Analysis Complete**
**Files Ready for Migration**: 2-3 backup files
**Investigation Required**: 1-2 configuration files
**Overall Project Cleanliness**: Excellent (A-)