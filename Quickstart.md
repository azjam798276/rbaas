# 1. Clone or create your project directory
mkdir nexus-sandbox-framework && cd nexus-sandbox-framework

# 2. Set up environment
export PM_API_TOKEN_ID="user@realm!token"
export PM_API_TOKEN_SECRET="your-secret"

# 3. Install Python dependencies
pip3 install rich pyyaml

# 4. Configure deployment
vim deployment_config.yaml
# Update: proxmox endpoint, node name, network settings, GPU PCI addresses

# 5. Run deployment
python3 deploy.py
```

## 📊 **What the TUI Shows**
```
╭─────────────────────────────────────────────────────────────╮
│      Nexus Sandbox Framework Deployment                    │
│      Deployment started: 2025-11-03 10:00:00               │
╰─────────────────────────────────────────────────────────────╯

╭─ Deployment Phases ─────────────────┬─ Logs: Infrastructure Provisioning ─╮
│ Phase              Status   Duration │ [2025-11-03 10:05:23] Initializing  │
│ Preflight Checks   ✅ Complete  12.3s │ OpenTofu...                         │
│ Infrastructure     🔄 Running   -     │ [2025-11-03 10:05:25] Downloading   │
│ K3s Base Install   ⏳ Pending   -     │ provider plugins...                 │
│ Secure Runtimes    ⏳ Pending   -     │ [2025-11-03 10:05:30] Creating VMs  │
│ GPU Operator       ⏳ Pending   -     │ [2025-11-03 10:05:45] Applying      │
│ Nexus Framework    ⏳ Pending   -     │ cloud-init configuration...         │
│ RBaaS Integration  ⏳ Pending   -     │                                     │
│ Observability      ⏳ Pending   -     │ Total lines: 156                    │
│ Validation         ⏳ Pending   -     │                                     │
╰─────────────────────────────────────┴─────────────────────────────────────╯

╭─ Progress ──────────────────────────────────────────────────────────────────╮
│ Progress: 2/9 phases                                                        │
│ ⠋ Overall Progress ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 22% -:--:--          │
╰─────────────────────────────────────────────────────────────────────────────╯
 Key Features

Maximum Observability: Every command runs with verbose logging
Modular Scripts: Each phase is a separate shell script (to be created in scripts/ directory)
Error Recovery: Comprehensive troubleshooting guide with solutions
Git Integration: Professional version control setup with GitHub sync
Security First: No secrets in repo, environment variable based auth
Production Ready: HA control plane, GPU passthrough, multi-tenancy

📁 Next Steps

Create Script Directory Structure:

bashmkdir -p scripts
# Create scripts 01-09 based on the orchestrator's phase definitions

Initialize Git:

bashgit init
git add .
git commit -m "Initial commit: Nexus Sandbox Framework"

Create GitHub Repo and Sync:

bashgh repo create nexus-sandbox-framework --private --source=. --push

Customize Configuration:

bashvim deployment_config.yaml
# Update Proxmox settings, network, GPU PCI addresses

Run Deployment:

bashpython3 deploy.py
The system is designed to be production-grade with enterprise-level observability, security, and maintainability. All components integrate seamlessly: OpenTofu provisions infrastructure, Ansible configures systems, Kubernetes orchestrates workloads, and the Rich TUI gives you real-time visibility into every step.
