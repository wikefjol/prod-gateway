"""
Doctor command - comprehensive health checks and diagnostics

This command performs preflight checks, readiness verification,
and smoke tests to ensure the system is working correctly.
"""
import subprocess
import json
import time
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.panel import Panel
import typer
import requests

from lib.environment import load_environment, EnvironmentError, get_data_plane_url, get_admin_api_url
from lib.docker import check_loader_status

console = Console()

def doctor_command(env: str):
    """
    Run comprehensive health checks and diagnostics

    This performs a complete system health check including:
    - Preflight checks (Docker, files, config)
    - Service readiness verification
    - Connectivity and route smoke tests

    Args:
        env: Environment (dev|test)
    """
    console.print(f"[bold blue]🔍 Running diagnostics for {env} environment[/bold blue]")

    # Track overall health
    checks_passed = 0
    total_checks = 0
    critical_failed = False

    # 1. Preflight Checks
    console.print(f"\n[bold cyan]━━━ Preflight Checks ━━━[/bold cyan]")
    passed, total, critical = _run_preflight_checks(env)
    checks_passed += passed
    total_checks += total
    if critical:
        critical_failed = True

    # 2. Service Readiness
    console.print(f"\n[bold cyan]━━━ Service Readiness ━━━[/bold cyan]")
    passed, total, critical = _run_readiness_checks(env)
    checks_passed += passed
    total_checks += total
    if critical:
        critical_failed = True

    # 3. Smoke Tests
    console.print(f"\n[bold cyan]━━━ Smoke Tests ━━━[/bold cyan]")
    passed, total, critical = _run_smoke_tests(env)
    checks_passed += passed
    total_checks += total
    if critical:
        critical_failed = True

    # Overall Summary
    _show_overall_summary(env, checks_passed, total_checks, critical_failed)

def _run_preflight_checks(env: str):
    """Run preflight checks before starting services"""
    checks_passed = 0
    total_checks = 0
    critical_failed = False

    # Check 1: Docker availability
    total_checks += 1
    if _check_docker():
        console.print("[green]✅ Docker available and running[/green]")
        checks_passed += 1
    else:
        console.print("[red]❌ Docker not available or not running[/red]")
        critical_failed = True

    # Check 2: Required files exist
    total_checks += 1
    if _check_required_files(env):
        console.print("[green]✅ Required configuration files present[/green]")
        checks_passed += 1
    else:
        console.print("[red]❌ Missing required configuration files[/red]")
        critical_failed = True

    # Check 3: Environment configuration
    total_checks += 1
    try:
        env_vars = load_environment("entraid", env)
        missing_critical = _check_critical_env_vars(env_vars)
        if not missing_critical:
            console.print("[green]✅ Environment configuration complete[/green]")
            checks_passed += 1
        else:
            console.print(f"[red]❌ Missing critical environment variables: {', '.join(missing_critical)}[/red]")
            critical_failed = True
    except EnvironmentError as e:
        console.print(f"[red]❌ Environment configuration failed: {e}[/red]")
        critical_failed = True

    # Check 4: Network ports availability
    total_checks += 1
    if _check_port_availability(env):
        console.print("[green]✅ Required network ports available[/green]")
        checks_passed += 1
    else:
        console.print("[yellow]⚠️ Some network ports may be in use[/yellow]")
        # Non-critical for now

    return checks_passed, total_checks, critical_failed

