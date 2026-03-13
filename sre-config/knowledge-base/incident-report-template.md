# Incident Report Template

When creating a GitHub issue for an incident, use the following structured format for consistency and actionable write-ups.

---

## Issue Title Format

```
Incident: <short description> (<affected service>)
```

**Examples:**
- `Incident: OOMKilled restarts on order-service (AKS pets namespace)`
- `Incident: Cascading failure from MongoDB outage (AKS pets namespace)`

---

## Issue Body Template

Use this markdown structure:

````markdown
# Incident Report: <short description>

- **Cluster:** `<aks-cluster-name>`
- **Namespace:** `pets`
- **Resource Group:** `<resource-group>`
- **Subscription:** `<subscription-id>`

## Summary

<2-3 sentences describing what happened, what error was observed, and the symptoms.>

## Impact

- <User-facing impact, e.g., "Store-front returned errors when placing orders">
- <Secondary impacts, e.g., "Product catalog was unavailable for 10 minutes">

## Timeline (UTC)

- **~HH:MM:** <First sign — metric anomaly or event>
- **~HH:MM:** <Error escalation or alert fired>
- **~HH:MM:** <Remediation applied>
- **~HH:MM:** <Services recovered>

## Evidence

### Pod Status

```
<Output of kubectl get pods -n pets showing affected pods>
```

### Container Logs

```
<Relevant error logs from affected services>
```

### Kubernetes Events

```
<Relevant events from kubectl get events -n pets>
```

### Metrics

- **Pod restarts:** <count and trend>
- **CPU utilization:** <peak values>
- **Memory utilization:** <peak values>
- **Request error rate:** <percentage>

## Root Cause

<1-2 sentences explaining the technical root cause. Reference the specific failure scenario, Kubernetes resource, or configuration.>

## Remediation

- **Immediate:** <what was done to fix it, e.g., "Applied healthy baseline via kubectl apply -f k8s/base/application.yaml">
- **Preventive:** <what should be done to prevent recurrence>
- **Monitoring:** <alert or check to add>

## Action Items

| # | Action | Priority |
|---|--------|----------|
| 1 | <specific fix> | High |
| 2 | <monitoring improvement> | Medium |
| 3 | <documentation update> | Low |

## References

- AKS Cluster: `<full ARM resource ID>`
- Log Analytics Workspace: `<workspace ID>`
- Application Insights: `<full ARM resource ID>`
- Scenario file: `k8s/scenarios/<scenario>.yaml`
- Recovery file: `k8s/base/application.yaml`
````

---

## Labels to Apply

| Condition | Labels |
|-----------|--------|
| Any incident | `incident` |
| Pod failure (OOM, crash, image) | `pod-failure` |
| Network issue | `networking` |
| Dependency failure | `dependency` |
| Resource exhaustion | `resource-exhaustion` |
| Critical severity | `severity-critical` |
| High severity | `severity-high` |
| Medium severity | `severity-medium` |

---

## Tips

1. **Be specific** — include actual metric values, timestamps, and resource names
2. **Include kubectl output** — paste the relevant pod status and events
3. **Show the timeline** — when did it start, when was it detected, when was it fixed
4. **Actionable items** — every report must end with concrete next steps
5. **Link to scenario** — reference the breakable scenario file that was applied
