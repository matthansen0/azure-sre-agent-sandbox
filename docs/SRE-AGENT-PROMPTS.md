# SRE Agent Prompt Library

A comprehensive collection of prompts for Azure SRE Agent, organized by SRE discipline. Use these during demos, day-to-day operations, or to explore what SRE Agent can do.

> **Tip:** Start with open-ended prompts and let SRE Agent guide the investigation. Follow up with targeted prompts to drill deeper.

---

## Table of Contents

- [Troubleshooting](#troubleshooting)
- [Monitoring & Observability](#monitoring--observability)
- [Incident Response](#incident-response)
- [Capacity Planning & Scaling](#capacity-planning--scaling)
- [Security & Compliance](#security--compliance)
- [Change Management](#change-management)
- [Performance Analysis](#performance-analysis)
- [Dependency & Service Health](#dependency--service-health)
- [Remediation & Actions](#remediation--actions)
- [Scheduled Tasks & Automation](#scheduled-tasks--automation)
- [Conversation Starters (Non-Technical)](#conversation-starters-non-technical)

---

## Troubleshooting

### General Triage

| Prompt | When to Use |
|--------|-------------|
| "Something is wrong with my application. Can you investigate?" | Great starting point — lets SRE Agent discover issues on its own |
| "Are there any unhealthy resources in my resource group?" | Broad sweep across all Azure resources, not just AKS |
| "Which pods in the pets namespace are not in a Running state?" | Quick status check across all workloads |
| "Show me all warning and error events in the pets namespace from the last 30 minutes" | Event-level triage when you know something recently broke |
| "Are there any failed deployments or rollouts in progress?" | Catch stuck rollouts or partial updates |

### Pod-Level Diagnosis

| Prompt | When to Use |
|--------|-------------|
| "Why is [pod-name] in CrashLoopBackOff?" | Direct pod investigation |
| "Show me the logs for pods that have restarted in the last hour" | Correlate restarts with log output |
| "What's the exit code and termination reason for the last failed container in order-service?" | Precise failure details |
| "Are any init containers failing across my deployments?" | Init container issues are easy to miss |
| "Compare the running pod spec for order-service to its deployment spec — are there any drift issues?" | Detect manual overrides or config drift |

### Networking Issues

| Prompt | When to Use |
|--------|-------------|
| "Can store-front reach order-service on port 3000?" | Validate service-to-service connectivity |
| "Are there any network policies blocking traffic in the pets namespace?" | Surface overly restrictive policies |
| "Why does the order-service Service have zero endpoints?" | Diagnose selector/label mismatches |
| "Show me DNS resolution results for mongodb inside the cluster" | Troubleshoot service discovery |
| "Trace the network path from the store-front ingress to the backend services" | End-to-end connectivity map |

### Storage & Volume Issues

| Prompt | When to Use |
|--------|-------------|
| "Are there any PersistentVolumeClaims stuck in Pending?" | Storage provisioning failures |
| "Check if the MongoDB data volume is running low on space" | Proactive disk pressure detection |
| "Are any pods failing to mount their volumes?" | Volume mount errors during startup |

---

## Monitoring & Observability

### Cluster Health

| Prompt | When to Use |
|--------|-------------|
| "Give me an overall health report for my AKS cluster" | Executive summary of cluster state |
| "What's the node status and condition for all nodes in the cluster?" | Node-level health (DiskPressure, MemoryPressure, etc.) |
| "Are there any system pods that aren't healthy in kube-system?" | Control plane component health |
| "Show me the cluster autoscaler status and recent scaling decisions" | Understand auto-scaling behavior |
| "What Kubernetes version am I running and is it still supported?" | Version lifecycle awareness |

### Application Metrics

| Prompt | When to Use |
|--------|-------------|
| "What's the current CPU and memory utilization for each pod in the pets namespace?" | Real-time resource snapshot |
| "Show me the request latency trends for store-front over the last 6 hours" | Application-level performance |
| "What are the most common exceptions in Application Insights for my app?" | Error pattern analysis |
| "Are there any pods consistently running above 80% of their resource limits?" | About-to-break detection |
| "Show me container restart counts and trends over the last 24 hours" | Stability trending |

### Log Analysis

| Prompt | When to Use |
|--------|-------------|
| "Query the last 50 error-level logs from the order-service container" | Targeted log retrieval |
| "Search Application Insights for any 5xx responses in the last hour" | HTTP error investigation |
| "Show me log volume trends — are any services producing an unusual amount of logs?" | Log storm detection |
| "Correlate pod restart events with error logs from the same time window" | Root cause correlation |
| "Are there any recurring error patterns in my container logs?" | Chronic issue detection |

### Alerting & Notifications

| Prompt | When to Use |
|--------|-------------|
| "What alerts are currently firing for my resource group?" | Active alert review |
| "Show me the alert history for the last 7 days" | Trend analysis on incidents |
| "Are my alert rules configured correctly for the AKS cluster?" | Alert configuration audit |

---

## Incident Response

### First Response

| Prompt | When to Use |
|--------|-------------|
| "I just got paged — my application is down. What's happening?" | Incident triage starting point |
| "What's the blast radius? Which services are affected right now?" | Impact assessment |
| "When did this issue start? Show me the timeline of events" | Establish incident timeline |
| "Is this a complete outage or partial degradation?" | Severity classification |
| "How many users are impacted based on the traffic patterns?" | User impact estimation |

### Root Cause Analysis

| Prompt | When to Use |
|--------|-------------|
| "What was the root cause of the pod failures that started 20 minutes ago?" | Post-triage RCA |
| "Trace the dependency chain — what broke first and what was impacted downstream?" | Cascading failure analysis |
| "Was this caused by a deployment, a config change, or an infrastructure event?" | Change correlation |
| "Compare the current state of my cluster to 1 hour ago — what's different?" | Diff-based investigation |
| "Show me all Kubernetes events, sorted by time, for the last 30 minutes" | Chronological event reconstruction |

### Communication

| Prompt | When to Use |
|--------|-------------|
| "Summarize the current incident in 3 sentences for my status page" | Stakeholder communication |
| "Write a brief incident summary I can share with my team" | Internal update |
| "What's the current status and what actions have been taken so far?" | Handoff during shift change |

---

## Capacity Planning & Scaling

| Prompt | When to Use |
|--------|-------------|
| "Do I have enough cluster capacity to handle a 2x traffic increase?" | Load readiness assessment |
| "Which nodes are most utilized and which have headroom?" | Node-level capacity map |
| "What would happen if I lost one node — would my pods still fit?" | Failure resilience planning |
| "Are my resource requests and limits set appropriately based on actual usage?" | Right-sizing recommendations |
| "Show me the ratio of requested resources vs. actual usage for each deployment" | Over-provisioning detection |
| "Would scaling product-service to 5 replicas fit on the current nodes?" | Pre-scale feasibility check |
| "What's the trend in resource utilization over the past week? Am I growing?" | Growth trajectory |
| "Recommend node pool sizing for my current workload" | Infrastructure right-sizing |

---

## Security & Compliance

| Prompt | When to Use |
|--------|-------------|
| "Are any containers running as root in the pets namespace?" | Security posture check |
| "Check if any pods have containers with privilege escalation enabled" | Privilege audit |
| "Are there any containers running without resource limits set?" | Best practice enforcement |
| "Show me the RBAC roles and bindings in the pets namespace" | Access control review |
| "Are any of my container images using the 'latest' tag?" | Image tagging best practice |
| "Do any pods have host network or host PID access?" | Host-level access audit |
| "Are my secrets stored in Kubernetes Secrets or referenced from Key Vault?" | Secrets management review |
| "Check if network policies exist for all services in the pets namespace" | Network segmentation audit |

---

## Change Management

| Prompt | When to Use |
|--------|-------------|
| "What changed in my cluster in the last 10 minutes?" | Post-change verification |
| "Were any deployments modified or restarted recently?" | Trace a specific change |
| "Show me the rollout history for order-service" | Deployment version tracking |
| "Is the latest rollout for product-service complete and healthy?" | Rollout status check |
| "What image versions are running vs. what's defined in the deployment spec?" | Image version drift |
| "Compare the current order-service deployment to the previous revision" | Diff between revisions |

---

## Performance Analysis

| Prompt | When to Use |
|--------|-------------|
| "Which service has the highest response latency right now?" | Latency hotspot detection |
| "Is there any CPU throttling happening on my pods?" | Throttling detection |
| "Analyze the request throughput for store-front — is it within normal range?" | Traffic anomaly detection |
| "Are there any pods that are being CPU-throttled due to low limits?" | Resource constraint impact |
| "Show me the p95 and p99 latency for my application endpoints" | Tail latency analysis |
| "My application is slow. Identify the bottleneck — is it CPU, memory, network, or disk?" | Performance triage |
| "Compare performance metrics from this week vs. last week" | Regression detection |

---

## Dependency & Service Health

| Prompt | When to Use |
|--------|-------------|
| "Map out the service dependencies in the pets namespace" | Service topology discovery |
| "Is MongoDB healthy and accepting connections?" | Database dependency check |
| "Is RabbitMQ running and are queues being consumed?" | Message broker health |
| "Which services depend on MongoDB and how would they be affected if it went down?" | Blast radius analysis |
| "Check the health of all backing services — database, message queue, cache" | Full dependency sweep |
| "Are there any services that are up but returning errors to their callers?" | Silent failure detection |

---

## Remediation & Actions

> **Requires write permissions** — see [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md) for RBAC configuration.

| Prompt | What It Does |
|--------|-------------|
| "Restart the order-service pods" | Rolling restart of a deployment |
| "Scale product-service to 3 replicas" | Horizontal scaling |
| "Delete the cpu-stress-test deployment" | Remove rogue/test workloads |
| "Remove the deny-order-service network policy" | Unblock network traffic |
| "Scale the mongodb deployment back to 1 replica" | Restore a dependency |
| "Roll back the order-service deployment to the previous revision" | Deployment rollback |
| "Cordon the unhealthy node and drain its workloads" | Node maintenance |
| "Increase the memory limit for order-service to 256Mi" | Resource limit adjustment |
| "Apply the healthy configuration from k8s/base/application.yaml" | Full state restoration |

---

## Scheduled Tasks & Automation

Use these prompts in the **Subagent builder** to set up recurring checks:

| Prompt | Schedule | Purpose |
|--------|----------|---------|
| "Check AKS cluster health and alert if any node is NotReady" | Every 15 min | Node health monitoring |
| "Monitor pod restarts in pets namespace — alert if any pod restarts more than 3 times in an hour" | Every 15 min | Restart anomaly detection |
| "Run a daily capacity report and flag if any node exceeds 80% CPU or memory" | Daily at 8 AM | Capacity monitoring |
| "Check for any pods in CrashLoopBackOff or ImagePullBackOff every 30 minutes" | Every 30 min | Failure state detection |
| "Generate a weekly SRE report summarizing incidents, restarts, and resource trends" | Weekly on Monday | Operational summary |
| "Verify all deployments have at least 2 replicas during business hours" | Hourly, 8AM-6PM | Availability enforcement |

---

## Conversation Starters (Non-Technical)

Great for demos where the audience may not know Kubernetes terminology:

| Prompt | Why It Works |
|--------|-------------|
| "My website is broken" | SRE Agent discovers what "broken" means |
| "Customers are complaining that checkout is slow" | Business-language → technical diagnosis |
| "We deployed something an hour ago and now things are bad" | Change correlation from a human perspective |
| "Is my app ready for a big product launch tomorrow?" | Capacity + health in business terms |
| "Help me understand why my costs went up this month" | Bridges SRE and FinOps |
| "I'm new to this cluster — give me a tour" | Onboarding/knowledge transfer |
| "What should I be worried about right now?" | Proactive risk assessment |
| "If you were on-call for this cluster, what would you check first?" | SRE best-practice framing |

---

## Pro Tips

1. **Layer your prompts** — Start broad ("what's wrong?"), then narrow ("why is order-service failing?"), then act ("restart order-service")
2. **Use business language** — SRE Agent translates "checkout is slow" into pod metrics and traces
3. **Ask "why" not "what"** — "Why is this pod restarting?" yields better insight than "show me pod status"
4. **Request timelines** — "When did this start?" helps SRE Agent correlate events
5. **Combine signals** — "Correlate the pod restarts with CPU spikes and any recent deployments" gets multi-signal analysis
6. **Follow up naturally** — SRE Agent keeps conversation context, so build on previous answers
7. **Ask for prevention** — After fixing an issue, ask "How can I prevent this from happening again?"
