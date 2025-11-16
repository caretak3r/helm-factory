#!/usr/bin/env python3
"""
Helm Chart Generator - Generates service-specific Helm charts from configuration.yml
and the platform library chart.
"""

import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict

import click
import yaml
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
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


def validate_configuration(config: Dict[str, Any]) -> bool:
    """Validate the service configuration."""
    required_fields = ["service", "deployment"]
    missing_fields = [field for field in required_fields if field not in config]

    if missing_fields:
        console.print(
            f"[red]Error:[/red] Missing required fields: {', '.join(missing_fields)}"
        )
        return False

    if "name" not in config.get("service", {}):
        console.print("[red]Error:[/red] service.name is required")
        return False

    if "image" not in config.get("deployment", {}):
        console.print("[red]Error:[/red] deployment.image is required")
        return False

    return True


def merge_with_library_values(
    config: Dict[str, Any], library_values_path: Path
) -> Dict[str, Any]:
    """Merge service configuration with library chart default values."""
    library_values = load_yaml_file(library_values_path)

    # Deep merge: service config takes precedence
    merged = library_values.copy()

    def deep_merge(base: Dict, override: Dict) -> Dict:
        """Recursively merge dictionaries."""
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = deep_merge(result[key], value)
            else:
                result[key] = value
        return result

    return deep_merge(merged, config)


def generate_chart(
    config_path: Path,
    library_chart_path: Path,
    output_path: Path,
    chart_name: str = None,
) -> None:
    """Generate a Helm chart from configuration and library chart."""
    console.print(f"\n[bold cyan]Generating Helm chart...[/bold cyan]")

    # Load configuration
    config = load_yaml_file(config_path)
    if not validate_configuration(config):
        sys.exit(1)

    # Determine chart name
    if not chart_name:
        chart_name = config.get("service", {}).get("name", "service")
        if not chart_name:
            console.print("[red]Error:[/red] Could not determine chart name")
            sys.exit(1)

    # Create output directory
    output_path.mkdir(parents=True, exist_ok=True)
    templates_path = output_path / "templates"
    templates_path.mkdir(exist_ok=True)

    # Copy all library chart templates (needed for template functions)
    library_templates_dir = library_chart_path / "templates"
    if library_templates_dir.exists():
        # Copy all template files starting with underscore (library templates)
        for template_file in library_templates_dir.glob("_*"):
            shutil.copy2(template_file, templates_path / template_file.name)
        console.print(f"[green]✓[/green] Copied library chart templates")

    # Merge configuration with library values
    library_values = library_chart_path / "values.yaml"
    merged_values = merge_with_library_values(config, library_values)

    # Determine library chart path (relative or absolute)
    # For local development, use absolute path
    # For CI/CD, might need relative path
    library_repo = f"file://{library_chart_path.absolute()}"
    
    # Write Chart.yaml
    chart_yaml = {
        "apiVersion": "v2",
        "name": chart_name,
        "description": f"Auto-generated Helm chart for {chart_name}",
        "type": "application",
        "version": config.get("version", "0.1.0"),
        "appVersion": config.get("appVersion", "1.0.0"),
        "dependencies": [
            {
                "name": "platform",
                "version": "1.0.0",
                "repository": library_repo,
            }
        ],
    }

    chart_yaml_path = output_path / "Chart.yaml"
    with open(chart_yaml_path, "w", encoding="utf-8") as f:
        yaml.dump(chart_yaml, f, default_flow_style=False, sort_keys=False)
    console.print(f"[green]✓[/green] Created Chart.yaml")

    # Write values.yaml (merged configuration)
    values_yaml_path = output_path / "values.yaml"
    with open(values_yaml_path, "w", encoding="utf-8") as f:
        yaml.dump(merged_values, f, default_flow_style=False, sort_keys=False)
    console.print(f"[green]✓[/green] Created values.yaml")

    # Create templates that reference library chart
    templates_path = output_path / "templates"

    # Deployment template
    deployment_template = """{{- include "platform.deployment" . }}
"""
    (templates_path / "deployment.yaml").write_text(deployment_template)

    # Service template
    service_template = """{{- include "platform.service" . }}
"""
    (templates_path / "service.yaml").write_text(service_template)

    # Ingress template (conditional)
    if merged_values.get("ingress", {}).get("enabled"):
        ingress_template = """{{- include "platform.ingress" . }}
"""
        (templates_path / "ingress.yaml").write_text(ingress_template)

    # Certificate template (conditional)
    if merged_values.get("certificate", {}).get("enabled"):
        cert_template = """{{- include "platform.certificate" . }}
"""
        (templates_path / "certificate.yaml").write_text(cert_template)

    # mTLS template (conditional)
    if merged_values.get("mtls", {}).get("enabled"):
        mtls_template = """{{- include "platform.mtls" . }}
"""
        (templates_path / "mtls.yaml").write_text(mtls_template)

    # ServiceAccount template
    sa_template = """{{- include "platform.serviceAccount" . }}
"""
    (templates_path / "serviceaccount.yaml").write_text(sa_template)

    # HPA template (conditional)
    if merged_values.get("autoscaling", {}).get("enabled"):
        hpa_template = """{{- include "platform.hpa" . }}
"""
        (templates_path / "hpa.yaml").write_text(hpa_template)

    console.print(f"\n[bold green]✓ Chart generated successfully![/bold green]")
    console.print(f"Output directory: [cyan]{output_path}[/cyan]")


@click.command()
@click.option(
    "--config",
    "-c",
    required=True,
    type=click.Path(exists=True, path_type=Path),
    help="Path to service configuration.yml file",
)
@click.option(
    "--library",
    "-l",
    default="platform-library",
    type=click.Path(exists=True, path_type=Path),
    help="Path to platform library chart directory",
)
@click.option(
    "--output",
    "-o",
    required=True,
    type=click.Path(path_type=Path),
    help="Output directory for generated chart",
)
@click.option(
    "--name",
    "-n",
    type=str,
    help="Chart name (defaults to service.name from config)",
)
def main(config: Path, library: Path, output: Path, name: str) -> None:
    """Generate a Helm chart from configuration.yml and library chart."""
    console.print(
        Panel.fit(
            "[bold cyan]Helm Chart Generator[/bold cyan]\n"
            "Generates service-specific Helm charts from configuration",
            border_style="cyan",
        )
    )

    generate_chart(config, library, output, name)


if __name__ == "__main__":
    main()

