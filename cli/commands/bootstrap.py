"""
Bootstrap command - reliable route deployment via bootstrap-core.sh

This command uses the proven bootstrap-core.sh approach that works reliably
with explicit environment targeting and graceful provider key handling.
"""
import subprocess
from rich.console import Console

from lib.environment import load_environment, EnvironmentError

console = Console()

def bootstrap_command(env: str, core_only: bool = True):
    """
    Bootstrap routes using proven bootstrap-core.sh

    This uses the canonical bootstrap approach that:
    - Uses explicit environment targeting (dev|test)
    - Runs from host (localhost:9180/9181)
    - Deploys core routes first, provider routes optionally
    - Handles missing API keys gracefully

    Args:
        env: Environment (dev|test)
        core_only: Deploy only core routes (default) or include provider routes
    """
    console.print(f"[bold blue]Bootstrapping {env} environment routes...[/bold blue]")

    try:
        # Load environment to ensure configuration is valid
        console.print("[dim]Loading environment configuration...[/dim]")
        env_vars = load_environment("entraid", env)

        # Verify APISIX Admin API is reachable before bootstrap
        admin_api = env_vars.get("APISIX_ADMIN_API")
        admin_key = env_vars.get("ADMIN_KEY")

        if not admin_api or not admin_key:
            raise EnvironmentError("Missing APISIX_ADMIN_API or ADMIN_KEY")

        console.print(f"[dim]Admin API: {admin_api}[/dim]")

        # Use the proven bootstrap-core.sh approach
        cmd = ["./scripts/bootstrap/bootstrap-core.sh", env]

        console.print(f"[dim]Executing: {' '.join(cmd)}[/dim]")

        # Set environment for the bootstrap script
        bootstrap_env = subprocess.os.environ.copy()
        bootstrap_env.update(env_vars)

        result = subprocess.run(
            cmd,
            check=True,
            env=bootstrap_env,
            text=True,
            capture_output=True
        )

        # Parse output to show what was deployed
        _parse_bootstrap_output(result.stdout, env, core_only)

        console.print(f"[green]✅ Bootstrap completed for {env} environment[/green]")

    except EnvironmentError as e:
        console.print(f"[red]❌ Environment configuration failed:[/red]")
        console.print(f"[red]{e}[/red]")
        raise typer.Exit(1)

    except subprocess.CalledProcessError as e:
        console.print(f"[red]❌ Bootstrap failed for {env} environment[/red]")
        console.print(f"[red]Exit code: {e.returncode}[/red]")

        # Show helpful error output
        if e.stdout:
            console.print("[yellow]Output:[/yellow]")
            console.print(e.stdout)
        if e.stderr:
            console.print("[red]Error:[/red]")
            console.print(e.stderr)

        console.print(f"\n[cyan]💡 Troubleshooting tips:[/cyan]")
        console.print(f"[cyan]   1. Check APISIX is running: gw status {env}[/cyan]")
        console.print(f"[cyan]   2. Verify admin API access: curl -H 'X-API-KEY: $ADMIN_KEY' http://localhost:{'9181' if env == 'test' else '9180'}/apisix/admin/routes[/cyan]")
        console.print(f"[cyan]   3. Check environment config: gw env {env}[/cyan]")

        raise typer.Exit(1)

    except KeyboardInterrupt:
        console.print(f"\n[yellow]⚠️ Bootstrap cancelled for {env} environment[/yellow]")
        raise typer.Exit(1)

def _parse_bootstrap_output(output: str, env: str, core_only: bool):
    """
    Parse bootstrap-core.sh output to show what was deployed

    This provides user feedback about which routes were successfully deployed
    and which provider routes were skipped due to missing API keys.
    """
    lines = output.split('\n')

    core_routes = []
    provider_routes = []
    failed_routes = []

    for line in lines:
        if "✅ Route deployed:" in line:
            route_id = line.split("✅ Route deployed:")[-1].strip()
            if any(core in route_id for core in ["health", "portal", "oidc", "root"]):
                core_routes.append(route_id)
            else:
                provider_routes.append(route_id)

        elif "❌ Failed to deploy" in line:
            route_id = line.split("❌ Failed to deploy")[-1].split("(")[0].strip()
            failed_routes.append(route_id)

        elif "Provider API keys not available" in line:
            console.print("[yellow]⚠️ Provider routes skipped (API keys not available)[/yellow]")

    # Show deployment summary
    if core_routes:
        console.print(f"[green]Core routes deployed:[/green] {', '.join(core_routes)}")

    if provider_routes:
        console.print(f"[blue]Provider routes deployed:[/blue] {', '.join(provider_routes)}")

    if failed_routes:
        console.print(f"[red]Failed routes:[/red] {', '.join(failed_routes)}")

    # Helpful next steps
    data_plane_url = f"http://localhost:{'9081' if env == 'test' else '9080'}"
    console.print(f"\n[cyan]💡 Test deployment:[/cyan]")
    console.print(f"[cyan]   Health check: curl {data_plane_url}/health[/cyan]")
    console.print(f"[cyan]   Portal access: {data_plane_url}/portal[/cyan]")

import typer  # Import needed for typer.Exit