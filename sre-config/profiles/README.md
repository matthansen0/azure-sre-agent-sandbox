# SRE Agent Capability Profiles

Profiles keep the sandbox demo paths explicit and independently verifiable.

| Profile | Enablement | Demonstrates |
|---|---|---|
| `core` | Default | AKS diagnosis, knowledge, Azure Monitor connector, and Review-mode remediation |
| `automation` | `scripts/deploy.ps1 -EnableAutomation` | Alerts, action group, incident routing, and scheduled health checks |
| `developer` | Configure GitHub credentials explicitly | Infrastructure/runbook RCA and confirmed issue creation for this repository |
| `learn` | Configure the Microsoft Learn MCP connector explicitly | Current Azure and SRE documentation lookup |

The application service source is not part of this repository. The developer
profile therefore analyzes infrastructure, Kubernetes, scripts, runbooks, and
SRE configuration. A separate application-source repository is required for
service-code RCA.

Every optional profile must remain disableable and must not prevent the core
deployment from completing. Credentials are supplied through environment
variables or an authorized portal connection; they are never committed.

## Profile commands

```powershell
# Core diagnosis path
.\scripts\configure-sre-agent.ps1 -ResourceGroupName <resource-group> -Profile core

# Azure Monitor scheduled health check
.\scripts\configure-sre-agent.ps1 -ResourceGroupName <resource-group> -Profile automation

# Infrastructure and runbook RCA for this repository
.\scripts\configure-sre-agent.ps1 -ResourceGroupName <resource-group> -Profile developer -GitHubPat $env:GITHUB_PAT -GitHubRepo matthansen0/azure-sre-agent-sandbox

# Microsoft Learn documentation lookup
.\scripts\configure-sre-agent.ps1 -ResourceGroupName <resource-group> -Profile learn

# Email reporting (requires portal authorization)
.\scripts\configure-sre-agent.ps1 -ResourceGroupName <resource-group> -Profile communications
```