"""
Routes command - view and manage APISIX routes

This command provides visibility into configured routes and their status
for debugging and monitoring purposes.
"""
import json
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
import typer
import requests

from lib.environment import load_environment, EnvironmentError, get_admin_api_url

console = Console()

def routes_command(env: str, detailed: bool = False, route_id: str = None):
    """
    View configured APISIX routes

    This shows the currently configured routes in APISIX for debugging
    and verification purposes.

    Args:
        env: Environment (dev|test)
        detailed: Show detailed route information
        route_id: Show specific route details
    """
    console.print(f"[bold blue]Routes for {env} environment[/bold blue]")

    try:
        # Load environment configuration
        env_vars = load_environment("entraid", env)
        admin_api = get_admin_api_url(env)
        admin_key = env_vars.get("ADMIN_KEY")

        if not admin_key:
            console.print(f"[red]❌ Cannot connect to admin API - missing configuration[/red]")
            console.print(f"[cyan]   Run 'gw env {env}' to check configuration[/cyan]")
            raise typer.Exit(1)

        # Fetch routes from admin API
        response = requests.get(
            f"{admin_api}/routes",
            headers={"X-API-KEY": admin_key},
            timeout=10
        )

        if response.status_code != 200:
            console.print(f"[red]❌ Failed to fetch routes (HTTP {response.status_code})[/red]")
            console.print(f"[cyan]   Check admin API status: curl -H 'X-API-KEY: $ADMIN_KEY' {admin_api}/routes[/cyan]")
            raise typer.Exit(1)

        routes_data = response.json()
        routes = routes_data.get("list", [])

        if not routes:
            console.print(f"[yellow]⚠️ No routes configured in {env} environment[/yellow]")
            console.print(f"[cyan]   Run 'gw bootstrap {env}' to deploy routes[/cyan]")
            return

        # Show specific route if requested
        if route_id:
            _show_specific_route(routes, route_id)
            return

        # Show route summary
        _show_route_summary(routes, detailed)

        # Show helpful next steps
        console.print(f"\n[cyan]💡 Commands:[/cyan]")
        console.print(f"[cyan]   Detailed view: gw routes {env} --detailed[/cyan]")
        console.print(f"[cyan]   Specific route: gw routes {env} --route-id <route-id>[/cyan]")
        console.print(f"[cyan]   Test endpoints: curl http://localhost:{'9080' if env == 'dev' else '9081'}/<path>[/cyan]")

    except EnvironmentError as e:
        console.print(f"[red]❌ Environment configuration failed:[/red]")
        console.print(f"[red]{e}[/red]")
        console.print(f"[cyan]   Check environment: gw env {env}[/cyan]")
        raise typer.Exit(1)

    except requests.exceptions.RequestException as e:
        console.print(f"[red]❌ Failed to connect to APISIX admin API:[/red]")
        console.print(f"[red]{e}[/red]")
        console.print(f"[cyan]   Check if APISIX is running: gw status {env}[/cyan]")
        raise typer.Exit(1)

def _show_route_summary(routes: list, detailed: bool):
    """Show summary table of all routes"""
    console.print(f"[green]✅ {len(routes)} routes configured[/green]\n")

    # Create summary table
    table = Table(title="Route Summary")
    table.add_column("Route ID", style="cyan", no_wrap=True)
    table.add_column("URI", style="green")
    table.add_column("Methods", style="blue")

    if detailed:
        table.add_column("Upstream", style="yellow")
        table.add_column("Plugins", style="magenta")

    for route in routes:
        # Handle APISIX API structure where route data is nested under "value"
        route_data = route.get("value", route)
        route_id = str(route_data.get("id", "unknown"))
        uri = route_data.get("uri", "N/A")
        methods = ", ".join(route_data.get("methods", ["ANY"]))

        if detailed:
            # Extract upstream info
            upstream = route_data.get("upstream", {})
            if upstream:
                upstream_nodes = upstream.get("nodes", {})
                if upstream_nodes:
                    upstream_str = ", ".join([f"{host}:{port}" for host, port in upstream_nodes.items()])
                else:
                    upstream_str = "No nodes"
            else:
                upstream_str = "N/A"

            # Extract plugin info
            plugins = route_data.get("plugins", {})
            if plugins:
                plugin_list = ", ".join(plugins.keys())
            else:
                plugin_list = "None"

            table.add_row(route_id, uri, methods, upstream_str, plugin_list)
        else:
            table.add_row(route_id, uri, methods)

    console.print(table)

