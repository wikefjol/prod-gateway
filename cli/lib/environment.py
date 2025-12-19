"""
Environment variable loading with robust error handling

This module loads environment variables by calling the existing environment.sh
script while handling stdout pollution and preserving stderr for debugging.
"""
import subprocess
from pathlib import Path
from typing import Dict

class EnvironmentError(Exception):
    """Environment loading failed"""
    pass

def load_environment(provider: str, env: str) -> Dict[str, str]:
    """
    Load environment by calling existing bash setup

    Args:
        provider: OIDC provider (currently hardcoded to 'entraid')
        env: Environment (dev|test)

    Returns:
        Dict of environment variables

    Raises:
        EnvironmentError: If environment setup fails
    """
    # Ensure we're in project root
    project_root = Path.cwd()
    env_script = project_root / "scripts/core/environment.sh"

    if not env_script.exists():
        raise EnvironmentError(f"Environment script not found: {env_script}")

    # Build command that silences stdout (to avoid pollution) but preserves stderr
    cmd = [
        'bash', '-lc',
        f'source scripts/core/environment.sh; '
        f'setup_environment {provider} {env} >/dev/null; '  # stdout to null
        f'env -0'  # null-separated output
    ]

    # Run with check=False so we can handle errors ourselves
    result = subprocess.run(
        cmd,
        capture_output=True,
        check=False,
        cwd=project_root
    )

    # Handle non-zero exit code with helpful error message
    if result.returncode != 0:
        stderr_msg = result.stderr.decode() if result.stderr else "No error output"
        raise EnvironmentError(
            f"Environment setup failed (exit code {result.returncode}):\n"
            f"Command: {' '.join(cmd)}\n"
            f"Error output:\n{stderr_msg}"
        )

    # Validate we have null-separated output (not corrupted by stdout pollution)
    if b'\0' not in result.stdout:
        stdout_preview = result.stdout.decode()[:200]
        raise EnvironmentError(
            "Environment setup didn't produce null-separated output. "
            "This indicates stdout pollution from environment.sh.\n"
            f"Got: {stdout_preview}..."
        )

    # Parse null-separated environment variables
    env_vars = {}
    for line in result.stdout.split(b'\0'):
        if line and b'=' in line:
            try:
                key, value = line.decode().split('=', 1)
                env_vars[key] = value
            except (UnicodeDecodeError, ValueError):
                # Skip unparseable lines
                continue

    # Validate we got expected core variables
    required_vars = ['ENVIRONMENT', 'APISIX_ADMIN_API', 'ADMIN_KEY']
    missing_vars = [var for var in required_vars if var not in env_vars]

    if missing_vars:
        raise EnvironmentError(
            f"Environment setup missing required variables: {missing_vars}\n"
            f"Got {len(env_vars)} variables total"
        )

    return env_vars

def get_project_name(env: str) -> str:
    """Get Docker Compose project name for environment"""
    return f"apisix-{env}"

def get_admin_api_url(env: str) -> str:
    """Get Admin API URL for environment"""
    port = "9181" if env == "test" else "9180"
    return f"http://localhost:{port}/apisix/admin"

def get_data_plane_url(env: str) -> str:
    """Get data plane URL for environment"""
    port = "9081" if env == "test" else "9080"
    return f"http://localhost:{port}"