import yaml
import subprocess
import os
from rich.console import Console
from rich.table import Table
from rich.live import Live
from rich.text import Text
import time

console = Console()

def run_phase_script(script_path: str, console: Console) -> bool:
    """Runs a shell script for a deployment phase and captures its output."""
    console.print(f"[bold blue]Running {os.path.basename(script_path)}...[/bold blue]")
    process = subprocess.Popen(
        ["bash", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
    )

    # Stream output live
    for line in process.stdout:
        console.print(f"  [dim]{line.strip()}[/dim]")

    process.wait()
    return process.returncode == 0

def main():
    """Main function to run the deployment."""
    console.print("[bold cyan]Nexus Sandbox Framework Deployment[/bold cyan]")

    with open("deployment_config.yaml", "r") as f:
        config = yaml.safe_load(f)

    phases_data = [
        {"name": "Preflight Checks", "script": "01-preflight-checks.sh", "status": "⏳ Pending"},
        {"name": "Infrastructure", "script": "02-infrastructure.sh", "status": "⏳ Pending"},
        {"name": "K3s Base Install", "script": "03-k3s-base-install.sh", "status": "⏳ Pending"},
        {"name": "Secure Runtimes", "script": "04-secure-runtimes.sh", "status": "⏳ Pending"},
        {"name": "GPU Operator", "script": "05-gpu-operator.sh", "status": "⏳ Pending"},
        {"name": "Nexus Framework", "script": "06-nexus-framework.sh", "status": "⏳ Pending"},
        {"name": "RBaaS Integration", "script": "07-rbaas-integration.sh", "status": "⏳ Pending"},
        {"name": "Observability", "script": "08-observability.sh", "status": "⏳ Pending"},
        {"name": "Validation", "script": "09-validation.sh", "status": "⏳ Pending"},
    ]

    def make_table() -> Table:
        table = Table(title="Deployment Phases")
        table.add_column("Phase", justify="left", style="cyan", no_wrap=True)
        table.add_column("Status", justify="left", style="green")
        for phase in phases_data:
            table.add_row(phase["name"], phase["status"])
        return table

    with Live(make_table(), refresh_per_second=4) as live:
        for i, phase in enumerate(phases_data):
            script_path = os.path.join("scripts", phase["script"])
            
            # Update status to Running
            phases_data[i]["status"] = "🔄 Running"
            live.update(make_table())
            console.print(Text(f"Starting Phase: {phase['name']}", style="bold yellow"))

            if run_phase_script(script_path, console):
                phases_data[i]["status"] = "✅ Complete"
                console.print(Text(f"Phase {phase['name']} Complete.", style="bold green"))
            else:
                phases_data[i]["status"] = "❌ Failed"
                live.update(make_table())
                console.print(Text(f"Phase {phase['name']} Failed. Aborting deployment.", style="bold red"))
                exit(1)
            live.update(make_table())
            time.sleep(0.5) # Small delay for visual update

    console.print("\n[bold green]Deployment Orchestration Complete![/bold green]")

if __name__ == "__main__":
    main()
