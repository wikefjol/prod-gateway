#!/usr/bin/env python3
"""
Self-Service API Key Portal Backend
APISIX + OIDC Integration

Implements the v0 spec for self-service API key management:
- 1:1 mapping between OIDC users and APISIX Consumers
- Exactly 0 or 1 key-auth credential per Consumer
- "Get key" and "Recycle key" operations
- Secure key generation using CSPRNG
"""

import os
import secrets
import logging
import json
import base64
from typing import Optional, Dict, Any, List
from datetime import datetime

import requests
from flask import Flask, request, render_template, jsonify, redirect, url_for

# Configure logging per specs - never log full keys
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__, template_folder='../templates')

# ===== DEVELOPMENT MODE CONFIGURATION =====
# Security-first development access for testing without OIDC

DEV_MODE = os.getenv('DEV_MODE', 'false').lower() == 'true'
DEV_ADMIN_PASSWORD = os.getenv('DEV_ADMIN_PASSWORD', '')
ENVIRONMENT = os.getenv('ENVIRONMENT', 'dev')

# Environment allowlist for DEV_MODE (blocklist pattern was insufficient)
ALLOWED_DEV_ENVIRONMENTS = ['local', 'development', 'dev', 'test']

if DEV_MODE and ENVIRONMENT not in ALLOWED_DEV_ENVIRONMENTS:
    logger.error(f"SECURITY LOCKOUT: DEV_MODE blocked in '{ENVIRONMENT}' (allowed: {ALLOWED_DEV_ENVIRONMENTS})")
    raise ValueError(f"DEV_MODE only allowed in: {ALLOWED_DEV_ENVIRONMENTS}")

if DEV_MODE:
    if not DEV_ADMIN_PASSWORD:
        logger.error("DEV_ADMIN_PASSWORD is required when DEV_MODE=true")
        raise ValueError("DEV_ADMIN_PASSWORD must be set for development mode")

    logger.warning("⚠️  DEVELOPMENT MODE ENABLED - This should NEVER be used in production!")
    logger.warning("⚠️  Development admin routes available at /dev/admin/")
    logger.warning(f"⚠️  Environment: {ENVIRONMENT}")

class DevModeManager:
    """Secure development mode functionality with audit logging"""

    def __init__(self):
        self.enabled = DEV_MODE
        self.admin_password = DEV_ADMIN_PASSWORD
        self.test_users = {
            'dev-user-123': {
                'user_oid': 'dev-user-123',
                'user_name': 'Development User',
                'user_email': 'dev-user@example.com'
            },
            'test-alice': {
                'user_oid': 'test-alice',
                'user_name': 'Alice Developer',
                'user_email': 'alice@dev.example.com'
            },
            'test-bob': {
                'user_oid': 'test-bob',
                'user_name': 'Bob Tester',
                'user_email': 'bob@test.example.com'
            }
        }

    def is_enabled(self) -> bool:
        """Check if development mode is enabled"""
        return self.enabled

    def verify_admin_password(self, password: str) -> bool:
        """Verify development admin password"""
        if not self.enabled:
            return False

        is_valid = password == self.admin_password
        if is_valid:
            logger.warning("🔐 DEV_MODE: Admin access granted")
        else:
            logger.warning("❌ DEV_MODE: Invalid admin password attempt")

        return is_valid

    def get_test_users(self) -> Dict[str, Dict[str, str]]:
        """Get available test users"""
        if not self.enabled:
            return {}
        return self.test_users.copy()

    def get_test_user(self, user_id: str) -> Optional[Dict[str, str]]:
        """Get specific test user"""
        if not self.enabled:
            return None
        return self.test_users.get(user_id)

    def audit_log(self, action: str, details: str = ""):
        """Audit log for development mode actions"""
        if self.enabled:
            logger.warning(f"🔍 DEV_MODE AUDIT: {action} - {details}")

# Initialize development mode manager
dev_mode = DevModeManager() if DEV_MODE else None

