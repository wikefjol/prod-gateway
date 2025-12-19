"""
Status command - show system and container status

This command provides a comprehensive overview of the system state,
including container status, service health, and route configuration.
"""
import subprocess
import json
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
import typer
import requests

from lib.environment import load_environment, EnvironmentError, get_data_plane_url, get_admin_api_url

console = Console()

def status_command(env: str = None):
    """
    Show system status and health

    This displays container status, service health, and basic
    connectivity tests for debugging and monitoring.

    Args:
        env: Environment (dev|test) - if not provided, shows both
    """
    if env:
        console.print(f"[bold blue]System Status for {env} environment[/bold blue]")
        _show_env_status(env)
    else:
        console.print(f"[bold blue]System Status (All Environments)[/bold blue]")
        console.print(f"[dim]Showing status for both dev and test environments[/dim]\n")

        for env_name in ["dev", "test"]:
            console.print(f"[bold cyan]━━━ {env_name.title()} Environment ━━━[/bold cyan]")
            _show_env_status(env_name)
            console.print()

def _show_env_status(env: str):
    """Show status for a specific environment"""
    project_name = f"apisix-{env}"

    # 1. Container Status
    console.print(f"[bold]Container Status ({project_name})[/bold]")
    _show_container_status(project_name)

    # 2. Service Health
    console.print(f"\n[bold]Service Health[/bold]")
    _show_service_health(env)

    # 3. Route Summary
    console.print(f"\n[bold]Route Summary[/bold]")
    _show_route_summary(env)

def _show_container_status(project_name: str):
    """Show Docker container status for the project"""
    try:
        # Get container status using docker compose ps
        result = subprocess.run(
            ["docker", "compose", "-p", project_name, "ps", "--format", "json"],
            capture_output=True,
            text=True,
            check=True
        )

        if not result.stdout.strip():
            console.print("[yellow]No containers found for this environment[/yellow]")
            return

        # Parse container information
        containers = []
        for line in result.stdout.strip().split('\n'):
            if line.strip():
                containers.append(json.loads(line))

        # Create table
        table = Table()
        table.add_column("Service", style="cyan")
        table.add_column("Status", style="green")
        table.add_column("Health", style="blue")
        table.add_column("Ports", style="dim")

        for container in containers:
            service = container.get("Service", "Unknown")
            state = container.get("State", "unknown")

            # Color code the status
            if state == "running":
                status = "[green]running[/green]"
            elif state == "exited":
                status = "[red]exited[/red]"
            else:
                status = f"[yellow]{state}[/yellow]"

            health = container.get("Health", "N/A")
            if health == "healthy":
                health = "[green]healthy[/green]"
            elif health == "unhealthy":
                health = "[red]unhealthy[/red]"
            elif health == "starting":
                health = "[yellow]starting[/yellow]"

            ports = container.get("Publishers", "")
            if isinstance(ports, list) and ports:
                # Format ports nicely
                port_str = ", ".join([
                    f"{p.get('TargetPort', '?')}:{p.get('PublishedPort', '?')}"
                    for p in ports
                ])
            else:
                port_str = "None"

            table.add_row(service, status, health, port_str)

        console.print(table)

    except subprocess.CalledProcessError as e:
        console.print(f"[red]Failed to get container status: {e}[/red]")
    except json.JSONDecodeError:
        console.print(f"[red]Failed to parse container status[/red]")

def _show_service_health(env: str):
    """Check service health via HTTP endpoints"""
    try:
        # Load environment to get URLs
        env_vars = load_environment("entraid", env)
        admin_api = get_admin_api_url(env)
        data_plane = get_data_plane_url(env)
        admin_key = env_vars.get("ADMIN_KEY")

        # Health checks
        health_table = Table()
        health_table.add_column("Endpoint", style="cyan")
        health_table.add_column("Status", style="green")
        health_table.add_column("Response Time", style="dim")

        # Check Admin API
        if admin_api and admin_key:
            status, response_time = _check_endpoint(
                f"{admin_api}/routes",
                headers={"X-API-KEY": admin_key}
            )
            health_table.add_row("Admin API", status, response_time)

        # Check Data Plane
        if data_plane:
            # Check basic connectivity
            status, response_time = _check_endpoint(f"{data_plane}/health")
            health_table.add_row("Data Plane (/health)", status, response_time)

            # Check portal endpoint
            status, response_time = _check_endpoint(
                f"{data_plane}/portal",
                expected_codes=[302, 401, 403]  # Redirect or auth is fine
            )
            health_table.add_row("Portal Route", status, response_time)

        console.print(health_table)

    except EnvironmentError:
        console.print("[yellow]Could not load environment for health checks[/yellow]")

def _check_endpoint(url: str, headers: dict = None, expected_codes: list = None):
    """Check a single HTTP endpoint and return status and timing"""
    if expected_codes is None:
        expected_codes = [200]

    try:
        import time
        start_time = time.time()

        response = requests.get(url, headers=headers, timeout=5, allow_redirects=False)
        response_time = f"{(time.time() - start_time) * 1000:.0f}ms"

        if response.status_code in expected_codes:
            return "[green]✅ OK[/green]", response_time
        else:
            return f"[yellow]⚠️ {response.status_code}[/yellow]", response_time

    except requests.exceptions.ConnectingError:
        return "[red]❌ Connection failed[/red]", "N/A"
    except requests.exceptions.Timeout:
        return "[red]❌ Timeout[/red]", ">5s"
    except requests.exceptions.RequestException as e:
        return f"[red]❌ {type(e).__name__}[/red]", "N/A"

def _show_route_summary(env: str):
    """Show summary of configured routes"""
    try:
        # Load environment
        env_vars = load_environment("entraid", env)
        admin_api = get_admin_api_url(env)
        admin_key = env_vars.get("ADMIN_KEY")

        if not admin_key:
            console.print("[yellow]Cannot check routes - missing admin API configuration[/yellow]")
            return

        # Get routes from admin API
        response = requests.get(
            f"{admin_api}/routes",
            headers={"X-API-KEY": admin_key},
            timeout=5
        )

        if response.status_code == 200:
            routes_data = response.json()
            routes = routes_data.get("list", [])

            if routes:
                console.print(f"[green]✅ {len(routes)} routes configured[/green]")

                # Show route IDs - handle APISIX API structure
                route_ids = [route.get("value", route).get("id", "unknown") for route in routes]
                console.print(f"[dim]Routes: {', '.join(route_ids)}[/dim]")
            else:
                console.print("[yellow]⚠️ No routes configured[/yellow]")
        else:
            console.print(f"[red]❌ Failed to fetch routes (HTTP {response.status_code})[/red]")

    except requests.exceptions.RequestException as e:
        console.print(f"[yellow]⚠️ Could not check routes: {e}[/yellow]")
    except EnvironmentError:
        console.print("[yellow]Could not load environment for route check[/yellow]")