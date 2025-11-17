#!/usr/bin/env python3
"""
Umbrella Chart Sync Tool - Syncs service configurations to umbrella chart dependencies.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List

import click
import yaml
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

console = Console()

def load_yaml_file(file_path: Path) -> Dict[str, Any]:
    """Load and parse a YAML file."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except FileNotFoundError:
        console.print(f"[red]Error:[/red] File not found: {file_path}")
        sys.exit(1)
    except yaml.YAMLError as e:
        console.print(f"[red]Error:[/red] Invalid YAML in {file_path}: {e}")
        sys.exit(1)


def save_yaml_file(file_path: Path, data: Dict[str, Any]) -> None:
    """Save data to a YAML file."""
    with open(file_path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)


def find_service_configs(services_dir: Path) -> List[Dict[str, Any]]:
    """Find all service configuration files."""
    configs = []
    if not services_dir.exists():
        return configs

    for config_file in services_dir.glob("**/configuration.yml"):
        config = load_yaml_file(config_file)
        config["_path"] = config_file
        configs.append(config)
    return configs


def update_umbrella_chart(
    umbrella_chart_path: Path,
    services_dir: Path,
    library_chart_path: Path,
) -> None:
    """Update umbrella chart Chart.yaml with dependencies from service configs."""
    console.print(f"\n[bold cyan]Updating umbrella chart...[/bold cyan]")

    chart_yaml_path = umbrella_chart_path / "Chart.yaml"
    if not chart_yaml_path.exists():
        console.print(f"[red]Error:[/red] Chart.yaml not found at {chart_yaml_path}")
        sys.exit(1)

    chart_yaml = load_yaml_file(chart_yaml_path)
    service_configs = find_service_configs(services_dir)

    if not service_configs:
        console.print("[yellow]Warning:[/yellow] No service configurations found")
        return

    # Build dependencies list
    dependencies = []
    values_files = {}

    for config in service_configs:
        service_name = config.get("service", {}).get("name")
        if not service_name:
            console.print(
                f"[yellow]Warning:[/yellow] Skipping config without service.name: {config['_path']}"
            )
            continue

        # Generate chart for this service
        service_chart_dir = umbrella_chart_path / "charts" / service_name
        
        # Import chart generator
        chart_gen_path = Path(__file__).parent.parent / "chart-generator"
        sys.path.insert(0, str(chart_gen_path))
        from main import generate_chart
        
        service_chart_dir.mkdir(parents=True, exist_ok=True)
        generate_chart(
            config["_path"],
            library_chart_path,
            service_chart_dir,
            service_name
        )
        console.print(f"[green]✓[/green] Generated chart for {service_name}")

        # Add dependency
        dependency = {
            "name": service_name,
            "version": config.get("version", "0.1.0"),
            "repository": f"file://{service_chart_dir.absolute()}",
            "alias": service_name,
        }
        dependencies.append(dependency)
        
        # Also create values file for umbrella chart
        values_file = umbrella_chart_path / f"values-{service_name}.yaml"
        config_copy = {k: v for k, v in config.items() if k != "_path"}
        save_yaml_file(values_file, config_copy)

        console.print(f"[green]✓[/green] Added dependency: {service_name}")

    # Update Chart.yaml
    chart_yaml["dependencies"] = dependencies
    save_yaml_file(chart_yaml_path, chart_yaml)

    console.print(f"\n[bold green]✓ Umbrella chart updated![/bold green]")
    console.print(f"Found {len(dependencies)} service dependencies")

    # Display summary table
    table = Table(title="Service Dependencies")
    table.add_column("Service Name", style="cyan")
    table.add_column("Version", style="green")
    table.add_column("Alias", style="yellow")

    for dep in dependencies:
        table.add_row(dep["name"], dep["version"], dep.get("alias", ""))

    console.print("\n")
    console.print(table)


@click.command()
@click.option(
    "--umbrella",
    "-u",
    required=True,
    type=click.Path(exists=True, path_type=Path),
    help="Path to umbrella chart directory",
)
@click.option(
    "--services",
    "-s",
    required=True,
    type=click.Path(exists=True, path_type=Path),
    help="Path to directory containing service configuration.yml files",
)
@click.option(
    "--library",
    "-l",
    default="platform-library",
    type=click.Path(exists=True, path_type=Path),
    help="Path to platform library chart directory",
)
def main(umbrella: Path, services: Path, library: Path) -> None:
    """Sync service configurations to umbrella chart dependencies."""
    console.print(
        Panel.fit(
            "[bold cyan]Umbrella Chart Sync[/bold cyan]\n"
            "Syncs service configurations to umbrella chart dependencies",
            border_style="cyan",
        )
    )

    # Generate charts and update umbrella chart
    update_umbrella_chart(umbrella, services, library)


if __name__ == "__main__":
    main()