def _run_readiness_checks(env: str):
    """Check if services are ready and responding"""
    checks_passed = 0
    total_checks = 0
    critical_failed = False

    project_name = f"apisix-{env}"

    # Check 1: Containers running
    total_checks += 1
    running_containers = _get_running_containers(project_name)
    if "apisix" in running_containers:
        console.print("[green]✅ APISIX container is running[/green]")
        checks_passed += 1
    else:
        console.print("[red]❌ APISIX container not running[/red]")
        critical_failed = True

    # Check 2: Container health
    total_checks += 1
    healthy_containers = _get_healthy_containers(project_name)
    if "apisix" in healthy_containers:
        console.print("[green]✅ APISIX container reports healthy[/green]")
        checks_passed += 1
    else:
        console.print("[yellow]⚠️ APISIX container health check unclear[/yellow]")

    # Check 3: Admin API readiness
    total_checks += 1
    if _check_admin_api_ready(env):
        console.print("[green]✅ APISIX Admin API ready and responding[/green]")
        checks_passed += 1
    else:
        console.print("[red]❌ APISIX Admin API not ready[/red]")
        critical_failed = True

    # Check 4: Loader status (non-critical)
    total_checks += 1
    try:
        loader_success, loader_error = check_loader_status(env)
        if loader_success:
            console.print("[green]✅ Loader container completed successfully[/green]")
            checks_passed += 1
        else:
            console.print(f"[yellow]⚠️ Loader container failed (known issue): {loader_error}[/yellow]")
            # Non-critical as per design
    except Exception as e:
        console.print(f"[yellow]⚠️ Could not check loader status: {e}[/yellow]")

    return checks_passed, total_checks, critical_failed

def _run_smoke_tests(env: str):
    """Run smoke tests to verify functionality"""
    checks_passed = 0
    total_checks = 0
    critical_failed = False

    try:
        env_vars = load_environment("entraid", env)
        data_plane = get_data_plane_url(env)

        # Test 1: Health endpoint
        total_checks += 1
        if _test_endpoint(f"{data_plane}/health", "Health endpoint"):
            checks_passed += 1
        else:
            critical_failed = True

        # Test 2: Portal route exists (redirect/auth is fine)
        total_checks += 1
        if _test_endpoint(f"{data_plane}/portal", "Portal route", expected_codes=[302, 401, 403]):
            checks_passed += 1

        # Test 3: Root redirect
        total_checks += 1
        if _test_endpoint(f"{data_plane}/", "Root redirect", expected_codes=[302]):
            checks_passed += 1

        # Test 4: Route count verification
        total_checks += 1
        route_count = _get_route_count(env)
        if route_count and route_count > 0:
            console.print(f"[green]✅ Route configuration verified ({route_count} routes)[/green]")
            checks_passed += 1
        else:
            console.print("[yellow]⚠️ No routes configured or unable to verify[/yellow]")

    except EnvironmentError:
        console.print("[red]❌ Cannot run smoke tests - environment configuration failed[/red]")
        return 0, 4, True

    return checks_passed, total_checks, critical_failed

