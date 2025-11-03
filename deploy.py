import yaml
from rich.console import Console
from rich.table import Table

console = Console()

def main():
    """Main function to run the deployment."""
    console.print("[bold cyan]Nexus Sandbox Framework Deployment[/bold cyan]")

    with open("deployment_config.yaml", "r") as f:
        config = yaml.safe_load(f)

    phases = [
        "Preflight Checks",
        "Infrastructure",
        "K3s Base Install",
        "Secure Runtimes",
        "GPU Operator",
        "Nexus Framework",
        "RBaaS Integration",
        "Observability",
        "Validation",
    ]

    table = Table(title="Deployment Phases")
    table.add_column("Phase", justify="left", style="cyan", no_wrap=True)
    table.add_column("Status", justify="left", style="green")

    for phase in phases:
        table.add_row(phase, "⏳ Pending")

    console.print(table)

if __name__ == "__main__":
    main()
