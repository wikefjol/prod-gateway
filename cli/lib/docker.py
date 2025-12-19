"""
Docker operations and status checking

This module provides utilities for checking Docker container status,
specifically for detecting loader failures after start.sh completes.
"""
import subprocess
import json
from typing import Dict, List, Optional, Tuple
from rich.console import Console

console = Console()

def check_loader_status(env: str) -> Tuple[bool, Optional[str]]:
    """
    Check if loader container failed after startup

    Args:
        env: Environment (dev|test)

    Returns:
        Tuple of (success: bool, error_message: Optional[str])
    """
    project_name = f"apisix-{env}"
    loader_service = "loader"

    try:
        # Check container status using docker compose ps
        cmd = [
            "docker", "compose", "-p", project_name,
            "-f", "infrastructure/docker/base.yml",
            "-f", "infrastructure/docker/providers.yml",
            "ps", "--format", "json", loader_service
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode != 0:
            return False, f"Failed to check loader status: {result.stderr}"

        # Parse JSON output
        if not result.stdout.strip():
            return False, "Loader container not found"

        container_info = json.loads(result.stdout.strip())

        # Check container state
        state = container_info.get("State", "unknown")
        exit_code = container_info.get("ExitCode", 0)

        if state == "running":
            return True, None
        elif state == "exited" and exit_code == 0:
            return True, None  # Loader is expected to exit successfully
        else:
            # Container failed
            container_name = container_info.get("Name", "unknown")
            return False, f"Loader container failed (state: {state}, exit code: {exit_code}). Check logs: gw logs {env} loader"

    except json.JSONDecodeError as e:
        return False, f"Failed to parse container status: {e}"
    except Exception as e:
        return False, f"Unexpected error checking loader: {e}"

def get_container_logs(env: str, service: str, lines: int = 50) -> str:
    """
    Get logs for a specific service

    Args:
        env: Environment (dev|test)
        service: Service name
        lines: Number of lines to return

    Returns:
        Log output as string
    """
    project_name = f"apisix-{env}"

    cmd = [
        "docker", "compose", "-p", project_name,
        "-f", "infrastructure/docker/base.yml",
        "-f", "infrastructure/docker/providers.yml",
        "logs", "--tail", str(lines), service
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        return f"Failed to get logs: {e.stderr}"

def list_containers(env: str) -> List[Dict[str, str]]:
    """
    List all containers for an environment

    Args:
        env: Environment (dev|test)

    Returns:
        List of container info dicts
    """
    project_name = f"apisix-{env}"

    cmd = [
        "docker", "compose", "-p", project_name,
        "-f", "infrastructure/docker/base.yml",
        "-f", "infrastructure/docker/providers.yml",
        "ps", "--format", "json"
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )

        containers = []
        if result.stdout.strip():
            # Each line is a JSON object
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    containers.append(json.loads(line))

        return containers

    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        console.print(f"[red]Failed to list containers: {e}[/red]")
        return []

def is_container_healthy(env: str, service: str) -> bool:
    """
    Check if a container is healthy

    Args:
        env: Environment (dev|test)
        service: Service name

    Returns:
        True if healthy, False otherwise
    """
    containers = list_containers(env)
    for container in containers:
        if container.get("Service") == service:
            state = container.get("State", "")
            health = container.get("Health", "")

            # Container is healthy if running and health check passes
            return state == "running" and (health == "healthy" or health == "")

    return False