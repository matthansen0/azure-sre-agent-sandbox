# Azure SRE Agent Setup Guide

This guide walks you through setting up Azure SRE Agent to work with the demo lab environment.

## What is Azure SRE Agent?

Azure SRE Agent (Preview) is an AI-powered site reliability engineering automation tool that helps you:

- **Diagnose issues** in Azure resources using natural language
- **Investigate incidents** across AKS, App Service, Container Apps, and more
- **Run remediation actions** to fix common problems
- **Create scheduled tasks** for proactive monitoring
- **Integrate with external tools** like Grafana, PagerDuty, and ServiceNow

## Prerequisites

Before creating an SRE Agent, ensure you have:

- ✅ Deployed the demo lab infrastructure (`scripts/deploy.ps1`)
- ✅ Access to a supported Azure region (East US 2, Sweden Central, Australia East)
- ✅ `Microsoft.Authorization/roleAssignments/write` permission
- ✅ Firewall allows access to `*.azuresre.ai`

## Step 1: Create an SRE Agent

### Automated via Bicep (Default)

The SRE Agent is deployed automatically as part of `scripts/deploy.ps1` using the `Microsoft.App/agents@2025-05-01-preview` resource type. The deployment:

- Creates the SRE Agent resource
- Creates a user-assigned managed identity
- Assigns Log Analytics Reader, Reader, and Contributor roles
- Grants the deploying user the **SRE Agent Administrator** role

To skip SRE Agent deployment, set `deploySreAgent = false` in `infra/bicep/main.bicepparam`.

### Via Azure Portal (Alternative)

You can also create the agent manually:

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Search for "SRE Agent" in the search bar
3. Click **Create SRE Agent**
4. Configure:
   - **Subscription**: Select your subscription
   - **Resource Group**: Create new or use existing (separate from demo resources)
   - **Name**: `sre-agent-demo` (or your preferred name)
   - **Region**: Must match one of: `East US 2`, `Sweden Central`, `Australia East`

5. Click **Review + Create**, then **Create**

### What Gets Created

When you create an SRE Agent, Azure automatically provisions:
- Application Insights instance
- Log Analytics Workspace
- Managed Identity for the agent

## Step 2: Configure Agent Permissions

The SRE Agent needs access to your Azure resources to diagnose and **remediate** issues.

> **Note**: When deployed via Bicep (default), the agent's managed identity is automatically assigned Reader, Contributor, and Log Analytics Reader roles on the deployment resource group. The script below grants additional AKS-specific roles.

### Grant Access to Demo Resources

1. Get the SRE Agent's managed identity Object ID from the portal
2. Run the RBAC configuration script:

```powershell
.\scripts\configure-rbac.ps1 `
    -ResourceGroupName "rg-srelab-eastus2" `
    -SreAgentPrincipalId "<sre-agent-object-id>"
```

### Permissions Granted to SRE Agent

The script assigns these roles to enable both **diagnosis AND remediation**:

| Scope | Role | What It Allows |
|-------|------|----------------|
| **Resource Group** | Contributor | Read/write access to all resources |
| **Subscription** | Reader | Broader context for diagnosis |
| **AKS Cluster** | AKS Cluster Admin Role | kubectl access to cluster |
| **AKS Cluster** | AKS RBAC Cluster Admin | Full Kubernetes RBAC permissions |
| **AKS Cluster** | AKS Contributor Role | Scale nodes, update cluster config |
| **Log Analytics** | Log Analytics Contributor | Query and analyze logs |
| **Key Vault** | Key Vault Secrets Officer | Manage secrets |
| **Container Registry** | AcrPush | Push/pull container images |

> **Note**: These are **write permissions** that allow SRE Agent to take actions like:
> - Restart pods, scale deployments, delete stuck resources
> - Query and analyze logs
> - Access/update Key Vault secrets
> - Push/pull container images

### SRE Agent User Roles

Assign these roles to **users** who will interact with SRE Agent:

| Role | Description |
|------|-------------|
| **SRE Agent Admin** | Full access - create agents, manage settings, assign roles |
| **SRE Agent Standard User** | Chat with agent, run diagnostics and remediation |
| **SRE Agent Reader** | View-only access to agent and chat history |

