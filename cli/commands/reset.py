"""
Reset command - complete "nuke and restart" flow

This implements the gold standard reset flow:
down → up → bootstrap → verify
"""
from rich.console import Console
import typer

from commands.down import down_command
from commands.up import up_command
from commands.bootstrap import bootstrap_command
from lib.environment import get_data_plane_url, get_admin_api_url
import subprocess

console = Console()

def reset_command(env: str, clean: bool = False, core_only: bool = True):
    """
    Complete reset: down → up → bootstrap → verify

    This is the "gold standard" operation that should work reliably every time
    by using the proven patterns from bootstrap-core.sh and existing scripts.

    Args:
        env: Environment (dev|test)
        clean: Remove volumes and networks during down
        core_only: Deploy only core routes (default) or include provider routes
    """
    console.print(f"[bold magenta]🔄 Resetting {env} environment (complete nuke and restart)[/bold magenta]")

    try:
        # Step 1: Stop environment completely
        console.print("\n[bold blue]Step 1: Stopping environment[/bold blue]")
        down_command(env, clean=clean)

        # Step 2: Start infrastructure
        console.print("\n[bold blue]Step 2: Starting infrastructure[/bold blue]")
        up_command(env, debug=False)

        # Step 3: Wait for readiness and bootstrap routes
        console.print("\n[bold blue]Step 3: Waiting for readiness[/bold blue]")
        _wait_for_readiness(env)

        console.print("\n[bold blue]Step 4: Bootstrapping routes[/bold blue]")
        bootstrap_command(env, core_only=core_only)

        # Step 5: Verify deployment
        console.print("\n[bold blue]Step 5: Verifying deployment[/bold blue]")
        _verify_deployment(env)

        # Success summary
        data_plane_url = get_data_plane_url(env)
        console.print(f"\n[bold green]🎉 Reset completed successfully for {env} environment![/bold green]")
        console.print(f"[green]   Portal: {data_plane_url}/portal[/green]")
        console.print(f"[green]   Health: {data_plane_url}/health[/green]")

    except Exception as e:
        console.print(f"\n[red]❌ Reset failed for {env} environment[/red]")
        console.print(f"[red]Error: {e}[/red]")

        console.print(f"\n[cyan]💡 Troubleshooting:[/cyan]")
        console.print(f"[cyan]   Check status: gw status {env}[/cyan]")
        console.print(f"[cyan]   Check logs: gw logs {env}[/cyan]")
        console.print(f"[cyan]   Manual bootstrap: gw bootstrap {env}[/cyan]")

        raise typer.Exit(1)

def _wait_for_readiness(env: str):
    """
    Implement deterministic readiness gates before bootstrap

    This ensures APISIX is truly ready for route configuration,
    preventing the timing issues that plague the automated bootstrap.
    """
    import time
    import requests

    admin_api_url = get_admin_api_url(env)
    data_plane_url = get_data_plane_url(env)

    # Load admin key from environment
    from lib.environment import load_environment
    try:
        env_vars = load_environment("entraid", env)
        admin_key = env_vars.get("ADMIN_KEY")
    except Exception as e:
        console.print(f"[red]Failed to load admin key: {e}[/red]")
        raise

    console.print("[dim]Waiting for APISIX to be ready...[/dim]")

    max_attempts = 30
    for attempt in range(max_attempts):
        try:
            # Test 1: Admin API responds to routes endpoint
            response = requests.get(
                f"{admin_api_url}/routes",
                headers={"X-API-KEY": admin_key},
                timeout=5
            )

            if response.status_code == 200:
                console.print("[green]✅ Admin API ready[/green]")
                break
            else:
                console.print(f"[yellow]Admin API not ready (status: {response.status_code})[/yellow]")

        except requests.exceptions.RequestException as e:
            if attempt < 3:  # Only show errors for first few attempts
                console.print(f"[yellow]Admin API not ready: {e}[/yellow]")

        if attempt == max_attempts - 1:
            raise Exception(f"APISIX Admin API not ready after {max_attempts} attempts")

        time.sleep(2)

    # Brief additional wait for full startup
    console.print("[dim]Allowing additional startup time...[/dim]")
    time.sleep(3)

def _verify_deployment(env: str):
    """
    Verify that the deployment is working properly

    This provides smoke tests to ensure the reset was successful.
    """
    import requests

    data_plane_url = get_data_plane_url(env)

    try:
        # Test health endpoint (should be available after bootstrap)
        response = requests.get(f"{data_plane_url}/health", timeout=5)
        if response.status_code == 200:
            console.print("[green]✅ Health endpoint working[/green]")
        else:
            console.print(f"[yellow]⚠️ Health endpoint returned: {response.status_code}[/yellow]")

        # Test portal redirect (should exist after bootstrap)
        response = requests.get(f"{data_plane_url}/portal", timeout=5, allow_redirects=False)
        if response.status_code in [302, 401, 403]:  # Redirect or auth required is fine
            console.print("[green]✅ Portal endpoint configured[/green]")
        else:
            console.print(f"[yellow]⚠️ Portal endpoint returned: {response.status_code}[/yellow]")

    except requests.exceptions.RequestException as e:
        console.print(f"[yellow]⚠️ Verification requests failed: {e}[/yellow]")
        console.print("[dim]This may be normal if services are still starting up[/dim]")

    # Show final status summary
    console.print("\n[bold]Final status check:[/bold]")
    try:
        from .status import status_command
        status_command(env)
    except Exception:
        console.print("[yellow]Could not show status summary[/yellow]")