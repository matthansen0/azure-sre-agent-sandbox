# Azure SRE Agent Demo Lab — Hands-On Guide

A step-by-step walkthrough for deploying the demo environment, exploring the healthy application, breaking things, and watching Azure SRE Agent diagnose and fix them.

**Time estimate:** 60–90 minutes for all three labs (or pick just one)

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1: Deploy and Explore](#part-1-deploy-and-explore)
- [Part 2: Verify the Healthy Application](#part-2-verify-the-healthy-application)
- [Part 3: Explore SRE Agent (Baseline)](#part-3-explore-sre-agent-baseline)
- [Lab 1: OOMKilled — The Classic Pod Crash](#lab-1-oomkilled--the-classic-pod-crash)
- [Lab 2: MongoDB Down — Cascading Dependency Failure](#lab-2-mongodb-down--cascading-dependency-failure)
- [Lab 3: Service Mismatch — The Silent Killer](#lab-3-service-mismatch--the-silent-killer)
- [Bonus: Automated Incident Response with Outlook](#bonus-automated-incident-response-with-outlook)
- [Explore More Scenarios](#explore-more-scenarios)
- [Cleanup](#cleanup)

---

## Prerequisites

Before starting, make sure you have:

- [ ] Azure subscription with Owner or Contributor access
- [ ] Access to a supported SRE Agent region: **East US 2**, **Sweden Central**, or **Australia East**
- [ ] VS Code with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension (recommended), or Azure CLI + kubectl installed locally
- [ ] Firewall allows access to `*.azuresre.ai`

### Open the Dev Container

1. Clone the repository and open it in VS Code
2. When prompted, click **Reopen in Container** (or use the command palette: `Dev Containers: Reopen in Container`)
3. Wait for the container to build — it installs Azure CLI, kubectl, Helm, PowerShell, and helpful aliases
4. Type `menu` in the terminal to see all available commands

---

## Part 1: Deploy and Explore

### 1.1 — Log in to Azure

```powershell
az login --use-device-code
```

Follow the device code prompt to authenticate. Verify you're on the right subscription:

```powershell
az account show --query '{Name:name, Id:id}' -o table
```

### 1.2 — Deploy the Infrastructure

This creates AKS, Container Registry, Key Vault, Log Analytics, Application Insights, Managed Grafana, and the SRE Agent — all via Bicep.

```powershell
.\scripts\deploy.ps1 -Location eastus2 -Yes
```

Deployment takes approximately 15–25 minutes. While it runs, the script will:

1. Deploy all Azure infrastructure via Bicep
2. Get AKS credentials and deploy the e-commerce application
3. Configure the SRE Agent with knowledge base, custom agents, connectors, and scheduled tasks

> **Cost note:** The full environment costs ~$32–38/day with SRE Agent enabled. See [COSTS.md](COSTS.md) for a breakdown.

### 1.3 — Confirm Everything Is Running

Once the deployment completes, verify the pods:

```bash
kgp
```

You should see all pods in `Running` status with `1/1` ready:

```
NAME                                READY   STATUS    RESTARTS   AGE
mongodb-7f5f5c5d4-xxxxx            1/1     Running   0          5m
order-service-6d8f7b9c5-xxxxx      1/1     Running   0          5m
makeline-service-5f4d6e8b7-xxxxx   1/1     Running   0          5m
product-service-4c3d5f7a6-xxxxx    1/1     Running   0          5m
rabbitmq-3b2c4d6e5-xxxxx           1/1     Running   0          5m
store-admin-2a1b3c5d4-xxxxx        1/1     Running   0          5m
store-front-1z0a2b4c3-xxxxx        1/1     Running   0          5m
virtual-customer-9x8w7v6u-xxxxx    1/1     Running   0          5m
virtual-worker-8w7v6u5t-xxxxx      1/1     Running   0          5m
```

> **Tip:** If any pods aren't ready yet, wait a minute and run `kgp` again. The first pull of container images can take a moment.

---

## Part 2: Verify the Healthy Application

Before breaking anything, confirm the application is working end-to-end.

### 2.1 — Open the Store Front

Get the external URL:

```bash
site
```

This prints the Store Front URL (e.g., `http://20.x.x.x`). Open it in your browser — you should see the pet store with products listed.

### 2.2 — Walk Through the Architecture

The application is a multi-service e-commerce platform:

| Service | Language | Role |
|---------|----------|------|
| **store-front** | Vue.js | Customer-facing website |
| **store-admin** | Vue.js | Admin panel |
| **order-service** | Node.js | Receives and queues orders via RabbitMQ |
| **product-service** | Rust | Product catalog API |
| **makeline-service** | Go | Fulfills orders from queue, writes to MongoDB |
| **ai-service** | Python | AI product recommendations |
| **virtual-customer** | Simulated | Generates load by placing orders |
| **virtual-worker** | Simulated | Processes queued orders |
| **RabbitMQ** | — | Message queue between order and makeline |
| **MongoDB** | — | Persistent order storage |

### 2.3 — Check Services and Endpoints

```bash
kgs
```

Verify all services have endpoints and the `store-front` has an external IP.

---

## Part 3: Explore SRE Agent (Baseline)

Open the SRE Agent portal:

```bash
sre-agent
```

Or navigate directly to [sre.azure.com](https://sre.azure.com).

### 3.1 — Healthy Baseline Prompts

Before introducing failures, ask the agent to confirm the cluster is healthy. Try these prompts:

| Prompt | What It Demonstrates |
|--------|----------------------|
| "Show me the health status of my AKS cluster" | Cluster overview, node health |
| "Are there any issues in the pets namespace?" | Baseline — everything should be green |
| "What workloads are running in pets?" | Inventory of deployments |
| "Show me resource utilization across my pods" | CPU/memory usage |

Take note of the healthy state — you'll compare this to the broken state in each lab.

### 3.2 — Verify Agent Configuration

In the SRE Agent portal, check:

- **Builder > Agent Canvas** — you should see `incident-handler` and `cluster-health-monitor` custom agents
- **Knowledge Files** — runbooks for pod failures, networking, dependencies, etc.
- **Connectors** — Azure Monitor (and optionally Outlook, GitHub)

---

## Lab 1: OOMKilled — The Classic Pod Crash

**Difficulty:** Beginner  
**What you'll learn:** How SRE Agent diagnoses memory exhaustion and recommends resource limits  
**Services affected:** order-service

### Step 1 — Break It

```bash
break-oom
```

This redeploys order-service with an absurdly low memory limit (16Mi). The container starts, immediately consumes more memory than allowed, and gets killed by the OOM Killer. Kubernetes restarts it, and the cycle repeats.

### Step 2 — Observe the Failure

Watch the pods cycle through crashes:

```bash
kgp
```

Within 30–60 seconds you should see:

```
order-service-xxxxx   0/1   OOMKilled   3   2m
```

For more detail:

```bash
kubectl describe pod -l app=order-service -n pets | grep -A 5 "Last State"
```

You'll see `Reason: OOMKilled` and `Exit Code: 137`.

### Step 3 — Ask SRE Agent to Diagnose

Go to the SRE Agent portal and try these prompts, progressing from open-ended to specific:

1. **Open-ended:** _"Something seems wrong with my order-service. Can you take a look?"_
2. **Direct:** _"Why is the order-service pod restarting repeatedly?"_
3. **Specific:** _"I see OOMKilled events in the pets namespace. What's going on?"_

**What to look for in the response:**
- SRE Agent identifies the `OOMKilled` status
- It reads the current memory limit (16Mi) and explains it's too low
- It recommends increasing the memory limit (typically to 128–256Mi)
- It may offer to apply the fix directly

### Step 4 — Ask SRE Agent to Remediate

Try:

- _"What memory limits should I set for order-service?"_
- _"Can you increase the memory limit for order-service to 256Mi?"_

SRE Agent has write access (Contributor + AKS Cluster Admin) and can patch the deployment directly.

### Step 5 — Fix It (Manual)

If you prefer to fix it yourself or want to restore the full healthy state:

```bash
fix-all
```

### Step 6 — Verify Recovery

```bash
kgp
```

All pods should return to `Running` 1/1. Open the store front again to confirm orders work.

---

## Lab 2: MongoDB Down — Cascading Dependency Failure

**Difficulty:** Intermediate  
**What you'll learn:** How SRE Agent traces dependency chains and identifies the root cause of cascading failures  
**Services affected:** MongoDB → makeline-service → order fulfillment

This is the most realistic scenario. It tests whether SRE Agent can look past the immediate symptom (makeline-service failing) to find the actual root cause (MongoDB is offline).

### Step 1 — Break It

```bash
break-mongodb
```

This scales the MongoDB deployment to 0 replicas. The database disappears, but the rest of the stack keeps running — at first.

### Step 2 — Observe the Cascade

Watch the effects unfold over 1–2 minutes:

```bash
kgp
```

You'll notice:
- **MongoDB** — 0/0 pods (scaled to zero)
- **makeline-service** — starts failing health checks, restarts
- **Everything else** — still Running (store-front loads, products display)

The subtle part: *the store front looks fine*. You can browse products. But try placing an order — it goes into the RabbitMQ queue and never gets fulfilled.

Check makeline-service health:

```bash
kubectl logs -l app=makeline-service -n pets --tail=20
```

You'll see connection errors to MongoDB.

### Step 3 — Ask SRE Agent to Diagnose

Start broad and let the agent investigate:

1. **Open-ended:** _"The app is up but orders aren't going through. What's wrong?"_
2. **Follow-up:** _"Is MongoDB running? What depends on it?"_
3. **Root cause:** _"Trace the dependency chain — what broke first?"_

**What to look for in the response:**
- SRE Agent discovers makeline-service is failing health checks
- It traces the dependency to MongoDB
- It identifies that MongoDB has 0 replicas
- It recommends scaling MongoDB back to 1 replica
- It explains the cascading impact: MongoDB → makeline-service → order fulfillment

### Step 4 — Ask SRE Agent to Fix It

- _"Scale the mongodb deployment back to 1 replica"_

SRE Agent should execute the scale operation directly.

### Step 5 — Verify Recovery

```bash
kgp
```

Watch mongodb start, then makeline-service stabilize. Orders queued in RabbitMQ during the outage should start getting fulfilled.

### Step 6 — Fix All (If Needed)

```bash
fix-all
```

---

## Lab 3: Service Mismatch — The Silent Killer

**Difficulty:** Advanced  
**What you'll learn:** How SRE Agent detects subtle networking issues that don't show up in pod status  
**Services affected:** order-service (reachable but silently disconnected)

This is the trickiest scenario. Everything *looks* healthy — all pods are Running, no restarts, no errors in pod status. But the order-service Service has a wrong selector, so it routes traffic to nothing.

### Step 1 — Break It

```bash
break-service
```

This replaces the order-service Service with one whose selector points to `app: order-service-v2` — a label that no pod has.

### Step 2 — Observe the Subtlety

Check pod status:

```bash
kgp
```

Everything is `Running` 1/1. No crashes. No restarts. Looks perfectly healthy.

Now check the Service endpoints:

```bash
kubectl get endpoints order-service -n pets
```

You'll see:

```
NAME            ENDPOINTS   AGE
order-service   <none>      30s
```

**No endpoints.** The Service exists but routes to nothing. The store-front loads fine (it's a client-side app), but any attempt to place an order will fail because the store-front can't reach order-service.

### Step 3 — Ask SRE Agent to Diagnose

This is where SRE Agent's depth of investigation shines. Start vague:

1. **Open-ended:** _"The site loads but placing an order fails. Everything looks healthy though."_
2. **Direct:** _"Why does the order-service have no endpoints?"_
3. **Specific:** _"Compare the order-service Service selector to the actual pod labels"_

**What to look for in the response:**
- SRE Agent goes beyond pod status (all Running) to check Service endpoints
- It discovers the selector mismatch: Service expects `app: order-service-v2`, pods have `app: order-service`
- It recommends correcting the selector to `app: order-service`

### Step 4 — Ask SRE Agent to Fix It

- _"Fix the selector on the order-service Service to match the pods"_

### Step 5 — Verify Recovery

```bash
kubectl get endpoints order-service -n pets
```

Should now show the order-service pod IPs. Test by placing an order in the store front.

### Step 6 — Fix All

```bash
fix-all
```

---

## Bonus: Automated Incident Response with Outlook

If you've configured the Outlook connector (see [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md#post-configuration-authorize-outlook)), your custom agents can email incident summaries automatically.

### How It Works

1. An alert fires (e.g., pod crashes from a break scenario)
2. The `incident-handler` agent investigates using the knowledge base runbooks
3. It collects evidence: pod status, logs, events, metrics
4. It emails a structured incident report with findings and recommended remediation

### Try It

1. **Authorize Outlook** in the SRE Agent portal (Builder > Connectors > Outlook > Authorize)
2. **Create an incident response plan** in the portal that triggers the `incident-handler` agent
3. **Break something:** `break-oom`
4. **Watch the agent work** — it should investigate and send an email with findings

### Email Report Format

The agents are configured to send reports with a subject line like:

```
[SRE Agent] Sev2: OOMKilled pods in pets namespace — order-service memory exhaustion
```

The body includes root cause analysis, affected resources, evidence collected, and recommended remediation steps.

> **Note:** The incident response plan must be created manually in the [SRE Agent portal](https://sre.azure.com). See [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md#post-configuration-create-incident-response-plan) for instructions.

---

## Explore More Scenarios

Once you're comfortable with the three labs above, try the other breakable scenarios:

| Command | Scenario | Difficulty | What Makes It Interesting |
|---------|----------|------------|---------------------------|
| `break-crash` | CrashLoopBackOff | Beginner | Exit code analysis, log inspection |
| `break-image` | ImagePullBackOff | Beginner | Registry/image troubleshooting |
| `break-cpu` | High CPU | Intermediate | Resource contention, noisy neighbor |
| `break-pending` | Pending Pods | Intermediate | Scheduling constraints, capacity |
| `break-probe` | Probe Failure | Intermediate | Health check misconfiguration |
| `break-network` | Network Policy Block | Advanced | Network policy analysis |
| `break-config` | Missing ConfigMap | Beginner | Configuration dependency |

See [BREAKABLE-SCENARIOS.md](BREAKABLE-SCENARIOS.md) for detailed descriptions, observation commands, and suggested SRE Agent prompts for each scenario. The [PROMPTS-GUIDE.md](PROMPTS-GUIDE.md) has per-scenario prompt progressions from open-ended to remediation.

---

## Cleanup

When you're done, tear down the entire environment:

```powershell
.\scripts\destroy.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

Or use the shortcut:

```bash
destroy
```

This deletes the resource group and everything in it (AKS, ACR, Key Vault, SRE Agent, etc.).

> **Reminder:** The environment costs ~$32–38/day. Don't forget to tear down when you're done!

---

## Tips and Troubleshooting

- **Type `menu`** to see all available commands at any time
- **Use `fix-all`** between scenarios to restore the healthy baseline
- **Wait 30–60 seconds** after applying a break scenario before asking SRE Agent — give the failure time to manifest
- **Start with open-ended prompts** — SRE Agent's investigation is more impressive when it discovers the issue rather than being told what to look for
- **Check pod events** if you want to verify what's happening before asking SRE Agent: `kubectl describe pod <pod-name> -n pets`
- **Deployment stuck?** Make sure you're in a supported region (eastus2, swedencentral, australiaeast)
- **SRE Agent not responding?** Verify firewall allows `*.azuresre.ai` and that you have the SRE Agent Standard User or Admin role

---

## Further Reading

- [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md) — Detailed agent setup and RBAC configuration
- [BREAKABLE-SCENARIOS.md](BREAKABLE-SCENARIOS.md) — All 10 scenarios with observation commands
- [PROMPTS-GUIDE.md](PROMPTS-GUIDE.md) — Per-scenario prompt progressions
- [SRE-AGENT-PROMPTS.md](SRE-AGENT-PROMPTS.md) — Comprehensive prompt library organized by SRE discipline
- [COSTS.md](COSTS.md) — Detailed cost breakdown