class APIKey:
    """Secure API key generation and management"""

    @staticmethod
    def generate() -> str:
        """Generate a secure API key using CSPRNG and base64url encoding

        Returns:
            32 bytes of randomness encoded as base64url string
        """
        return secrets.token_urlsafe(32)

    @staticmethod
    def get_fingerprint(key: str) -> str:
        """Get a truncated fingerprint for logging purposes"""
        return f"{key[:8]}...{key[-4:]}"

class APISIXClient:
    """APISIX Admin API client for Consumer and Credential management"""

    def __init__(self):
        self.admin_api = os.getenv('APISIX_ADMIN_API_CONTAINER', 'http://apisix-dev:9180/apisix/admin')
        self.admin_key = os.getenv('ADMIN_KEY')

        if not self.admin_key:
            raise ValueError("ADMIN_KEY environment variable is required")

        self.headers = {
            'X-API-KEY': self.admin_key,
            'Content-Type': 'application/json'
        }

        logger.info(f"APISIX Client initialized with admin API: {self.admin_api}")

    def _make_request(self, method: str, path: str, data: Optional[Dict] = None) -> requests.Response:
        """Make authenticated request to APISIX Admin API"""
        url = f"{self.admin_api}/{path.lstrip('/')}"

        try:
            response = requests.request(
                method=method.upper(),
                url=url,
                headers=self.headers,
                json=data,
                timeout=10
            )
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            error_detail = ""
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = f" - Response: {e.response.text}"
                except:
                    error_detail = ""
            logger.error(f"APISIX API request failed: {method} {url} - {e}{error_detail}")
            raise

    def find_consumer(self, user_oid: str) -> Optional[Dict[str, Any]]:
        """Find Consumer by username (user_oid)

        Args:
            user_oid: The OIDC user OID to search for

        Returns:
            Consumer data if found, None otherwise
        """
        try:
            response = self._make_request('GET', f'consumers/{user_oid}')
            consumer_data = response.json()

            if 'value' in consumer_data:
                logger.info(f"Found existing consumer for user_oid: {user_oid}")
                return consumer_data['value']

        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                logger.info(f"No existing consumer found for user_oid: {user_oid}")
                return None
            raise

        return None

    def create_consumer(self, user_oid: str, user_name: str = None, user_email: str = None) -> Dict[str, Any]:
        """Create a new Consumer for the user

        Args:
            user_oid: OIDC user OID
            user_name: Display name for description
            user_email: Email for description

        Returns:
            Created Consumer data
        """
        consumer_data = {
            "username": user_oid,
            "desc": f"Created by SSO portal for {user_name or 'user'} ({user_email or 'no-email'})",
            "labels": {
                "source": "oidc-portal-v0",
                "created_at": datetime.utcnow().isoformat()
            },
            "group_id": "base_user"
        }

        response = self._make_request('PUT', f'consumers/{user_oid}', consumer_data)
        created_consumer = response.json()

        logger.info(f"Created consumer for user_oid: {user_oid}, name: {user_name}, assigned to base_user group")
        return created_consumer['value'] if 'value' in created_consumer else created_consumer

    def get_consumer_credentials(self, user_oid: str) -> List[Dict[str, Any]]:
        """Get key-auth credentials for a Consumer by checking plugins

        Args:
            user_oid: Consumer username/user_oid

        Returns:
            List with key-auth credential if exists, empty list otherwise
        """
        try:
            response = self._make_request('GET', f'consumers/{user_oid}')
            consumer_data = response.json()

            if 'value' in consumer_data:
                consumer = consumer_data['value']
                plugins = consumer.get('plugins', {})
                key_auth = plugins.get('key-auth', {})

                if key_auth and 'key' in key_auth:
                    # Return credential in compatible format
                    credential = {
                        'id': 'key-auth',  # Use plugin name as ID
                        'key': key_auth['key']
                    }
                    logger.info(f"Found key-auth credential for user_oid: {user_oid}")
                    return [credential]

            logger.info(f"No key-auth credential found for user_oid: {user_oid}")
            return []

        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                logger.info(f"No consumer found for user_oid: {user_oid}")
                return []
            raise

    def create_credential(self, user_oid: str, api_key: str) -> Dict[str, Any]:
        """Create a key-auth credential for the Consumer by updating plugins

        Args:
            user_oid: Consumer username
            api_key: The generated API key

        Returns:
            Created credential data
        """
        # Get current consumer data
        response = self._make_request('GET', f'consumers/{user_oid}')
        consumer_data = response.json()['value']

        # Remove ETCD metadata fields that are forbidden in updates
        consumer_update = {
            "username": consumer_data["username"],
            "desc": consumer_data.get("desc", ""),
            "labels": consumer_data.get("labels", {}),
            "plugins": consumer_data.get("plugins", {})
        }

        # Add key-auth plugin
        consumer_update['plugins']['key-auth'] = {"key": api_key}

        # Update consumer with new plugin
        response = self._make_request('PUT', f'consumers/{user_oid}', consumer_update)
        updated_consumer = response.json()

        key_fingerprint = APIKey.get_fingerprint(api_key)
        logger.info(f"Created key-auth credential for user_oid: {user_oid}, key_fingerprint: {key_fingerprint}")

        return {"id": "key-auth", "key": api_key}

    def update_credential(self, user_oid: str, credential_id: str, api_key: str) -> Dict[str, Any]:
        """Update existing key-auth credential with new key

        Args:
            user_oid: Consumer username
            credential_id: Credential ID (ignored for key-auth plugin)
            api_key: New API key

        Returns:
            Updated credential data
        """
        # Get current consumer data
        response = self._make_request('GET', f'consumers/{user_oid}')
        consumer_data = response.json()['value']

        # Remove ETCD metadata fields that are forbidden in updates
        consumer_update = {
            "username": consumer_data["username"],
            "desc": consumer_data.get("desc", ""),
            "labels": consumer_data.get("labels", {}),
            "plugins": consumer_data.get("plugins", {})
        }

        # Update key-auth plugin
        consumer_update['plugins']['key-auth'] = {"key": api_key}

        # Update consumer with new plugin
        response = self._make_request('PUT', f'consumers/{user_oid}', consumer_update)
        updated_consumer = response.json()

        key_fingerprint = APIKey.get_fingerprint(api_key)
        logger.info(f"Updated key-auth credential for user_oid: {user_oid}, key_fingerprint: {key_fingerprint}")

        return {"id": "key-auth", "key": api_key}

    def update_consumer_group(self, user_oid: str, new_group_id: str) -> Dict[str, Any]:
        """Update consumer's group assignment

        Args:
            user_oid: Consumer username
            new_group_id: New consumer group ID (e.g., "premium_user")

        Returns:
            Updated consumer data
        """
        # Get current consumer data
        response = self._make_request('GET', f'consumers/{user_oid}')
        consumer_data = response.json()['value']

        # Remove ETCD metadata fields that are forbidden in updates
        consumer_update = {
            "username": consumer_data["username"],
            "desc": consumer_data.get("desc", ""),
            "labels": consumer_data.get("labels", {}),
            "plugins": consumer_data.get("plugins", {}),
            "group_id": new_group_id
        }

        # Update consumer
        response = self._make_request('PUT', f'consumers/{user_oid}', consumer_update)
        updated_consumer = response.json()

        logger.info(f"Updated consumer {user_oid} group assignment to: {new_group_id}")
        return updated_consumer['value'] if 'value' in updated_consumer else updated_consumer

    def migrate_consumer_to_base_group(self, user_oid: str) -> bool:
        """Migrate existing consumer to base_user group

        Args:
            user_oid: Consumer username

        Returns:
            True if successful, False if consumer not found
        """
        try:
            # Check if consumer exists
            consumer = self.find_consumer(user_oid)
            if not consumer:
                return False

            # Only update if not already in a group
            if consumer.get('group_id') is None:
                self.update_consumer_group(user_oid, 'base_user')
                logger.info(f"Migrated consumer {user_oid} to base_user group")

            return True
        except Exception as e:
            logger.error(f"Failed to migrate consumer {user_oid}: {e}")
            return False

