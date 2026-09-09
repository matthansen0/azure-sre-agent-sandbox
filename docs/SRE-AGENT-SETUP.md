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

The standard deployment creates daily health, daily RBAC/cost/network audit, and
hourly automation-health tasks. To create additional diagnosis tasks:

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
   -GitHubRepo "owner/repo" `
   -GitHubBranch "main"
```

When GitHub is enabled, the script preflights repository and branch access,
restricts agent instructions to that scope, redacts credentials from evidence,
requires review before issue creation, and prohibits pull-request writes. The
default deployment remains GitHub-free. This repository supplies infrastructure,
Kubernetes, automation, and runbook context. Connect the upstream
`Azure-Samples/aks-store-demo` repository or your fork when application
service-code RCA is required; the service source is not vendored here.

### Microsoft Learn MCP (Optional)

Microsoft Learn MCP is an independent, credential-free track. Enable it during
the standard deployment:

```powershell
.\scripts\deploy.ps1 `
   -Location eastus2 `
   -EnableMicrosoftLearnMcp
```

Or add it to an existing agent:

```powershell
.\scripts\configure-sre-agent.ps1 `
   -ResourceGroupName "rg-srelab-eastus2" `
   -EnableMicrosoftLearnMcp
```

Verify the optional track independently:

```powershell
.\scripts\verify-sre-agent-configuration.ps1 `
   -ResourceGroupName "rg-srelab-eastus2" `
   -RequireMicrosoftLearnMcp
```

Then ask: "Using Microsoft Learn, find the current Azure SRE Agent supported
regions and cite the documentation you used." A successful response includes a
Microsoft Learn connector tool call and source links.

The connector uses `https://learn.microsoft.com/api/mcp`, requires outbound
HTTPS on port 443 to `learn.microsoft.com`, and requires no inbound access or
customer credentials. Its setup failure is reported when enabled, but it never
blocks the core configuration when omitted. Remove it independently with:

```powershell
.\scripts\configure-sre-agent.ps1 `
   -ResourceGroupName "rg-srelab-eastus2" `
   -RemoveMicrosoftLearnMcp
```

The removal is idempotent and exits without changing knowledge, agents, other
connectors, response plans, or scheduled tasks. You can also delete it from
**Builder** > **Connectors**. Omitting `-EnableMicrosoftLearnMcp` prevents
creation but does not delete a connector that was enabled previously.

### Azure Monitor Automation Profile

The standard deployment creates the Azure Monitor automation profile; no extra
deployment flag or second command is required.

This deploys four symptom-focused alerts and the `ag-srelab` action group. The
deployment verifier requires those resources on every standard deployment.
The deployment also connects Azure Monitor as the incident platform and creates
an enabled Review-mode response plan that routes matching alerts to
`incident-handler`.

For the fastest deterministic demo, run `break-crash`. The product service exits
immediately, and the pod-failure and CrashLoop rules evaluate every minute. Use
`fix-all` afterward. `break-image`, `break-pending`, and `break-oom` also map to
the inventory-based rules. Azure Monitor log alerts do not support a 30-second
evaluation frequency; one minute is the minimum, and Container Insights
ingestion means the alert usually appears a few minutes after the break.

| Alert | Evaluation | Demo trigger |
|-------|------------|--------------|
| Pod restart spike | 1 minute | `break-crash`, `break-oom`, or `break-probe` |
| HTTP 5xx spike | 1 minute | Any request that produces a 5xx access-log entry |
| Failed, pending, or waiting pod | 1 minute | `break-crash`, `break-image`, or `break-pending` |
| CrashLoop, OOM, image-pull, or startup error | 1 minute | `break-crash`, `break-oom`, or `break-image` |

`break-network`, `break-service`, and `break-mongodb` demonstrate dependency or
connectivity failures and are not guaranteed to match these pod-symptom rules.

Inspect, pause, resume, or clean up the profile with:

```powershell
.\scripts\manage-azure-monitor-profile.ps1 -ResourceGroupName "rg-srelab-eastus2"
.\scripts\manage-azure-monitor-profile.ps1 -ResourceGroupName "rg-srelab-eastus2" -Pause
.\scripts\manage-azure-monitor-profile.ps1 -ResourceGroupName "rg-srelab-eastus2" -Resume
.\scripts\manage-azure-monitor-profile.ps1 -ResourceGroupName "rg-srelab-eastus2" -RunNow -TaskName hourly-automation-health
.\scripts\manage-azure-monitor-profile.ps1 -ResourceGroupName "rg-srelab-eastus2" -Cleanup -ConfirmCleanup
```

Pass `-WorkloadName` when the lab was deployed with a non-default workload name.

`-RunNow` reports exit code `2` when the current SRE Agent API does not expose
an immediate scheduled-task endpoint.

### Grafana Dashboard

Managed Grafana is linked to the Azure Monitor Workspace and receives the
`SRE Lab - AKS Overview` dashboard during deployment. Open the Grafana URL from
the deployment output to view pod readiness, workload CPU, pod restarts, and
node memory. Dashboard provisioning uses Entra authentication with the
`https://dashboard.azure.com` audience; API keys remain disabled.

Container Insights is verified separately by checking ready `ama-logs` pods,
the `ContainerInsightsExtension` DCR association, and recent `ContainerLogV2`
and `KubePodInventory` records. The current profile intentionally uses
`ContainerLogV2`; an empty legacy `ContainerLog` table is therefore expected.
On a fresh cluster, initial inventory ingestion can take up to 20 minutes; the
deployment configures Grafana and SRE Agent before waiting on that final gate.

### Governance Profile

The local governance contract in `sre-config/governance/review-profile.yaml` is
disabled by default and keeps Review mode, explicit approval for writes, secret
redaction, and `pets`/demo-resource-group scope as the intended policy. Validate
it with:

```powershell
.\scripts\validate-sre-agent-governance.py
.\scripts\report-sre-agent-capabilities.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

The report uses read-only calls and labels unsupported hooks and broad RBAC
boundaries as unknown or unenforceable; it does not claim prompt text alone can
enforce them.

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
| **daily-rbac-cost-network-audit** | Read-only governance audit daily at 08:30 UTC |
| **hourly-automation-health** | Read-only AKS and Azure Monitor health check every hour |
| **AKS Pod Failure Handler** | Enabled P1/P2 `Pet Store` response plan routed to incident-handler in Review mode |

### Post-Configuration: Authorize Outlook

The Outlook connector enables the `SendOutlookEmail` tool so agents can email you incident analysis and health reports. After the script runs:

1. Open [sre.azure.com](https://sre.azure.com) → your agent → **Settings** → **Connectors**
2. Find the **Outlook** connector and click **Authorize**
3. Sign in with the account that should send incident emails
4. Once authorized, agents will email findings for incidents and scheduled health checks

### Verify Incident Response

The standard configuration connects Azure Monitor as the incident platform and
creates `AKS Pod Failure Handler` automatically. In the SRE Agent portal, open
**Builder** → **Incident response plans** and verify that the plan is **On**, uses
`incident-handler`, matches P1/P2 alerts containing `Pet Store`, and runs in
**Review** mode.

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
