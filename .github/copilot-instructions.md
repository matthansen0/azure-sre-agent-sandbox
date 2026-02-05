# Azure SRE Agent Demo Lab - Copilot Instructions

## Project Overview

This repository contains a fully automated Azure SRE Agent demo lab environment. It deploys:

- **Azure Kubernetes Service (AKS)** with a multi-pod sample e-commerce application
- **Azure Container Registry** for container images
- **Azure Key Vault** for secrets management
- **Observability stack**: Log Analytics, Application Insights, Managed Grafana
- **Breakable scenarios** for demonstrating SRE Agent diagnosis capabilities

The app uses in-cluster MongoDB and RabbitMQ with Azure Managed Disk storage.

## Technology Stack

- **Infrastructure as Code**: Bicep (modular templates in `infra/bicep/`)
- **Container Orchestration**: Kubernetes (manifests in `k8s/`)
- **Scripting**: PowerShell (deployment scripts in `scripts/`)
- **Dev Environment**: Dev Containers with Azure CLI, kubectl, azd

## Key Directories

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
└── .devcontainer/         # Dev container configuration
```

## Azure SRE Agent Context

Azure SRE Agent is a Preview feature that provides AI-powered site reliability engineering automation:

- **Supported Regions**: East US 2, Sweden Central, Australia East
- **Firewall Requirement**: Allow `*.azuresre.ai`
- **RBAC Roles**: SRE Agent Admin, Standard User, Reader
- **Key Feature**: Natural language diagnosis and remediation

### SRE Agent Starter Prompts

For AKS issues:
- "Why are pods crashing in the pets namespace?"
- "Show me the health status of my AKS cluster"
- "What's causing high CPU usage on my nodes?"

For general diagnosis:
- "What issues are affecting my application?"
- "Analyze performance metrics and identify bottlenecks"

## Breakable Scenarios

Located in `k8s/scenarios/`:

| File | Issue | SRE Agent Can Diagnose |
|------|-------|----------------------|
| `oom-killed.yaml` | Memory exhaustion | OOMKilled events, memory limits |
| `crash-loop.yaml` | Startup failure | CrashLoopBackOff, exit codes |
| `image-pull-backoff.yaml` | Bad image | Registry/image issues |
| `high-cpu.yaml` | Resource exhaustion | CPU contention |
| `pending-pods.yaml` | Insufficient resources | Scheduling issues |
| `probe-failure.yaml` | Health check failure | Probe configuration |
| `network-block.yaml` | Connectivity issues | Network policies |
| `missing-config.yaml` | ConfigMap reference | Configuration issues |

## Common Operations

### Dev Container Commands
Type `menu` in the terminal to see all available commands. Key shortcuts:
- `deploy` - Deploy infrastructure
- `destroy` - Tear down infrastructure  
- `site` - Show store front URL
- `kgp` - Get pods in pets namespace
- `break-oom`, `break-crash`, `break-image` - Apply scenarios
- `fix-all` - Restore healthy state

### Deploy Infrastructure
```powershell
.\scripts\deploy.ps1 -Location eastus2 -Yes
```

### Create SRE Agent (Portal Only)
Azure SRE Agent does not support programmatic deployment. Create manually:
1. Go to: https://aka.ms/sreagent/portal
2. Click "Create" and select the resource group (e.g., `rg-srelab-eastus2`)

### Apply Breakable Scenario
```bash
kubectl apply -f k8s/scenarios/oom-killed.yaml
```

### Restore Healthy State
```bash
kubectl apply -f k8s/base/application.yaml
```

### Destroy Infrastructure
```powershell
.\scripts\destroy.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

## Important Constraints

1. **SRE Agent Regions**: Only deploy to eastus2, swedencentral, or australiaeast
2. **AKS Networking**: Must NOT be private cluster for SRE Agent access
3. **Authentication**: Use device code auth in dev containers (`az login --use-device-code`)
4. **RBAC**: Some role assignments may fail due to subscription policies - use scripts
5. **No SAS Tokens**: Use Workload Identity instead of connection strings where possible

## Cost Considerations

- **Full deployment**: ~$650-850/month
- **With SRE Agent**: ~$950-1,150/month
- **See**: `docs/COSTS.md` for detailed breakdown

## When Helping with This Project

1. **For Bicep changes**: Follow best practices in `infra/bicep/` patterns
2. **For K8s manifests**: Use namespace `pets`, label with `sre-demo: breakable`
3. **For scripts**: Use PowerShell, include error handling, support `-WhatIf`
4. **For docs**: Keep formatting consistent, include code examples
5. **For new scenarios**: Add to `k8s/scenarios/` and update `docs/BREAKABLE-SCENARIOS.md`
