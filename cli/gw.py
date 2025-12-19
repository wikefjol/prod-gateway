#!/usr/bin/env python3
"""
APISIX Gateway CLI - Unified interface for reliable gateway operations

This CLI treats bootstrap-core.sh as canonical and orchestrates existing
scripts rather than reimplementing Docker Compose logic.
"""
import os
import sys
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

# Add directories to path for imports
cli_dir = Path(__file__).parent
sys.path.insert(0, str(cli_dir / "lib"))
sys.path.insert(0, str(cli_dir))

from lib.environment import load_environment, EnvironmentError
from lib.docker import check_loader_status
from commands.up import up_command
from commands.down import down_command
from commands.reset import reset_command
from commands.bootstrap import bootstrap_command
from commands.status import status_command
from commands.env import env_command
from commands.doctor import doctor_command
from commands.logs import logs_command
from commands.routes import routes_command

# Initialize CLI app and console
app = typer.Typer(
    name="gw",
    help="APISIX Gateway CLI - Reliable gateway operations",
    rich_markup_mode="rich"
)

console = Console()

# Valid environments (explicit, no defaults for destructive commands)
VALID_ENVS = ["dev", "test"]

def validate_env(env: str) -> str:
    """Validate environment parameter"""
    if env not in VALID_ENVS:
        console.print(f"[red]❌ Invalid environment: {env}[/red]")
        console.print(f"Valid environments: {', '.join(VALID_ENVS)}")
        raise typer.Exit(1)
    return env

@app.command()
def up(
    env: str = typer.Argument(..., help="Environment (dev|test)"),
    debug: bool = typer.Option(False, "--debug", help="Enable debug mode"),
):
    """Start environment infrastructure"""
    env = validate_env(env)
    up_command(env, debug)

@app.command()
def down(
    env: str = typer.Argument(..., help="Environment (dev|test)"),
    clean: bool = typer.Option(False, "--clean", help="Remove volumes and networks"),
    prune_global: bool = typer.Option(False, "--prune-global", help="⚠️ DANGER: Prune ALL containers/networks"),
    i_know_what_im_doing: bool = typer.Option(False, "--i-know-what-im-doing", help="Skip safety prompt for global prune"),
):
    """Stop environment"""
    env = validate_env(env)
    down_command(env, clean, prune_global, i_know_what_im_doing)

@app.command()
def reset(
    env: str = typer.Argument(..., help="Environment (dev|test)"),
    clean: bool = typer.Option(False, "--clean", help="Remove volumes and networks"),
    core_only: bool = typer.Option(True, "--core-only/--with-providers", help="Deploy only core routes (default) or include provider routes"),
):
    """Complete reset: down → up → bootstrap → verify"""
    env = validate_env(env)
    reset_command(env, clean, core_only)

@app.command()
def bootstrap(
    env: str = typer.Argument(..., help="Environment (dev|test)"),
    core_only: bool = typer.Option(True, "--core-only/--with-providers", help="Deploy only core routes (default) or include provider routes"),
):
    """Bootstrap routes using proven bootstrap-core.sh"""
    env = validate_env(env)
    bootstrap_command(env, core_only)

@app.command()
def status(
    env: Optional[str] = typer.Argument(None, help="Environment (dev|test) or show both")
):
    """Show environment status"""
    if env is not None:
        env = validate_env(env)
    status_command(env)

@app.command()
def env(
    env: str = typer.Argument(..., help="Environment (dev|test)")
):
    """Show derived environment variables"""
    env = validate_env(env)
    env_command(env)

@app.command()
def doctor(
    env: str = typer.Argument(..., help="Environment (dev|test)")
):
    """Run health checks and diagnostics"""
    env = validate_env(env)
    doctor_command(env)

@app.command()
def logs(
    env: str = typer.Argument(..., help="Environment (dev|test)"),
    service: Optional[str] = typer.Argument(None, help="Service name (apisix, etcd, portal-backend, loader)"),
    follow: bool = typer.Option(False, "--follow", "-f", help="Follow log output"),
    tail: int = typer.Option(100, "--tail", "-n", help="Number of lines to show from end")
):
    """Show logs for environment or specific service"""
    env = validate_env(env)
    logs_command(env, service, follow, tail)

@app.command()
def routes(
    env: str = typer.Argument(..., help="Environment (dev|test)"),
    detailed: bool = typer.Option(False, "--detailed", "-d", help="Show detailed route information"),
    route_id: Optional[str] = typer.Option(None, "--route-id", help="Show specific route details")
):
    """List configured routes"""
    env = validate_env(env)
    routes_command(env, detailed, route_id)

def main():
    """Main CLI entry point with error handling"""
    try:
        # Ensure we're in the right directory
        project_root = Path(__file__).parent.parent
        os.chdir(project_root)

        # Run the CLI
        app()
    except KeyboardInterrupt:
        console.print("\n[yellow]Operation cancelled by user[/yellow]")
        sys.exit(1)
    except Exception as e:
        console.print(f"[red]❌ Unexpected error: {e}[/red]")
        sys.exit(1)

if __name__ == "__main__":
    main()