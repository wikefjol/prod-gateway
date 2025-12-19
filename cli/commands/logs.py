"""
Logs command - view service logs for debugging

This command provides easy access to container logs for debugging
and monitoring purposes.
"""
import subprocess
from rich.console import Console
import typer

console = Console()

def logs_command(env: str, service: str = None, follow: bool = False, tail: int = 100):
    """
    View service logs for debugging

    This provides access to container logs for troubleshooting and monitoring.
    Without a service specified, shows logs for all services in the environment.

    Args:
        env: Environment (dev|test)
        service: Specific service to show logs for (optional)
        follow: Follow log output (like tail -f)
        tail: Number of lines to show from the end (default: 100)
    """
    project_name = f"apisix-{env}"

    if service:
        console.print(f"[bold blue]Logs for {service} service in {env} environment[/bold blue]")
    else:
        console.print(f"[bold blue]Logs for all services in {env} environment[/bold blue]")

    try:
        # Build docker compose logs command
        cmd = ["docker", "compose", "-p", project_name, "logs"]

        if follow:
            cmd.append("--follow")

        if tail > 0:
            cmd.extend(["--tail", str(tail)])

        # Add timestamps for better debugging
        cmd.append("--timestamps")

        # Add specific service if provided
        if service:
            cmd.append(service)

        console.print(f"[dim]Executing: {' '.join(cmd)}[/dim]")
        console.print(f"[dim]Press Ctrl+C to stop following logs[/dim]\n")

        # Execute logs command
        subprocess.run(cmd, check=True)

    except subprocess.CalledProcessError as e:
        console.print(f"[red]❌ Failed to get logs for {env} environment[/red]")
        console.print(f"[red]Exit code: {e.returncode}[/red]")

        # Show helpful troubleshooting
        console.print(f"\n[cyan]💡 Troubleshooting:[/cyan]")

        if service:
            console.print(f"[cyan]   1. Check if '{service}' service exists: gw status {env}[/cyan]")
            console.print(f"[cyan]   2. List available services: docker compose -p {project_name} ps[/cyan]")
        else:
            console.print(f"[cyan]   1. Check if environment is running: gw status {env}[/cyan]")
            console.print(f"[cyan]   2. Start environment: gw up {env}[/cyan]")

        console.print(f"[cyan]   3. Check Docker daemon is running: docker ps[/cyan]")

        raise typer.Exit(1)

    except KeyboardInterrupt:
        console.print(f"\n[yellow]⚠️ Log viewing cancelled[/yellow]")