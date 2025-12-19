"""
Up command - thin wrapper around scripts/lifecycle/start.sh

This command starts the environment infrastructure using existing scripts
rather than reimplementing Docker Compose logic.
"""
import subprocess
from rich.console import Console

from lib.docker import check_loader_status

console = Console()

def up_command(env: str, debug: bool = False):
    """
    Start environment infrastructure

    This is a thin wrapper around the existing start.sh script to avoid
    duplicating the Docker Compose logic that already knows which files,
    profiles, and environment variables to use.

    Args:
        env: Environment (dev|test)
        debug: Enable debug mode
    """
    console.print(f"[bold blue]Starting {env} environment...[/bold blue]")

    # Build command for existing start script
    cmd = [
        "./scripts/lifecycle/start.sh",
        "--provider", "entraid",  # Currently hardcoded
        "--environment", env
    ]

    if debug:
        cmd.append("--debug")

    try:
        # Execute start script
        console.print(f"[dim]Executing: {' '.join(cmd)}[/dim]")

        result = subprocess.run(
            cmd,
            check=True,
            text=True
        )

        console.print(f"[green]✅ {env.title()} environment started successfully[/green]")

        # Check loader status (visible but non-fatal)
        _check_and_warn_loader_status(env)

    except subprocess.CalledProcessError as e:
        console.print(f"[red]❌ Failed to start {env} environment[/red]")
        console.print(f"[red]Exit code: {e.returncode}[/red]")
        if e.stderr:
            console.print(f"[red]Error: {e.stderr}[/red]")
        raise

    except KeyboardInterrupt:
        console.print(f"\n[yellow]⚠️ Startup cancelled for {env} environment[/yellow]")
        raise

def _check_and_warn_loader_status(env: str):
    """
    Check loader status and warn if failed, but don't fail the command

    This implements the "visible but non-fatal" approach for loader failures.
    """
    try:
        success, error_msg = check_loader_status(env)

        if not success and error_msg:
            console.print(f"[yellow]⚠️ Loader container failed (this is a known issue)[/yellow]")
            console.print(f"[dim]   {error_msg}[/dim]")
            console.print(f"[cyan]   💡 This doesn't prevent core functionality. Use 'gw bootstrap {env}' for reliable route setup.[/cyan]")

    except Exception as e:
        # Don't fail the entire up command due to loader check issues
        console.print(f"[yellow]⚠️ Could not check loader status: {e}[/yellow]")
        console.print(f"[cyan]   💡 Use 'gw bootstrap {env}' to ensure routes are configured.[/cyan]")