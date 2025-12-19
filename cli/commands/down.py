"""
Down command - safe environment shutdown with optional global cleanup

This command stops environments using existing scripts while implementing
safe cleanup defaults (project-only) and explicit opt-in for global pruning.
"""
import subprocess
from rich.console import Console
import typer

console = Console()

def down_command(env: str, clean: bool = False, prune_global: bool = False, i_know_what_im_doing: bool = False):
    """
    Stop environment with safe cleanup options

    Args:
        env: Environment (dev|test)
        clean: Remove volumes and networks (project-only)
        prune_global: DANGER - Prune ALL containers/networks
        i_know_what_im_doing: Skip safety prompt for global prune
    """
    console.print(f"[bold blue]Stopping {env} environment...[/bold blue]")

    # Handle global prune safety
    if prune_global and not i_know_what_im_doing:
        console.print("[red]⚠️ WARNING: Global prune will delete ALL stopped containers and unused networks on this machine![/red]")
        console.print("[dim]This may affect containers from other projects.[/dim]")

        if not typer.confirm("Are you sure you want to proceed?"):
            console.print("[yellow]Operation cancelled[/yellow]")
            raise typer.Exit(0)

    # Build command for existing stop script
    cmd = [
        "./scripts/lifecycle/stop.sh",
        "--environment", env
    ]

    if clean:
        cmd.append("--clean")

    try:
        # Execute stop script (project-only cleanup)
        console.print(f"[dim]Executing: {' '.join(cmd)}[/dim]")

        subprocess.run(
            cmd,
            check=True,
            text=True
        )

        console.print(f"[green]✅ {env.title()} environment stopped[/green]")

        # Handle global prune separately if requested
        if prune_global:
            _perform_global_prune()

    except subprocess.CalledProcessError as e:
        console.print(f"[red]❌ Failed to stop {env} environment[/red]")
        console.print(f"[red]Exit code: {e.returncode}[/red]")
        if e.stderr:
            console.print(f"[red]Error: {e.stderr}[/red]")
        raise

    except KeyboardInterrupt:
        console.print(f"\n[yellow]⚠️ Shutdown cancelled for {env} environment[/yellow]")
        raise

def _perform_global_prune():
    """
    Perform global Docker cleanup with explicit warning

    This is separated from the main stop logic to make it very explicit
    that this affects the entire Docker system, not just our project.
    """
    console.print("[red]🧹 Performing GLOBAL Docker cleanup...[/red]")

    try:
        # Prune stopped containers
        console.print("[dim]Pruning stopped containers...[/dim]")
        subprocess.run(
            ["docker", "container", "prune", "-f"],
            check=True,
            capture_output=True
        )

        # Prune unused networks
        console.print("[dim]Pruning unused networks...[/dim]")
        subprocess.run(
            ["docker", "network", "prune", "-f"],
            check=True,
            capture_output=True
        )

        console.print("[green]✅ Global cleanup completed[/green]")

    except subprocess.CalledProcessError as e:
        console.print(f"[red]❌ Global cleanup failed: {e.stderr.decode() if e.stderr else 'Unknown error'}[/red]")
        # Don't raise - this is additional cleanup, not critical