Assign roles to users via Azure Portal:
1. Navigate to your SRE Agent resource
2. Go to **Access control (IAM)**
3. Click **Add role assignment**
4. Select the appropriate role and assign to users/groups

## Step 3: Connect Resources to SRE Agent

### Connect AKS Cluster

1. In the SRE Agent portal, go to **Connected resources**
2. Click **Add resource**
3. Select your AKS cluster: `aks-srelab`
4. Review permissions and confirm

### Connect Other Resources

You can also connect:
- Log Analytics Workspace
- Application Insights
- Azure Monitor Workspace (Prometheus)
- Managed Grafana

## Step 4: Start Diagnosing!

Once connected, you can interact with SRE Agent using natural language:

### Starter Prompts for AKS

- "Show me the health status of my AKS cluster"
- "Why are pods crashing in the pets namespace?"
- "What's causing high CPU usage on my nodes?"
- "List all pods that have restarted in the last hour"
- "Diagnose the CrashLoopBackOff error for the order-service pod"

### Starter Prompts for General Diagnosis

- "What issues are affecting my application right now?"
- "Show me errors from the last 24 hours"
- "Analyze the performance metrics and identify bottlenecks"
- "What changes were made to my resources recently?"

## Using SRE Agent with Demo Scenarios

### Example: Diagnosing OOMKilled Pods

1. **Break the application:**
   ```bash
   kubectl apply -f k8s/scenarios/oom-killed.yaml
   ```

2. **Wait for pods to crash** (1-2 minutes)

3. **Ask SRE Agent:**
   > "I'm seeing pods crash in the pets namespace. Can you diagnose the issue?"

4. **Expected Response:**
   - SRE Agent will identify OOMKilled events
   - Recommend increasing memory limits
   - May offer to create a remediation action

5. **Fix the issue:**
   ```bash
   kubectl apply -f k8s/base/application.yaml
   ```

### Example: Diagnosing Network Issues

1. **Apply network policy:**
   ```bash
   kubectl apply -f k8s/scenarios/network-block.yaml
   ```

2. **Ask SRE Agent:**
   > "The order-service seems to be unreachable. What's blocking traffic?"

3. **Expected Response:**
   - Identifies blocking network policy
   - Shows affected pods
   - Recommends removing or modifying the policy

## Advanced Features

### Scheduled Tasks

Create automated diagnosis tasks:

1. Go to **Subagent builder** in SRE Agent
2. Click **Create scheduled task**
3. Configure:
   - **Name**: "Daily AKS Health Check"
   - **Schedule**: "Every day at 9 AM" (or use cron: `0 9 * * *`)
   - **Prompt**: "Check the health of my AKS cluster and report any issues"

### Incident Triggers

Configure automatic diagnosis when incidents are created:

1. Go to **Subagent builder** > **Incident triggers**
2. Connect to your incident management system (PagerDuty, ServiceNow)
3. Define trigger conditions and diagnosis prompts

### MCP Integrations

Connect external tools via Model Context Protocol (MCP):

- **Grafana**: Query dashboards and metrics
- **Prometheus**: Access custom metrics
- **GitHub/Azure DevOps**: Correlate with code changes
- **ServiceNow/PagerDuty**: Bi-directional incident management

## Step 5: Configure Knowledge Base & Custom Agents

After infrastructure deployment, configure the agent's knowledge base, custom agents, connectors, and scheduled tasks using the automated configuration script. This uses the **dataplane v2 API** (`{agentEndpoint}/api/v2/extendedAgent/`).

### Automated (Recommended)

The `deploy.ps1` script automatically calls `configure-sre-agent.ps1` after a successful deployment. To run it manually:

```powershell
# Basic configuration (knowledge base + agents + connectors + scheduled tasks)
.\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2"

# With GitHub integration
.\scripts\configure-sre-agent.ps1 `
    -ResourceGroupName "rg-srelab-eastus2" `
    -GitHubPat $env:GITHUB_PAT `
    -GitHubRepo "owner/repo"