class PortalService:
    """Main portal service implementing the self-service API key logic"""

    def __init__(self):
        self.apisix = APISIXClient()

    def resolve_user_identity(self, headers: Dict[str, str]) -> Dict[str, str]:
        """Extract user identity from APISIX-injected headers

        Args:
            headers: Request headers from APISIX

        Returns:
            Dictionary with user identity information

        Raises:
            ValueError: If required headers are missing
        """
        userinfo_header = headers.get('X-Userinfo')
        id_token_header = headers.get('X-Id-Token')

        # Try X-Userinfo first (preferred method)
        if userinfo_header:
            try:
                # Decode the userinfo JSON
                userinfo = json.loads(userinfo_header)

                # Extract user identity from claims
                user_oid = userinfo.get('oid') or userinfo.get('sub')
                if not user_oid:
                    raise ValueError("Missing 'oid' or 'sub' claim in userinfo")

                user_identity = {
                    'user_oid': user_oid,
                    'user_name': userinfo.get('name', 'Unknown User'),
                    'user_email': userinfo.get('email') or userinfo.get('preferred_username', 'unknown@example.com')
                }

                logger.info(f"Resolved user identity from X-Userinfo: {user_identity['user_oid']} ({user_identity['user_name']})")
                return user_identity

            except json.JSONDecodeError as e:
                logger.warning(f"Invalid JSON in X-Userinfo header: {e}, trying X-Id-Token fallback")

        # Fallback to X-Id-Token (base64 JSON decoding)
        if id_token_header:
            try:
                # APISIX sends the ID token as base64-encoded JSON payload (not full JWT)
                # Add padding if needed for base64 decoding
                payload_b64 = id_token_header
                payload_b64 += '=' * (4 - len(payload_b64) % 4)
                payload_json = base64.b64decode(payload_b64).decode('utf-8')

                # Parse token payload
                jwt_claims = json.loads(payload_json)

                # Extract user identity from JWT claims
                user_oid = jwt_claims.get('oid') or jwt_claims.get('sub')
                if not user_oid:
                    raise ValueError("Missing 'oid' or 'sub' claim in ID token")

                user_identity = {
                    'user_oid': user_oid,
                    'user_name': jwt_claims.get('name', 'Unknown User'),
                    'user_email': jwt_claims.get('email') or jwt_claims.get('preferred_username', 'unknown@example.com')
                }

                logger.info(f"Resolved user identity from X-Id-Token: {user_identity['user_oid']} ({user_identity['user_name']})")
                return user_identity

            except (ValueError, json.JSONDecodeError, IndexError) as e:
                logger.error(f"Failed to decode X-Id-Token: {e}")

        # If both methods fail
        raise ValueError("Missing X-Userinfo header and unable to decode X-Id-Token - user not authenticated")

    def ensure_consumer_exists(self, user_identity: Dict[str, str]) -> Dict[str, Any]:
        """Ensure Consumer exists for the user, create if missing

        Args:
            user_identity: User identity from headers

        Returns:
            Consumer data
        """
        user_oid = user_identity['user_oid']

        # Try to find existing consumer
        consumer = self.apisix.find_consumer(user_oid)

        if consumer is None:
            # Create new consumer
            consumer = self.apisix.create_consumer(
                user_oid=user_oid,
                user_name=user_identity['user_name'],
                user_email=user_identity['user_email']
            )

        return consumer

    def get_or_create_api_key(self, user_identity: Dict[str, str]) -> str:
        """Get existing API key or create a new one

        Implements the "Get key" operation from specs:
        - If exactly one credential exists: return its key
        - If none exist: generate new key and create credential

        Args:
            user_identity: User identity from headers

        Returns:
            The API key (existing or newly created)
        """
        user_oid = user_identity['user_oid']

        # Ensure consumer exists
        self.ensure_consumer_exists(user_identity)

        # Get existing credentials
        credentials = self.apisix.get_consumer_credentials(user_oid)

        if len(credentials) == 1:
            # Return existing key
            existing_key = credentials[0]['key']
            key_fingerprint = APIKey.get_fingerprint(existing_key)
            logger.info(f"Returning existing API key for user_oid: {user_oid}, key_fingerprint: {key_fingerprint}")
            return existing_key

        elif len(credentials) == 0:
            # Generate new key and create credential
            new_key = APIKey.generate()
            self.apisix.create_credential(user_oid, new_key)

            key_fingerprint = APIKey.get_fingerprint(new_key)
            logger.info(f"Generated new API key for user_oid: {user_oid}, key_fingerprint: {key_fingerprint}")
            return new_key

        else:
            # Should never happen in v0 - enforce exactly one credential
            logger.error(f"Found {len(credentials)} credentials for user_oid: {user_oid}, expected 0 or 1")
            raise ValueError(f"Unexpected number of credentials: {len(credentials)}")

    def recycle_api_key(self, user_identity: Dict[str, str]) -> str:
        """Rotate/recycle the API key

        Implements the "Recycle key" operation from specs:
        - If none exist: treat as "Get key"
        - If one exists: generate new key and update credential

        Args:
            user_identity: User identity from headers

        Returns:
            The new API key
        """
        user_oid = user_identity['user_oid']

        # Ensure consumer exists
        self.ensure_consumer_exists(user_identity)

        # Get existing credentials
        credentials = self.apisix.get_consumer_credentials(user_oid)

        # Generate new key
        new_key = APIKey.generate()

        if len(credentials) == 0:
            # No existing credential - create new one
            self.apisix.create_credential(user_oid, new_key)
            logger.info(f"Created new API key during recycle for user_oid: {user_oid}")

        elif len(credentials) == 1:
            # Update existing credential
            credential_id = credentials[0]['id']
            self.apisix.update_credential(user_oid, credential_id, new_key)
            logger.info(f"Recycled API key for user_oid: {user_oid}, credential_id: {credential_id}")

        else:
            logger.error(f"Found {len(credentials)} credentials for user_oid: {user_oid}, expected 0 or 1")
            raise ValueError(f"Unexpected number of credentials: {len(credentials)}")

        key_fingerprint = APIKey.get_fingerprint(new_key)
        logger.info(f"Recycled API key for user_oid: {user_oid}, new_key_fingerprint: {key_fingerprint}")
        return new_key