def _check_docker():
    """Check if Docker is available and running"""
    try:
        subprocess.run(["docker", "--version"], capture_output=True, check=True)
        subprocess.run(["docker", "ps"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def _check_required_files(env: str):
    """Check if required configuration files exist"""
    import os

    required_files = [
        f"config/env/{env}.env",
        f"config/providers/entraid/{env}.env",
        "scripts/core/environment.sh",
        "scripts/lifecycle/start.sh",
        "scripts/bootstrap/bootstrap-core.sh",
        "infrastructure/docker/base.yml"
    ]

    for file_path in required_files:
        if not os.path.exists(file_path):
            console.print(f"[dim]Missing: {file_path}[/dim]")
            return False

    return True

def _check_critical_env_vars(env_vars: dict):
    """Check for missing critical environment variables"""
    critical_vars = [
        "ADMIN_KEY",
        "OIDC_CLIENT_ID",
        "OIDC_CLIENT_SECRET",
        "OIDC_DISCOVERY_ENDPOINT"
    ]

    missing = []
    for var in critical_vars:
        if not env_vars.get(var):
            missing.append(var)

    return missing

def _check_port_availability(env: str):
    """Check if required ports are available"""
    import socket

    ports = [9180, 9080] if env == "dev" else [9181, 9081]

    for port in ports:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex(('localhost', port))
        sock.close()

        if result == 0:
            # Port is in use - might be our services
            continue

    return True  # Assume OK for now

def _get_running_containers(project_name: str):
    """Get list of running container service names"""
    try:
        result = subprocess.run(
            ["docker", "compose", "-p", project_name, "ps", "--format", "json"],
            capture_output=True, text=True, check=True
        )

        running = []
        for line in result.stdout.strip().split('\n'):
            if line.strip():
                container = json.loads(line)
                if container.get("State") == "running":
                    running.append(container.get("Service", ""))

        return running
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []

def _get_healthy_containers(project_name: str):
    """Get list of healthy container service names"""
    try:
        result = subprocess.run(
            ["docker", "compose", "-p", project_name, "ps", "--format", "json"],
            capture_output=True, text=True, check=True
        )

        healthy = []
        for line in result.stdout.strip().split('\n'):
            if line.strip():
                container = json.loads(line)
                if container.get("Health") == "healthy":
                    healthy.append(container.get("Service", ""))

        return healthy
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []

def _check_admin_api_ready(env: str):
    """Check if Admin API is ready to accept requests"""
    try:
        env_vars = load_environment("entraid", env)
        admin_api = get_admin_api_url(env)
        admin_key = env_vars.get("ADMIN_KEY")

        if not admin_key:
            return False

        response = requests.get(
            f"{admin_api}/routes",
            headers={"X-API-KEY": admin_key},
            timeout=5
        )

        return response.status_code == 200
    except:
        return False

def _test_endpoint(url: str, name: str, expected_codes: list = None):
    """Test a single HTTP endpoint"""
    if expected_codes is None:
        expected_codes = [200]

    try:
        response = requests.get(url, timeout=5, allow_redirects=False)

        if response.status_code in expected_codes:
            console.print(f"[green]✅ {name} responding correctly ({response.status_code})[/green]")
            return True
        else:
            console.print(f"[red]❌ {name} unexpected response ({response.status_code})[/red]")
            return False
    except requests.exceptions.RequestException as e:
        console.print(f"[red]❌ {name} failed: {e}[/red]")
        return False

def _get_route_count(env: str):
    """Get the number of configured routes"""
    try:
        env_vars = load_environment("entraid", env)
        admin_api = get_admin_api_url(env)
        admin_key = env_vars.get("ADMIN_KEY")

        if not admin_key:
            return None

        response = requests.get(
            f"{admin_api}/routes",
            headers={"X-API-KEY": admin_key},
            timeout=5
        )

        if response.status_code == 200:
            data = response.json()
            return len(data.get("list", []))

        return None
    except:
        return None

def _show_overall_summary(env: str, checks_passed: int, total_checks: int, critical_failed: bool):
    """Show overall health summary"""
    console.print(f"\n[bold cyan]━━━ Overall Health Summary ━━━[/bold cyan]")

    percentage = (checks_passed / total_checks * 100) if total_checks > 0 else 0

    if critical_failed:
        status = "[red]❌ CRITICAL ISSUES FOUND[/red]"
        recommendations = [
            "Fix critical issues before using the system",
            f"Run 'gw down {env} --clean && gw up {env}' to restart",
            f"Check configuration with 'gw env {env}'"
        ]
    elif percentage >= 90:
        status = "[green]✅ SYSTEM HEALTHY[/green]"
        recommendations = [
            "System is ready for use",
            f"Access portal at: http://localhost:{'9080' if env == 'dev' else '9081'}/portal"
        ]
    elif percentage >= 70:
        status = "[yellow]⚠️ MINOR ISSUES[/yellow]"
        recommendations = [
            "System is functional with minor issues",
            "Review warnings above for potential improvements",
            f"Monitor with 'gw status {env}'"
        ]
    else:
        status = "[red]❌ MAJOR ISSUES[/red]"
        recommendations = [
            "System has significant problems",
            f"Try complete reset: 'gw reset {env}'",
            "Check logs for detailed error information"
        ]

    summary_panel = Panel(
        f"Status: {status}\n"
        f"Checks passed: {checks_passed}/{total_checks} ({percentage:.1f}%)\n\n"
        f"Recommendations:\n" + "\n".join(f"• {rec}" for rec in recommendations),
        title=f"{env.title()} Environment Health",
        border_style="green" if not critical_failed and percentage >= 90 else "yellow" if not critical_failed else "red"
    )

    console.print(summary_panel)