def _show_specific_route(routes: list, route_id: str):
    """Show detailed information for a specific route"""
    # Find the requested route
    target_route = None
    for route in routes:
        # Handle APISIX API structure where route data is nested under "value"
        route_data = route.get("value", route)
        if str(route_data.get("id")) == route_id:
            target_route = route_data
            break

    if not target_route:
        console.print(f"[red]❌ Route '{route_id}' not found[/red]")
        available_routes = [str(r.get("value", r).get('id', 'unknown')) for r in routes]
        console.print(f"[cyan]Available routes: {', '.join(available_routes)}[/cyan]")
        return

    # Display detailed route information
    console.print(f"[bold cyan]Route Details: {route_id}[/bold cyan]\n")

    # Basic info panel
    basic_info = []
    basic_info.append(f"ID: {target_route.get('id', 'N/A')}")
    basic_info.append(f"URI: {target_route.get('uri', 'N/A')}")
    basic_info.append(f"Methods: {', '.join(target_route.get('methods', ['ANY']))}")
    basic_info.append(f"Status: {'Enabled' if target_route.get('status', 1) == 1 else 'Disabled'}")

    console.print(Panel(
        "\n".join(basic_info),
        title="Basic Information",
        border_style="blue"
    ))

    # Upstream configuration
    upstream = target_route.get("upstream", {})
    if upstream:
        upstream_info = []
        upstream_info.append(f"Type: {upstream.get('type', 'roundrobin')}")

        nodes = upstream.get("nodes", {})
        if nodes:
            upstream_info.append("Nodes:")
            for host, port in nodes.items():
                upstream_info.append(f"  - {host}:{port}")

        hash_on = upstream.get("hash_on", "vars")
        if hash_on != "vars":
            upstream_info.append(f"Hash on: {hash_on}")

        console.print(Panel(
            "\n".join(upstream_info),
            title="Upstream Configuration",
            border_style="yellow"
        ))

    # Plugins configuration
    plugins = target_route.get("plugins", {})
    if plugins:
        plugins_info = []
        for plugin_name, plugin_config in plugins.items():
            plugins_info.append(f"[cyan]{plugin_name}[/cyan]:")

            # Show key configuration details
            if isinstance(plugin_config, dict):
                for key, value in plugin_config.items():
                    if key in ["disable", "priority"]:
                        continue
                    if isinstance(value, (str, int, bool)):
                        plugins_info.append(f"  {key}: {value}")
                    elif isinstance(value, dict):
                        plugins_info.append(f"  {key}: [complex object]")
                    elif isinstance(value, list):
                        plugins_info.append(f"  {key}: [array with {len(value)} items]")

        console.print(Panel(
            "\n".join(plugins_info),
            title="Plugins Configuration",
            border_style="magenta"
        ))

    # Raw JSON (for debugging)
    if console.options.legacy_windows:
        # Fallback for environments that don't support rich JSON
        console.print("\n[bold]Raw JSON:[/bold]")
        console.print(json.dumps(target_route, indent=2))
    else:
        from rich.syntax import Syntax
        console.print("\n[bold]Raw JSON:[/bold]")
        json_str = json.dumps(target_route, indent=2)
        syntax = Syntax(json_str, "json", theme="monokai", line_numbers=True)
        console.print(syntax)