# Initialize portal service
portal_service = PortalService()

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "portal-backend"})

@app.route('/portal/')
@app.route('/portal')
def portal_dashboard():
    """Main portal dashboard - shows current API key status"""
    try:
        # TEMPORARY DEBUG: Log all headers
        logger.info("=== DEBUG: All received headers ===")
        for header_name, header_value in request.headers:
            if header_name.startswith('X-'):
                # For X-Userinfo, show first 100 chars to avoid logging sensitive data
                if header_name == 'X-Userinfo':
                    logger.info(f"{header_name}: {header_value[:100]}...")
                else:
                    logger.info(f"{header_name}: {header_value}")
        logger.info("=== END DEBUG HEADERS ===")

        # Extract user identity from headers
        user_identity = portal_service.resolve_user_identity(dict(request.headers))

        # Check if user has existing credentials
        user_oid = user_identity['user_oid']
        portal_service.ensure_consumer_exists(user_identity)
        credentials = portal_service.apisix.get_consumer_credentials(user_oid)

        # Determine current state
        has_key = len(credentials) > 0
        current_key = credentials[0]['key'] if has_key else None

        return render_template('dashboard.html',
                             user_identity=user_identity,
                             has_key=has_key,
                             current_key=current_key)

    except ValueError as e:
        logger.warning(f"Authentication error: {e}")
        return jsonify({"error": "Authentication required", "details": str(e)}), 401

    except Exception as e:
        logger.error(f"Portal dashboard error: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/portal/get-key', methods=['POST'])
def get_api_key():
    """Get API key endpoint"""
    try:
        user_identity = portal_service.resolve_user_identity(dict(request.headers))
        api_key = portal_service.get_or_create_api_key(user_identity)

        return jsonify({
            "success": True,
            "api_key": api_key,
            "message": "API key retrieved successfully"
        })

    except ValueError as e:
        logger.warning(f"Authentication error in get-key: {e}")
        return jsonify({"error": "Authentication required", "details": str(e)}), 401

    except Exception as e:
        logger.error(f"Get API key error: {e}")
        return jsonify({"error": "Failed to get API key", "details": str(e)}), 500

@app.route('/portal/recycle-key', methods=['POST'])
def recycle_api_key():
    """Recycle API key endpoint"""
    try:
        user_identity = portal_service.resolve_user_identity(dict(request.headers))
        new_api_key = portal_service.recycle_api_key(user_identity)

        return jsonify({
            "success": True,
            "api_key": new_api_key,
            "message": "API key recycled successfully - previous key is now invalid"
        })

    except ValueError as e:
        logger.warning(f"Authentication error in recycle-key: {e}")
        return jsonify({"error": "Authentication required", "details": str(e)}), 401

    except Exception as e:
        logger.error(f"Recycle API key error: {e}")
        return jsonify({"error": "Failed to recycle API key", "details": str(e)}), 500

# ===== DEVELOPMENT ADMIN ROUTES =====
# Secure development access for testing without OIDC

def dev_mode_required(f):
    """Decorator to ensure DEV_MODE is enabled"""
    def wrapper(*args, **kwargs):
        if not DEV_MODE:
            return jsonify({"error": "Development mode not enabled"}), 403
        return f(*args, **kwargs)
    wrapper.__name__ = f.__name__
    return wrapper

def dev_admin_auth_required(f):
    """Decorator to require admin authentication in dev mode"""
    def wrapper(*args, **kwargs):
        if not DEV_MODE:
            return jsonify({"error": "Development mode not enabled"}), 403

        # Check for admin password in request
        password = request.form.get('admin_password') or request.json.get('admin_password') if request.json else None
        auth_header = request.headers.get('Authorization', '')

        if auth_header.startswith('Bearer '):
            password = auth_header.replace('Bearer ', '')

        if not password or not dev_mode.verify_admin_password(password):
            return jsonify({"error": "Invalid development admin credentials"}), 401

        return f(*args, **kwargs)
    wrapper.__name__ = f.__name__
    return wrapper

@app.route('/dev/admin/')
@app.route('/dev/admin')
@dev_mode_required
def dev_admin_dashboard():
    """Development admin interface dashboard"""
    dev_mode.audit_log("Admin dashboard accessed")

    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Development Admin - Portal Backend</title>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
            .container {{ max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
            .warning {{ background: #fff3cd; border: 1px solid #ffeaa7; color: #856404; padding: 15px; border-radius: 4px; margin-bottom: 20px; }}
            .form-group {{ margin-bottom: 15px; }}
            label {{ display: block; margin-bottom: 5px; font-weight: bold; }}
            input, select {{ width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }}
            button {{ background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }}
            button:hover {{ background: #0056b3; }}
            .user-list {{ margin-top: 20px; }}
            .user-item {{ background: #f8f9fa; padding: 10px; margin: 5px 0; border-radius: 4px; }}
            .results {{ margin-top: 20px; padding: 15px; background: #e9ecef; border-radius: 4px; }}
            .error {{ color: #dc3545; }}
            .success {{ color: #28a745; }}
            h1, h2 {{ color: #333; }}
            pre {{ background: #f8f9fa; padding: 10px; border-radius: 4px; overflow-x: auto; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔧 Development Admin Portal</h1>

            <div class="warning">
                <strong>⚠️ DEVELOPMENT MODE ACTIVE</strong><br>
                This interface is only available in development mode and should NEVER be enabled in production.
                Environment: {ENVIRONMENT}
            </div>

            <h2>🔐 Admin Authentication</h2>
            <div class="form-group">
                <label for="admin-password">Admin Password:</label>
                <input type="password" id="admin-password" placeholder="Enter DEV_ADMIN_PASSWORD">
            </div>

            <h2>👥 Test Users</h2>
            <div class="user-list">
                <div class="user-item"><strong>dev-user-123</strong> - Development User (dev-user@example.com)</div>
                <div class="user-item"><strong>test-alice</strong> - Alice Developer (alice@dev.example.com)</div>
                <div class="user-item"><strong>test-bob</strong> - Bob Tester (bob@test.example.com)</div>
            </div>

            <h2>🧪 User Simulation</h2>
            <div class="form-group">
                <label for="user-select">Select Test User:</label>
                <select id="user-select">
                    <option value="dev-user-123">dev-user-123 - Development User</option>
                    <option value="test-alice">test-alice - Alice Developer</option>
                    <option value="test-bob">test-bob - Bob Tester</option>
                </select>
            </div>
            <button onclick="simulateUser()">Simulate User Portal Access</button>
            <button onclick="getUserKey()">Get User API Key</button>
            <button onclick="recycleUserKey()">Recycle User API Key</button>
            <button onclick="resetUser()">Reset User (Delete Consumer)</button>

            <div id="results" class="results" style="display: none;">
                <h3>Results:</h3>
                <pre id="results-content"></pre>
            </div>

            <h2>🔗 Quick Links</h2>
            <p>
                <a href="/health" target="_blank">Health Check</a> |
                <a href="http://localhost:9180" target="_blank">APISIX Admin</a> |
                <a href="http://localhost:9080/portal/" target="_blank">Portal (OIDC)</a>
            </p>
        </div>

        <script>
            function getAdminPassword() {{
                return document.getElementById('admin-password').value;
            }}

            function getSelectedUser() {{
                return document.getElementById('user-select').value;
            }}

            function showResults(data, isError = false) {{
                const results = document.getElementById('results');
                const content = document.getElementById('results-content');
                content.textContent = JSON.stringify(data, null, 2);
                content.className = isError ? 'error' : 'success';
                results.style.display = 'block';
            }}

            async function makeAuthenticatedRequest(url, method = 'GET', body = null) {{
                const password = getAdminPassword();
                if (!password) {{
                    alert('Please enter admin password');
                    return;
                }}

                try {{
                    const options = {{
                        method: method,
                        headers: {{
                            'Authorization': `Bearer ${{password}}`,
                            'Content-Type': 'application/json'
                        }}
                    }};

                    if (body) {{
                        options.body = JSON.stringify(body);
                    }}

                    const response = await fetch(url, options);
                    const data = await response.json();

                    if (!response.ok) {{
                        showResults(data, true);
                    }} else {{
                        showResults(data, false);
                    }}
                }} catch (error) {{
                    showResults({{ error: error.message }}, true);
                }}
            }}

            async function simulateUser() {{
                const userId = getSelectedUser();
                await makeAuthenticatedRequest(`/dev/admin/simulate-user/${{userId}}`, 'POST');
            }}

            async function getUserKey() {{
                const userId = getSelectedUser();
                await makeAuthenticatedRequest(`/dev/admin/test-user/${{userId}}/get-key`, 'POST');
            }}

            async function recycleUserKey() {{
                const userId = getSelectedUser();
                await makeAuthenticatedRequest(`/dev/admin/test-user/${{userId}}/recycle-key`, 'POST');
            }}

            async function resetUser() {{
                const userId = getSelectedUser();
                if (confirm(`Are you sure you want to reset user ${{userId}}? This will delete their Consumer and API key.`)) {{
                    await makeAuthenticatedRequest(`/dev/admin/reset-user/${{userId}}`, 'POST');
                }}
            }}
        </script>
    </body>
    </html>
    """

@app.route('/dev/admin/users')
@dev_admin_auth_required
def dev_admin_list_users():
    """List available test users"""
    dev_mode.audit_log("Test users list requested")

    return jsonify({
        "success": True,
        "test_users": dev_mode.get_test_users(),
        "message": "Available test users for development mode"
    })

@app.route('/dev/admin/simulate-user/<user_id>', methods=['POST'])
@dev_admin_auth_required
def dev_admin_simulate_user(user_id):
    """Simulate user login for testing portal functionality"""
    test_user = dev_mode.get_test_user(user_id)

    if not test_user:
        dev_mode.audit_log(f"Invalid user simulation attempt", f"user_id: {user_id}")
        return jsonify({"error": "Test user not found", "user_id": user_id}), 404

    dev_mode.audit_log(f"User simulation", f"user_id: {user_id}")

    try:
        # Check if user has existing credentials
        user_oid = test_user['user_oid']
        portal_service.ensure_consumer_exists(test_user)
        credentials = portal_service.apisix.get_consumer_credentials(user_oid)

        # Determine current state
        has_key = len(credentials) > 0
        current_key_fingerprint = APIKey.get_fingerprint(credentials[0]['key']) if has_key else None

        return jsonify({
            "success": True,
            "user_identity": test_user,
            "has_key": has_key,
            "current_key_fingerprint": current_key_fingerprint,
            "message": f"Successfully simulated user {user_id}"
        })

    except Exception as e:
        dev_mode.audit_log(f"User simulation failed", f"user_id: {user_id}, error: {str(e)}")
        return jsonify({"error": "User simulation failed", "details": str(e)}), 500

@app.route('/dev/admin/test-user/<user_id>/get-key', methods=['POST'])
@dev_admin_auth_required
def dev_admin_test_get_key(user_id):
    """Test get key operation for a test user"""
    test_user = dev_mode.get_test_user(user_id)

    if not test_user:
        return jsonify({"error": "Test user not found", "user_id": user_id}), 404

    dev_mode.audit_log(f"Test get key operation", f"user_id: {user_id}")

    try:
        api_key = portal_service.get_or_create_api_key(test_user)
        key_fingerprint = APIKey.get_fingerprint(api_key)

        return jsonify({
            "success": True,
            "api_key": api_key,
            "key_fingerprint": key_fingerprint,
            "message": "API key retrieved successfully",
            "user_id": user_id
        })

    except Exception as e:
        dev_mode.audit_log(f"Test get key failed", f"user_id: {user_id}, error: {str(e)}")
        return jsonify({"error": "Failed to get API key", "details": str(e)}), 500

@app.route('/dev/admin/test-user/<user_id>/recycle-key', methods=['POST'])
@dev_admin_auth_required
def dev_admin_test_recycle_key(user_id):
    """Test recycle key operation for a test user"""
    test_user = dev_mode.get_test_user(user_id)

    if not test_user:
        return jsonify({"error": "Test user not found", "user_id": user_id}), 404

    dev_mode.audit_log(f"Test recycle key operation", f"user_id: {user_id}")

    try:
        new_api_key = portal_service.recycle_api_key(test_user)
        key_fingerprint = APIKey.get_fingerprint(new_api_key)

        return jsonify({
            "success": True,
            "api_key": new_api_key,
            "key_fingerprint": key_fingerprint,
            "message": "API key recycled successfully - previous key is now invalid",
            "user_id": user_id
        })

    except Exception as e:
        dev_mode.audit_log(f"Test recycle key failed", f"user_id: {user_id}, error: {str(e)}")
        return jsonify({"error": "Failed to recycle API key", "details": str(e)}), 500

@app.route('/dev/admin/reset-user/<user_id>', methods=['POST'])
@dev_admin_auth_required
def dev_admin_reset_user(user_id):
    """Reset user by deleting their Consumer (dangerous operation)"""
    test_user = dev_mode.get_test_user(user_id)

    if not test_user:
        return jsonify({"error": "Test user not found", "user_id": user_id}), 404

    dev_mode.audit_log(f"DANGEROUS: User reset operation", f"user_id: {user_id}")

    try:
        user_oid = test_user['user_oid']

        # Attempt to delete consumer
        response = portal_service.apisix._make_request('DELETE', f'consumers/{user_oid}')

        dev_mode.audit_log(f"User reset completed", f"user_id: {user_id}")

        return jsonify({
            "success": True,
            "message": f"User {user_id} reset successfully - Consumer and API key deleted",
            "user_id": user_id,
            "warning": "User will need to be recreated on next portal access"
        })

    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            return jsonify({
                "success": True,
                "message": f"User {user_id} was already reset - no Consumer found",
                "user_id": user_id
            })
        else:
            dev_mode.audit_log(f"User reset failed", f"user_id: {user_id}, error: {str(e)}")
            return jsonify({"error": "Failed to reset user", "details": str(e)}), 500

    except Exception as e:
        dev_mode.audit_log(f"User reset failed", f"user_id: {user_id}, error: {str(e)}")
        return jsonify({"error": "Failed to reset user", "details": str(e)}), 500

if __name__ == '__main__':
    # Development server - in production use proper WSGI server
    app.run(host='0.0.0.0', port=3000, debug=False)