# Git Initialization and GitHub Synchronization Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Repository Setup](#initial-repository-setup)
3. [Project Structure](#project-structure)
4. [First Commit](#first-commit)
5. [GitHub Repository Creation](#github-repository-creation)
6. [Connecting to GitHub](#connecting-to-github)
7. [Branch Strategy](#branch-strategy)
8. [Syncing with GitHub](#syncing-with-github)
9. [Collaboration Workflow](#collaboration-workflow)
10. [Security Best Practices](#security-best-practices)
11. [Common Git Operations](#common-git-operations)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Install Git

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y git

# Verify installation
git --version  # Should show version 2.x or higher
```

### Configure Git Identity

```bash
# Set your name and email (required for commits)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Optional: Set default branch name to 'main'
git config --global init.defaultBranch main

# Optional: Configure preferred editor
git config --global core.editor "vim"  # or "nano", "code --wait", etc.

# Optional: Enable color output
git config --global color.ui auto

# Verify configuration
git config --list
```

### GitHub Account Setup

1. **Create GitHub Account:** https://github.com/signup
2. **Generate SSH Key** (recommended for authentication):

```bash
# Generate ED25519 key (modern and secure)
ssh-keygen -t ed25519 -C "your.email@example.com" -f ~/.ssh/github_ed25519

# Or RSA key (if ED25519 not supported)
ssh-keygen -t rsa -b 4096 -C "your.email@example.com" -f ~/.ssh/github_rsa

# Start SSH agent
eval "$(ssh-agent -s)"

# Add key to agent
ssh-add ~/.ssh/github_ed25519

# Copy public key to clipboard
cat ~/.ssh/github_ed25519.pub
# Or use: xclip -sel clip < ~/.ssh/github_ed25519.pub
```

3. **Add SSH Key to GitHub:**
   - Go to: https://github.com/settings/keys
   - Click "New SSH key"
   - Paste the public key
   - Give it a descriptive title (e.g., "Nexus Deployment Machine")

4. **Test Connection:**

```bash
ssh -T git@github.com
# Should see: "Hi username! You've successfully authenticated..."
```

---

## Initial Repository Setup

### Step 1: Navigate to Project Directory

```bash
cd /path/to/nexus-sandbox-framework
```

### Step 2: Initialize Git Repository

```bash
# Initialize new Git repository
git init

# Verify initialization
ls -la .git/  # Should show Git directory structure

# Check initial status
git status
```

### Step 3: Create .gitignore

The `.gitignore` file has already been provided. Verify it's in place:

```bash
# Check if .gitignore exists
cat .gitignore

# If not present, create it from the artifact provided
# Copy the .gitignore content from the previous artifact
```

---

## Project Structure

Your project should follow this structure:

```
nexus-sandbox-framework/
├── .git/                           # Git metadata (auto-created)
├── .gitignore                      # Git ignore rules
├── README.md                       # Project documentation
├── deploy.py                       # Main deployment orchestrator
├── deployment_config.yaml          # Deployment configuration
├── requirements.txt                # Python dependencies
├── terraform/                      # Infrastructure as Code
│   ├── main.tf                     # Main Terraform config
│   ├── variables.tf                # Variable definitions
│   ├── outputs.tf                  # Output definitions
│   ├── providers.tf                # Provider configuration
│   └── cloud-init/                 # Cloud-init templates
│       ├── control-plane.yaml.tpl
│       ├── worker.yaml.tpl
│       └── gpu-worker.yaml.tpl
├── ansible/                        # Configuration management
│   ├── inventory/
│   │   └── hosts.ini.tpl           # Inventory template
│   ├── playbooks/
│   │   ├── k3s-install.yaml
│   │   ├── kata-install.yaml
│   │   ├── gpu-operator.yaml
│   │   └── nexus-deploy.yaml
│   ├── roles/                      # Ansible roles
│   └── ansible.cfg
├── kubernetes/                     # Kubernetes manifests
│   ├── crds/                       # Custom Resource Definitions
│   │   ├── browsersession-crd.yaml
│   │   └── sandboxconfig-crd.yaml
│   ├── operators/                  # Operator deployments
│   │   ├── rbaas-operator.yaml
│   │   └── sandbox-operator.yaml
│   ├── core/                       # Core Nexus components
│   │   ├── namespace.yaml
│   │   ├── orchestrator.yaml
│   │   ├── api-gateway.yaml
│   │   └── mcp-registry.yaml
│   └── monitoring/                 # Observability stack
│       ├── prometheus/
│       ├── grafana/
│       └── jaeger/
├── scripts/                        # Deployment scripts
│   ├── 01_preflight_checks.sh
│   ├── 02_provision_infrastructure.sh
│   ├── 03_install_k3s.sh
│   ├── 04_install_runtimes.sh
│   ├── 05_install_gpu_operator.sh
│   ├── 06_deploy_nexus.sh
│   ├── 07_deploy_rbaas.sh
│   ├── 08_deploy_observability.sh
│   └── 09_validate_deployment.sh
├── docs/                           # Documentation
│   ├── architecture.md
│   ├── deployment-guide.md
│   ├── troubleshooting.md
│   └── api-reference.md
├── tests/                          # Test suites
│   ├── unit/
│   ├── integration/
│   └── e2e/
└── .github/                        # GitHub-specific files
    ├── workflows/                  # CI/CD workflows
    │   ├── lint.yaml
    │   ├── test.yaml
    │   └── deploy.yaml
    └── ISSUE_TEMPLATE/
        ├── bug_report.md
        └── feature_request.md
```

---

## First Commit

### Step 1: Create README.md

```bash
cat > README.md << 'EOF'
# Nexus Sandbox Framework

A production-grade, multi-tenant Kubernetes framework for executing untrusted code in isolated sandboxes with hardware-enforced security.

## Features

- **Multiple Isolation Runtimes:** Docker, Kata Containers, gVisor
- **GPU Acceleration:** NVIDIA GPU passthrough via Kata Containers
- **Remote Browser-as-a-Service (RBaaS):** Secure, isolated browser sessions
- **MCP Integration:** Universal tool protocol for AI agents
- **Full Observability:** Prometheus, Grafana, Jaeger, Loki
- **Multi-tenancy:** Kubernetes-native resource isolation and RBAC

## Quick Start

```bash
# 1. Configure deployment
cp deployment_config.yaml.example deployment_config.yaml
vim deployment_config.yaml

# 2. Set Proxmox credentials
export PM_API_TOKEN_ID="user@realm!token"
export PM_API_TOKEN_SECRET="your-secret"

# 3. Run deployment
python3 deploy.py
```

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Deployment Guide](docs/deployment-guide.md)
- [Troubleshooting](docs/troubleshooting.md)
- [API Reference](docs/api-reference.md)

## Requirements

- Proxmox VE 8.x
- OpenTofu/Terraform >= 1.6
- Ansible >= 2.15
- Python >= 3.10
- NVIDIA GPU (optional, for RBaaS)

## License

[Your License Here]

## Support

For issues and questions: [GitHub Issues](https://github.com/your-org/nexus-sandbox-framework/issues)
EOF
```

### Step 2: Stage All Files

```bash
# Add all files to staging area
git add .

# Verify what will be committed
git status

# See detailed diff of staged changes
git diff --staged
```

### Step 3: Create Initial Commit

```bash
# Commit with descriptive message
git commit -m "Initial commit: Nexus Sandbox Framework infrastructure

- Add OpenTofu configuration for Proxmox VM provisioning
- Add Ansible playbooks for K3s, Kata Containers, GPU Operator
- Add deployment orchestrator with Rich TUI
- Add comprehensive documentation and troubleshooting guide
- Configure multi-runtime support (Docker, Kata, gVisor)
- Set up RBaaS architecture with BrowserSession CRD"

# Verify commit
git log --oneline
```

---

## GitHub Repository Creation

### Option 1: Via GitHub Web UI

1. Go to: https://github.com/new
2. **Repository name:** `nexus-sandbox-framework`
3. **Description:** "Production-grade Kubernetes framework for isolated code execution"
4. **Visibility:** 
   - `Private` (recommended for initial development)
   - `Public` (for open-source projects)
5. **DO NOT** initialize with README, .gitignore, or license (we have these locally)
6. Click "Create repository"

### Option 2: Via GitHub CLI

```bash
# Install GitHub CLI
# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Authenticate
gh auth login

# Create repository
gh repo create nexus-sandbox-framework \
  --private \
  --description "Production-grade Kubernetes framework for isolated code execution" \
  --source=. \
  --remote=origin \
  --push
```

---

## Connecting to GitHub

### Add Remote Repository

```bash
# Add GitHub as remote (replace with your URL)
git remote add origin git@github.com:your-username/nexus-sandbox-framework.git

# Verify remote
git remote -v

# If you made a mistake, remove and re-add
git remote remove origin
git remote add origin git@github.com:your-username/nexus-sandbox-framework.git
```

### Push to GitHub

```bash
# Push main branch to GitHub
git push -u origin main

# The -u flag sets upstream tracking
# Future pushes can simply use: git push
```

### Verify on GitHub

Navigate to your repository on GitHub:
```
https://github.com/your-username/nexus-sandbox-framework
```

You should see all your files and the initial commit.

---

## Branch Strategy

### Recommended GitFlow Workflow

```
main (production)
  ↑
  └── develop (integration)
       ↑
       ├── feature/gpu-passthrough
       ├── feature/rbaas-operator
       └── bugfix/kata-networking
```

### Create Branch Structure

```bash
# Create and switch to develop branch
git checkout -b develop

# Push develop to GitHub
git push -u origin develop

# Create feature branch (always from develop)
git checkout develop
git checkout -b feature/your-feature-name

# Work on feature
# ... make changes ...
git add .
git commit -m "feat: add your feature"

# Push feature branch
git push -u origin feature/your-feature-name
```

### Branch Naming Conventions

- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `hotfix/*` - Critical fixes for production
- `release/*` - Release preparation
- `docs/*` - Documentation updates

Examples:
```bash
git checkout -b feature/gpu-operator-integration
git checkout -b bugfix/kata-vm-boot-timeout
git checkout -b hotfix/critical-security-patch
git checkout -b docs/deployment-guide-updates
```

---

## Syncing with GitHub

### Daily Workflow

```bash
# 1. Start of day: Pull latest changes
git checkout develop
git pull origin develop

# 2. Create/switch to your working branch
git checkout -b feature/my-work
# or: git checkout feature/my-work

# 3. Make changes
# ... edit files ...

# 4. Stage and commit frequently
git add .
git commit -m "feat: implement XYZ functionality"

# 5. Push to GitHub (backup and collaboration)
git push origin feature/my-work

# 6. End of day: Push final changes
git add .
git commit -m "wip: end of day checkpoint"
git push origin feature/my-work

# 7. When feature is complete: Create Pull Request on GitHub
```

### Syncing with Upstream Changes

```bash
# While working on a feature branch, develop may have new commits

# 1. Commit or stash your current work
git add .
git commit -m "wip: checkpoint before sync"
# or: git stash

# 2. Switch to develop and pull
git checkout develop
git pull origin develop

# 3. Return to feature branch and rebase
git checkout feature/my-work
git rebase develop

# 4. If you stashed, restore your work
git stash pop

# 5. Push (may require force push after rebase)
git push origin feature/my-work --force-with-lease
```

### Handling Merge Conflicts

```bash
# If rebase encounters conflicts:

# 1. Git will pause and show conflicting files
git status

# 2. Open conflicting files and resolve
vim path/to/conflicted/file
# Look for conflict markers:
# <<<<<<< HEAD
# ... your changes ...
# =======
# ... their changes ...
# >>>>>>> commit-hash

# 3. After resolving, stage the files
git add path/to/resolved/file

# 4. Continue rebase
git rebase --continue

# If things go wrong, abort and start over
git rebase --abort
```

---

## Collaboration Workflow

### Pull Requests (PRs)

```bash
# 1. Push your feature branch
git push origin feature/my-feature

# 2. Create PR on GitHub
# Via web: GitHub will show "Compare & pull request" button
# Via CLI: gh pr create --base develop --head feature/my-feature

# 3. Add description
Title: feat: Add GPU passthrough support for Kata Containers

Description:
- Configured VFIO passthrough in Proxmox
- Updated Terraform to enable PCI devices
- Added GPU Operator Helm chart deployment
- Updated documentation

Closes #123

# 4. Request reviews
# Via web: Use "Reviewers" sidebar
# Via CLI: gh pr create --reviewer @teammate1,@teammate2

# 5. Address review feedback
# Make changes, commit, push
git add .
git commit -m "refactor: address PR feedback"
git push origin feature/my-feature

# 6. Merge (after approval)
# Via web: Click "Merge pull request"
# Via CLI: gh pr merge --squash
```

### Code Review Best Practices

```bash
# Review someone's PR locally

# 1. Fetch their branch
git fetch origin

# 2. Check out their branch
git checkout feature/their-feature

# 3. Test their changes
./deploy.py  # or run tests

# 4. Leave feedback on GitHub
gh pr review <PR_NUMBER> --comment

# 5. Approve or request changes
gh pr review <PR_NUMBER> --approve
# or: gh pr review <PR_NUMBER> --request-changes
```

---

## Security Best Practices

### Never Commit Secrets

```bash
# Check for accidentally staged secrets
git diff --staged | grep -i -E 'password|secret|key|token'

# If you accidentally committed a secret:

# 1. If not yet pushed:
git reset HEAD~1  # Undo last commit
# Remove secret from files
git add .
git commit -m "fix: remove accidentally committed secret"

# 2. If already pushed (MORE SERIOUS):
# Option A: Rewrite history (if no one has pulled)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/secret/file" \
  --prune-empty --tag-name-filter cat -- --all

git push origin --force --all

# Option B: Use BFG Repo-Cleaner
bfg --delete-files secret-file.txt

# 3. IMMEDIATELY rotate the compromised secret
# Change passwords, regenerate tokens, etc.
```

### Use Environment Variables

```bash
# Store secrets in environment variables, not in code

# Create .env file (ignored by .gitignore)
cat > .env << EOF
PM_API_TOKEN_ID=user@realm!token
PM_API_TOKEN_SECRET=your-secret
GITHUB_TOKEN=ghp_xxxxx
EOF

# Load in scripts
source .env

# Or use direnv (auto-loads .env)
sudo apt-get install direnv
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
```

### Sign Commits (Optional but Recommended)

```bash
# Generate GPG key
gpg --full-generate-key

# List keys and get key ID
gpg --list-secret-keys --keyid-format=long

# Configure Git to use GPG key
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true

# Add GPG key to GitHub
gpg --armor --export <KEY_ID>
# Copy output and add to: https://github.com/settings/keys

# Commits will now show "Verified" badge on GitHub
```

---

## Common Git Operations

### Viewing History

```bash
# View commit log
git log

# Condensed view
git log --oneline

# With graph
git log --oneline --graph --all

# Search commits
git log --grep="GPU"
git log --author="Your Name"

# View changes in specific commit
git show <commit-hash>

# View file history
git log --follow -- path/to/file
```

### Undoing Changes

```bash
# Undo uncommitted changes to a file
git checkout -- path/to/file

# Undo all uncommitted changes
git reset --hard

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1

# Revert a pushed commit (creates new commit)
git revert <commit-hash>
git push origin main
```

### Stashing Changes

```bash
# Save work in progress
git stash

# List stashes
git stash list

# Apply most recent stash
git stash apply

# Apply and remove stash
git stash pop

# Stash with message
git stash save "WIP: testing GPU passthrough"

# Apply specific stash
git stash apply stash@{2}

# Drop stash
git stash drop stash@{0}
```

### Tagging Releases

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release version 1.0.0"

# Push tag to GitHub
git push origin v1.0.0

# Push all tags
git push origin --tags

# List tags
git tag -l

# Checkout specific tag
git checkout v1.0.0

# Delete tag
git tag -d v1.0.0
git push origin --delete v1.0.0
```

---

## Troubleshooting

### Authentication Issues

```bash
# Test SSH connection
ssh -T git@github.com

# If fails, check SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github_ed25519

# Debug SSH
ssh -vT git@github.com

# Alternative: Use HTTPS with token
git remote set-url origin https://github.com/your-username/nexus-sandbox-framework.git
# Then use Personal Access Token as password
```

### Push Rejected

```bash
# If you get "Updates were rejected" error

# Option 1: Pull and merge
git pull origin main
git push origin main

# Option 2: Rebase
git pull --rebase origin main
git push origin main

# Option 3: Force push (DANGEROUS - only if you're sure)
git push origin main --force-with-lease
```

### Large Files

```bash
# If you accidentally committed large files

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
sudo apt-get install git-lfs
git lfs install

# Track large files
git lfs track "*.iso"
git lfs track "*.qcow2"

# Commit .gitattributes
git add .gitattributes
git commit -m "Configure Git LFS for large files"

# If file already committed, remove from history
git rm --cached large-file.iso
git commit -m "Remove large file from tracking"

# Add to LFS
git lfs track "*.iso"
git add large-file.iso
git commit -m "Track large file with Git LFS"
```

### Detached HEAD State

```bash
# If you see "You are in 'detached HEAD' state"

# Option 1: Create branch from current state
git checkout -b new-branch-name

# Option 2: Discard and return to main
git checkout main

# Option 3: Apply changes to existing branch
git checkout main
git cherry-pick <commit-hash>
```

---

## Automated Sync Script

Save this as `scripts/git-sync.sh`:

```bash
#!/bin/bash
# Automated Git sync script with error handling

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "🔄 Syncing branch: $BRANCH"

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
    echo "📝 Uncommitted changes detected. Committing..."
    git add .
    git commit -m "auto: sync changes $(date +'%Y-%m-%d %H:%M:%S')"
else
    echo "✅ No uncommitted changes"
fi

# Pull with rebase
echo "⬇️  Pulling latest changes..."
git pull --rebase origin "$BRANCH" || {
    echo "❌ Pull failed. Resolve conflicts and run again."
    exit 1
}

# Push
echo "⬆️  Pushing to GitHub..."
git push origin "$BRANCH"

echo "✅ Sync complete!"
```

Make it executable:
```bash
chmod +x scripts/git-sync.sh

# Run it
./scripts/git-sync.sh
```

---

## GitHub Actions CI/CD

Create `.github/workflows/ci.yaml`:

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install flake8 black mypy
      
      - name: Lint Python
        run: |
          flake8 .
          black --check .
          mypy .
      
      - name: Lint Terraform
        uses: hashicorp/setup-terraform@v2
      
      - run: |
          cd terraform
          terraform fmt -check
          terraform validate

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run tests
        run: |
          pytest tests/
```

---

**Congratulations!** Your Nexus Sandbox Framework is now under version control and synced with GitHub. Follow the branching strategy and pull request workflow for collaborative development.

**Next Steps:**
1. Invite collaborators to the repository
2. Set up branch protection rules on GitHub
3. Configure GitHub Actions for CI/CD
4. Document your deployment procedures

---

**Document Version:** 1.0  
**Last Updated:** 2025-11-03  
**Maintainer:** DevOps Team
