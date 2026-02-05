# Azure SRE Agent Demo Lab 🔧

A fully automated Azure environment for demonstrating **Azure SRE Agent** capabilities. Deploy a breakable multi-service application on AKS and let SRE Agent diagnose and fix the issues!

## 🎯 What This Lab Provides

- **Azure Kubernetes Service (AKS)** with a multi-pod e-commerce demo application
- **8 breakable scenarios** for demonstrating SRE Agent diagnosis
- **Full observability stack**: Log Analytics, Application Insights, Managed Grafana
- **Ready-to-use scripts** for deployment and teardown
- **Dev container** for consistent development experience

## 🚀 Quick Start

### Prerequisites

- Azure subscription with Owner/Contributor access
- Azure region supporting SRE Agent: `East US 2`, `Sweden Central`, or `Australia East`
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
- [VS Code](https://code.visualstudio.com/) with [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (optional but recommended)

### Deploy

```powershell
# 1. Login to Azure
az login --use-device-code

# 2. Deploy infrastructure (~15-25 minutes)
.\scripts\deploy.ps1 -Location eastus2 -Yes
```

> 💡 **Tip**: Type `menu` in the terminal to see all available commands including break scenarios, fix commands, and kubectl shortcuts.

### Create SRE Agent (Portal Only)

> ⚠️ **Note**: Azure SRE Agent does not support programmatic deployment yet. You must create it manually in the Azure Portal.

1. Go to the [SRE Agent Portal](https://aka.ms/sreagent/portal)
2. Click **Create** and select the deployed resource group (e.g., `rg-srelab-eastus2`)
3. Configure it to monitor the AKS cluster

### Validate Deployment

After deployment, verify everything is healthy:

```powershell
.\scripts\validate-deployment.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

## 💥 Breaking Things (The Fun Part!)

Once deployed, you can break the application using shortcut commands:

```bash
# Out of Memory scenario
break-oom

# CrashLoopBackOff
break-crash

# Image Pull failure
break-image

# See all scenarios
menu
```

To restore:
```bash
fix-all
```

## 🤖 Using SRE Agent

After deployment:

1. **Create an SRE Agent** in Azure Portal (if not already done)
2. **Connect it to your resources** (AKS, Log Analytics)
3. **Ask it to diagnose**:
   - "Why are pods crashing in the pets namespace?"
   - "What's causing high CPU usage?"
   - "Diagnose the CrashLoopBackOff error"

See [docs/SRE-AGENT-SETUP.md](docs/SRE-AGENT-SETUP.md) for detailed instructions.

## 📁 Repository Structure

```
├── infra/bicep/           # Bicep IaC templates
│   ├── main.bicep         # Main deployment orchestration
│   ├── main.bicepparam    # Parameters file
│   └── modules/           # Modular Bicep templates
├── k8s/
│   ├── base/              # Healthy application manifests
│   └── scenarios/         # Breakable failure scenarios
├── scripts/               # Deployment and management scripts
├── docs/                  # Documentation
│   ├── SRE-AGENT-SETUP.md # SRE Agent configuration guide
│   ├── BREAKABLE-SCENARIOS.md # Scenario details
│   └── COSTS.md           # Cost estimates
└── .devcontainer/         # Dev container configuration
```

## 💰 Cost Estimate

| Configuration | Monthly Cost |
|--------------|--------------|
| Default deployment | ~$650-850 |
| + SRE Agent | ~$950-1,150 |

See [docs/COSTS.md](docs/COSTS.md) for detailed breakdown and optimization tips.

## 🔧 Available Scenarios

| Scenario | Description | SRE Agent Diagnoses |
|----------|-------------|---------------------|
| OOMKilled | Memory limit too low | Memory exhaustion, limit recommendations |
| CrashLoop | App exits immediately | Exit codes, log analysis |
| ImagePullBackOff | Invalid image reference | Registry/image troubleshooting |
| HighCPU | Resource exhaustion | Performance analysis |
| PendingPods | Insufficient cluster resources | Scheduling analysis |
| ProbeFailure | Failing health checks | Probe configuration |
| NetworkBlock | NetworkPolicy blocking traffic | Connectivity analysis |
| MissingConfig | Non-existent ConfigMap | Configuration troubleshooting |

## 🛠️ Commands Reference

### Deployment Scripts (PowerShell)

> **Note**: These PowerShell scripts deploy to Azure and can be run from the dev container, locally on Windows, or on any system with PowerShell Core installed.

| Command | Description |
|---------|-------------|
| `.\scripts\deploy.ps1 -Location eastus2` | Deploy all infrastructure to Azure |
| `.\scripts\deploy.ps1 -WhatIf` | Preview what would be deployed |
| `.\scripts\validate-deployment.ps1 -ResourceGroupName <rg>` | Verify resources and app are healthy |
| `.\scripts\destroy.ps1 -ResourceGroupName <rg>` | Tear down all infrastructure |

**Deploy script parameters:**
- `-Location`: Azure region (`eastus2`, `swedencentral`, `australiaeast`) - Default: `eastus2`
- `-WorkloadName`: Resource prefix - Default: `srelab`
- `-SkipRbac`: Skip RBAC assignments if subscription policies block them
- `-WhatIf`: Preview deployment without making changes
- `-Yes`: Skip confirmation prompts (non-interactive mode)

### Kubernetes Commands (kubectl)

| Command | Description |
|---------|-------------|
| `kubectl apply -f k8s/base/application.yaml` | Deploy healthy application |
| `kubectl apply -f k8s/scenarios/<scenario>.yaml` | Apply a break scenario |
| `kubectl get pods -n pets` | Check pod status |
| `kubectl get events -n pets --sort-by='.lastTimestamp'` | View recent events |

## 📚 Documentation

- [SRE Agent Setup Guide](docs/SRE-AGENT-SETUP.md)
- [Breakable Scenarios Guide](docs/BREAKABLE-SCENARIOS.md)
- [Cost Estimation](docs/COSTS.md)

## 🤝 Contributing

Contributions welcome! Please read our contributing guidelines and submit PRs.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

**⚠️ Important Notes:**

- SRE Agent is currently in **Preview**
- Only available in **East US 2**, **Sweden Central**, and **Australia East**
- AKS cluster must **NOT** be a private cluster for SRE Agent to access
- Firewall must allow `*.azuresre.ai`