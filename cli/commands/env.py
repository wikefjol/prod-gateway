"""
Environment command - show environment configuration and variables

This command helps debug configuration issues by showing exactly what
environment variables are loaded for a given environment.
"""
from rich.console import Console
from rich.table import Table
import typer

from lib.environment import load_environment, EnvironmentError

console = Console()

def env_command(env: str):
    """
    Show environment configuration and variables

    This displays the complete environment configuration loaded
    from the environment.sh setup for debugging purposes.

    Args:
        env: Environment (dev|test)
    """
    console.print(f"[bold blue]Environment configuration for {env}[/bold blue]")

    try:
        # Load environment configuration
        console.print("[dim]Loading environment configuration...[/dim]")
        env_vars = load_environment("entraid", env)

        # Create table for key environment variables
        table = Table(title=f"{env.title()} Environment Variables")
        table.add_column("Variable", style="cyan", no_wrap=True)
        table.add_column("Value", style="green")
        table.add_column("Source", style="dim")

        # Key variables to show (in order of importance)
        key_vars = [
            ("ENVIRONMENT", "Core"),
            ("APISIX_ADMIN_API", "Core"),
            ("APISIX_DATA_PLANE", "Core"),
            ("ADMIN_KEY", "Security"),
            ("OIDC_CLIENT_ID", "OIDC"),
            ("OIDC_CLIENT_SECRET", "OIDC"),
            ("OIDC_DISCOVERY_ENDPOINT", "OIDC"),
            ("OIDC_REDIRECT_URI", "OIDC"),
            ("OIDC_SESSION_SECRET", "OIDC"),
            ("OIDC_PROVIDER_NAME", "OIDC"),
            ("OPENAI_API_KEY", "Provider"),
            ("ANTHROPIC_API_KEY", "Provider"),
            ("LITELLM_KEY", "Provider"),
        ]

        # Add key variables to table
        for var_name, source in key_vars:
            value = env_vars.get(var_name, "[red]NOT SET[/red]")
            if var_name in ["ADMIN_KEY", "OIDC_CLIENT_SECRET", "OIDC_SESSION_SECRET",
                           "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "LITELLM_KEY"]:
                # Mask sensitive values
                if value and value != "[red]NOT SET[/red]":
                    value = f"{value[:8]}..."
            table.add_row(var_name, value, source)

        console.print(table)

        # Show configuration file sources
        console.print(f"\n[bold]Configuration Sources:[/bold]")
        console.print(f"[dim]1. config/env/{env}.env (base)[/dim]")
        console.print(f"[dim]2. config/providers/entraid/{env}.env (provider)[/dim]")
        console.print(f"[dim]3. scripts/core/environment.sh (setup logic)[/dim]")

        # Show critical missing variables
        missing_critical = []
        critical_vars = ["ADMIN_KEY", "OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET",
                        "OIDC_DISCOVERY_ENDPOINT"]

        for var in critical_vars:
            if not env_vars.get(var):
                missing_critical.append(var)

        if missing_critical:
            console.print(f"\n[red]❌ Missing critical variables:[/red]")
            for var in missing_critical:
                console.print(f"[red]   - {var}[/red]")
        else:
            console.print(f"\n[green]✅ All critical variables configured[/green]")

        # Show optional provider variables
        provider_vars = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "LITELLM_KEY"]
        missing_provider = [var for var in provider_vars if not env_vars.get(var)]

        if missing_provider:
            console.print(f"\n[yellow]⚠️ Missing provider variables (optional):[/yellow]")
            for var in missing_provider:
                console.print(f"[yellow]   - {var}[/yellow]")
            console.print(f"[dim]   Provider routes will be skipped during bootstrap[/dim]")

    except EnvironmentError as e:
        console.print(f"[red]❌ Failed to load environment configuration:[/red]")
        console.print(f"[red]{e}[/red]")

        console.print(f"\n[cyan]💡 Troubleshooting:[/cyan]")
        console.print(f"[cyan]   1. Check config files exist: config/env/{env}.env[/cyan]")
        console.print(f"[cyan]   2. Check provider config: config/providers/entraid/{env}.env[/cyan]")
        console.print(f"[cyan]   3. Verify environment.sh: ./scripts/core/environment.sh[/cyan]")

        raise typer.Exit(1)