```

### What Gets Configured

| Component | Description |
|-----------|-------------|
| **Knowledge Base** | Runbooks for pod failures, networking, dependencies, resource exhaustion, app architecture |
| **incident-handler** | Custom agent that investigates alerts using runbooks, log analysis, and emails results |
| **cluster-health-monitor** | Custom agent for proactive health checks with email reports |
| **code-analyzer** | (GitHub only) Custom agent for source code root cause analysis |
| **Azure Monitor** | Connector for incident detection and alerting |
| **Outlook** | Connector for email delivery (requires portal authorization) |
| **GitHub MCP** | (Optional) Connector for searching code and creating issues |
| **daily-health-check** | Scheduled task that runs cluster-health-monitor daily at 08:00 UTC |
| **aks-pod-failure-handler** | Incident filter routing pod alerts to incident-handler (API or portal) |

> **Note:** Incident response plans must be created manually in the [SRE Agent portal](https://sre.azure.com) — the script prints guidance for this.

### Post-Configuration: Authorize Outlook

The Outlook connector enables the `SendOutlookEmail` tool so agents can email you incident analysis and health reports. After the script runs:

1. Open [sre.azure.com](https://sre.azure.com) → your agent → **Settings** → **Connectors**
2. Find the **Outlook** connector and click **Authorize**
3. Sign in with the account that should send incident emails
4. Once authorized, agents will email findings for incidents and scheduled health checks

### Post-Configuration: Create Incident Response Plan

The script attempts to create an incident filter via the API. If it fails (the API may not support creation yet), create one in the portal:

1. Open [sre.azure.com](https://sre.azure.com) → your agent → **Builder** → **Incident response plans**
2. Click **New incident response plan**
3. Configure:
   - **Name:** AKS Pod Failure Handler
   - **Severity:** Sev1, Sev2, Sev3
   - **Title contains:** pod
   - **Response agent:** incident-handler
   - **Agent autonomy:** Review
4. Save — incidents matching the filter will automatically trigger the subagent

### Partial Re-runs

If part of the configuration fails, you can skip completed steps:

```powershell
# Skip knowledge base, only re-create agents and connectors
.\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2" -SkipKnowledgeBase

# Only upload knowledge base
.\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2" -SkipAgents -SkipConnectors -SkipScheduledTasks
```

### Custom Runbooks

To add your own runbooks:

1. Create a `.md` file in `sre-config/knowledge-base/`
2. Re-run the configuration script:
   ```powershell
   .\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2" -SkipAgents -SkipConnectors -SkipScheduledTasks
   ```
3. The script auto-discovers all `*.md` files in the knowledge-base directory

## Troubleshooting SRE Agent

### Agent Can't Access AKS Resources

**Symptom:** SRE Agent says it can't read namespaces or pods

**Cause:** AKS cluster has restricted inbound network access

**Solution:** Ensure the cluster is not a fully private cluster. SRE Agent needs network access to query Kubernetes objects.

### Permission Errors

**Symptom:** "Insufficient permissions" errors

**Solution:**
1. Verify the SRE Agent's managed identity has Contributor role on the resource group
2. Ensure you have `Microsoft.Authorization/roleAssignments/write` permission
3. Run the RBAC configuration script again

### Firewall Blocking

**Symptom:** Agent can't connect or times out

**Solution:** Ensure `*.azuresre.ai` is allowed through your firewall/proxy

## Cost Information

SRE Agent billing is based on Azure AI Units (AAU):

| Component | Cost |
|-----------|------|
| Fixed agent cost | ~$292/month (4 AAU × 730 hours × $0.10) |
| Execution costs | Variable based on usage |

See [docs/COSTS.md](COSTS.md) for full cost breakdown including AKS and other resources.

## Additional Resources

- [Azure SRE Agent Documentation](https://learn.microsoft.com/azure/sre-agent/)
- [SRE Agent FAQs](https://learn.microsoft.com/azure/sre-agent/faq)
- [Supported Azure Services](https://learn.microsoft.com/azure/sre-agent/overview#supported-services)
