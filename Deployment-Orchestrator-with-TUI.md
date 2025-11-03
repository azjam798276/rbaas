#!/usr/bin/env python3
"""
Nexus Sandbox Framework Deployment Orchestrator
Main controller with Rich TUI for monitoring deployment progress
"""

import asyncio
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import json
import yaml

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.progress import (
    Progress,
    SpinnerColumn,
    TextColumn,
    BarColumn,
    TaskProgressColumn,
    TimeRemainingColumn,
)
from rich.table import Table
from rich.text import Text
from rich.logging import RichHandler
import logging

# Configure rich logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True, markup=True)]
)
logger = logging.getLogger("nexus_deploy")


class DeploymentPhase:
    """Represents a deployment phase with child tasks"""
    
    def __init__(self, name: str, description: str, script: str, children: List[str] = None):
        self.name = name
        self.description = description
        self.script = script
        self.children = children or []
        self.status = "pending"  # pending, running, completed, failed
        self.start_time = None
        self.end_time = None
        self.logs: List[str] = []
        self.error: Optional[str] = None


class DeploymentOrchestrator:
    """Main orchestrator for Nexus deployment"""
    
    def __init__(self, config_path: str = "deployment_config.yaml"):
        self.console = Console()
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.phases: Dict[str, DeploymentPhase] = self._initialize_phases()
        self.logs_dir = Path("logs") / datetime.now().strftime("%Y%m%d_%H%M%S")
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        
    def _load_config(self) -> dict:
        """Load deployment configuration"""
        if not self.config_path.exists():
            logger.error(f"Config file not found: {self.config_path}")
            sys.exit(1)
        
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def _initialize_phases(self) -> Dict[str, DeploymentPhase]:
        """Initialize all deployment phases"""
        return {
            "preflight": DeploymentPhase(
                name="Preflight Checks",
                description="Validate prerequisites and environment",
                script="scripts/01_preflight_checks.sh",
                children=[
                    "Check Proxmox connectivity",
                    "Validate API credentials",
                    "Check OpenTofu installation",
                    "Check Ansible installation",
                    "Verify network configuration",
                    "Check available resources"
                ]
            ),
            "infrastructure": DeploymentPhase(
                name="Infrastructure Provisioning",
                description="Provision VMs with OpenTofu",
                script="scripts/02_provision_infrastructure.sh",
                children=[
                    "Initialize OpenTofu",
                    "Validate OpenTofu configuration",
                    "Create cloud-init templates",
                    "Provision K3s control plane VMs",
                    "Provision K3s worker VMs",
                    "Configure nested virtualization",
                    "Configure GPU passthrough",
                    "Wait for VMs to boot"
                ]
            ),
            "k3s_base": DeploymentPhase(
                name="K3s Base Installation",
                description="Install and configure K3s cluster",
                script="scripts/03_install_k3s.sh",
                children=[
                    "Generate Ansible inventory",
                    "Configure SSH access",
                    "Install K3s server nodes",
                    "Configure K3s HA",
                    "Install K3s agent nodes",
                    "Verify cluster health",
                    "Install kubectl locally",
                    "Configure kubeconfig"
                ]
            ),
            "runtimes": DeploymentPhase(
                name="Secure Runtimes Setup",
                description="Install Kata Containers and gVisor",
                script="scripts/04_install_runtimes.sh",
                children=[
                    "Configure containerd for K3s",
                    "Install Kata Containers components",
                    "Create Kata RuntimeClass",
                    "Install gVisor (runsc)",
                    "Create gVisor RuntimeClass",
                    "Verify runtime installations",
                    "Run runtime smoke tests"
                ]
            ),
            "gpu": DeploymentPhase(
                name="GPU Operator Installation",
                description="Install NVIDIA GPU Operator for Kata",
                script="scripts/05_install_gpu_operator.sh",
                children=[
                    "Add NVIDIA Helm repository",
                    "Install GPU Operator",
                    "Configure Kata GPU support",
                    "Deploy sandbox device plugin",
                    "Verify GPU passthrough",
                    "Run GPU workload test"
                ]
            ),
            "nexus": DeploymentPhase(
                name="Nexus Framework Deployment",
                description="Deploy Nexus Sandbox Framework",
                script="scripts/06_deploy_nexus.sh",
                children=[
                    "Create nexus-system namespace",
                    "Deploy SandboxManager CRD",
                    "Deploy MCP registry",
                    "Deploy Orchestration Engine",
                    "Deploy API Gateway",
                    "Configure multi-tenancy",
                    "Deploy observability stack",
                    "Run integration tests"
                ]
            ),
            "rbaas": DeploymentPhase(
                name="RBaaS Integration",
                description="Deploy Remote Browser-as-a-Service",
                script="scripts/07_deploy_rbaas.sh",
                children=[
                    "Deploy BrowserSession CRD",
                    "Deploy RBaaS Operator",
                    "Deploy FastAPI control plane",
                    "Configure KasmVNC images",
                    "Setup session ingress",
                    "Deploy monitoring exporters",
                    "Run RBaaS smoke test"
                ]
            ),
            "observability": DeploymentPhase(
                name="Observability Stack",
                description="Deploy Prometheus, Grafana, Jaeger",
                script="scripts/08_deploy_observability.sh",
                children=[
                    "Deploy Prometheus Operator",
                    "Configure ServiceMonitors",
                    "Deploy Grafana",
                    "Import dashboards",
                    "Deploy Jaeger",
                    "Configure OpenTelemetry",
                    "Setup alerting rules"
                ]
            ),
            "validation": DeploymentPhase(
                name="End-to-End Validation",
                description="Run comprehensive tests",
                script="scripts/09_validate_deployment.sh",
                children=[
                    "Test Docker sandbox execution",
                    "Test Kata sandbox execution",
                    "Test gVisor sandbox execution",
                    "Test RBaaS session creation",
                    "Test GPU workload",
                    "Verify observability",
                    "Load testing",
                    "Generate deployment report"
                ]
            )
        }
    
    def create_layout(self) -> Layout:
        """Create the TUI layout"""
        layout = Layout()
        
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="footer", size=10)
        )
        
        layout["body"].split_row(
            Layout(name="phases", ratio=1),
            Layout(name="logs", ratio=2)
        )
        
        return layout
    
    def render_header(self) -> Panel:
        """Render header panel"""
        title = Text("Nexus Sandbox Framework Deployment", style="bold magenta")
        subtitle = Text(f"Deployment started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", style="dim")
        
        grid = Table.grid(expand=True)
        grid.add_column(justify="center")
        grid.add_row(title)
        grid.add_row(subtitle)
        
        return Panel(grid, style="white on blue")
    
    def render_phases(self) -> Panel:
        """Render phases progress panel"""
        table = Table(show_header=True, header_style="bold cyan", expand=True)
        table.add_column("Phase", style="cyan", width=25)
        table.add_column("Status", width=12)
        table.add_column("Duration", width=10)
        
        for phase_id, phase in self.phases.items():
            # Status with emoji
            if phase.status == "pending":
                status = "⏳ Pending"
                style = "dim"
            elif phase.status == "running":
                status = "🔄 Running"
                style = "yellow bold"
            elif phase.status == "completed":
                status = "✅ Completed"
                style = "green"
            elif phase.status == "failed":
                status = "❌ Failed"
                style = "red bold"
            else:
                status = "❓ Unknown"
                style = "dim"
            
            # Calculate duration
            if phase.start_time:
                end = phase.end_time or datetime.now()
                duration = (end - phase.start_time).total_seconds()
                duration_str = f"{duration:.1f}s"
            else:
                duration_str = "-"
            
            table.add_row(
                phase.name,
                Text(status, style=style),
                duration_str
            )
        
        return Panel(table, title="Deployment Phases", border_style="cyan")
    
    def render_logs(self, current_phase: Optional[DeploymentPhase] = None) -> Panel:
        """Render real-time logs panel"""
        if not current_phase:
            return Panel("Waiting to start...", title="Logs", border_style="blue")
        
        # Show last 20 log lines
        log_text = "\n".join(current_phase.logs[-20:]) if current_phase.logs else "No logs yet..."
        
        title = f"Logs: {current_phase.name}"
        if current_phase.error:
            title += " [red](ERROR)[/red]"
        
        return Panel(
            log_text,
            title=title,
            border_style="red" if current_phase.error else "blue",
            subtitle=f"Total lines: {len(current_phase.logs)}"
        )
    
    def render_footer(self) -> Panel:
        """Render footer with progress bar and stats"""
        # Calculate overall progress
        total_phases = len(self.phases)
        completed_phases = sum(1 for p in self.phases.values() if p.status == "completed")
        failed_phases = sum(1 for p in self.phases.values() if p.status == "failed")
        
        # Create progress table
        table = Table.grid(expand=True)
        table.add_column(justify="left")
        table.add_column(justify="right")
        
        table.add_row(
            f"Progress: {completed_phases}/{total_phases} phases",
            f"Failed: {failed_phases}" if failed_phases > 0 else ""
        )
        
        # Add progress bar
        progress = Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            TimeRemainingColumn(),
            expand=True
        )
        
        task = progress.add_task(
            "Overall Progress",
            total=total_phases,
            completed=completed_phases
        )
        
        table.add_row(progress)
        
        return Panel(table, style="white on dark_blue")
    
    async def run_phase(self, phase: DeploymentPhase) -> bool:
        """Execute a deployment phase"""
        phase.status = "running"
        phase.start_time = datetime.now()
        
        log_file = self.logs_dir / f"{phase.name.lower().replace(' ', '_')}.log"
        
        try:
            # Run the phase script
            process = await asyncio.create_subprocess_exec(
                "bash", phase.script,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                env={**subprocess.os.environ, "VERBOSE": "1"}
            )
            
            # Stream output
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                
                decoded_line = line.decode().rstrip()
                phase.logs.append(decoded_line)
                
                # Write to log file
                with open(log_file, "a") as f:
                    f.write(decoded_line + "\n")
                
                # Also log to system logger
                logger.debug(f"[{phase.name}] {decoded_line}")
            
            await process.wait()
            
            if process.returncode == 0:
                phase.status = "completed"
                phase.end_time = datetime.now()
                return True
            else:
                phase.status = "failed"
                phase.error = f"Script exited with code {process.returncode}"
                phase.end_time = datetime.now()
                return False
                
        except Exception as e:
            phase.status = "failed"
            phase.error = str(e)
            phase.end_time = datetime.now()
            logger.exception(f"Phase {phase.name} failed with exception")
            return False
    
    async def deploy(self):
        """Main deployment orchestration"""
        layout = self.create_layout()
        
        with Live(layout, refresh_per_second=4, screen=True):
            current_phase = None
            
            for phase_id, phase in self.phases.items():
                current_phase = phase
                
                # Update display
                layout["header"].update(self.render_header())
                layout["phases"].update(self.render_phases())
                layout["logs"].update(self.render_logs(current_phase))
                layout["footer"].update(self.render_footer())
                
                # Execute phase
                success = await self.run_phase(phase)
                
                if not success:
                    self.console.print(f"\n[red bold]Deployment failed at phase: {phase.name}[/red bold]")
                    self.console.print(f"[red]Error: {phase.error}[/red]")
                    self.console.print(f"\n[yellow]Check logs at: {self.logs_dir / f'{phase.name.lower().replace(' ', '_')}.log'}[/yellow]")
                    return False
                
                # Update display one final time
                layout["phases"].update(self.render_phases())
                layout["logs"].update(self.render_logs(current_phase))
                layout["footer"].update(self.render_footer())
            
            self.console.print("\n[green bold]✅ Deployment completed successfully![/green bold]")
            self.console.print(f"[green]Total time: {self._calculate_total_time()}[/green]")
            self.console.print(f"\n[cyan]Logs saved to: {self.logs_dir}[/cyan]")
            return True
    
    def _calculate_total_time(self) -> str:
        """Calculate total deployment time"""
        start_times = [p.start_time for p in self.phases.values() if p.start_time]
        end_times = [p.end_time for p in self.phases.values() if p.end_time]
        
        if start_times and end_times:
            total_seconds = (max(end_times) - min(start_times)).total_seconds()
            return f"{total_seconds:.1f} seconds"
        return "Unknown"


async def main():
    """Main entry point"""
    console = Console()
    
    console.print(Panel.fit(
        "[bold cyan]Nexus Sandbox Framework[/bold cyan]\n"
        "[white]Automated Deployment System[/white]\n\n"
        "[dim]Starting deployment orchestration...[/dim]",
        border_style="cyan"
    ))
    
    orchestrator = DeploymentOrchestrator()
    success = await orchestrator.deploy()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        console = Console()
        console.print("\n[yellow]Deployment interrupted by user[/yellow]")
        sys.exit(130)
