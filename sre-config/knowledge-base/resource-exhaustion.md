# Resource Exhaustion Investigation Runbook

Diagnose and remediate CPU contention, memory pressure, and scheduling failures in the AKS cluster running the pets e-commerce application.

---

## Step 1: Identify Resource Pressure Type

| Symptom | Type | Jump To |
|---------|------|---------|
| Pods slow, high latency | CPU contention | Step 2 |
| Pods OOMKilled or slow | Memory pressure | Step 3 |
| New pods stuck in Pending | Scheduling failure | Step 4 |
| Node NotReady | Node-level exhaustion | Step 5 |

---

## Step 2: CPU Contention

**Symptoms:** Application responses are slow, CPU throttling, high latency

**Diagnostic steps:**
1. Check CPU usage across pods:
   ```bash
   kubectl top pods -n pets --sort-by=cpu
   ```
2. Check node-level CPU:
   ```bash
   kubectl top nodes
   ```
3. Look for CPU stress workloads:
   ```bash
   kubectl get pods -n pets | grep -i stress
   kubectl get deployment -n pets | grep -i stress
   ```
4. Query CPU metrics:
   ```kql
   InsightsMetrics
   | where TimeGenerated > ago(1h)
   | where Namespace == "pets"
   | where Name == "cpuUsageNanoCores"
   | summarize AvgCPU = avg(Val) by PodUid, bin(TimeGenerated, 5m)
   | order by AvgCPU desc
   ```

**Remediation:**
- Delete rouge CPU stress workloads:
  ```bash
  kubectl delete deployment cpu-stress-test -n pets
  ```
- Adjust CPU limits for legitimate workloads
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 3: Memory Pressure

**Symptoms:** Pods restarting with OOMKilled, node reporting MemoryPressure

**Diagnostic steps:**
1. Check memory usage:
   ```bash
   kubectl top pods -n pets --sort-by=memory
   ```
2. Check for OOM events:
   ```bash
   kubectl get events -n pets --field-selector reason=OOMKilling
   ```
3. Check node conditions:
   ```bash
   kubectl describe nodes | grep -A 3 "MemoryPressure"
   ```
4. Query memory metrics:
   ```kql
   InsightsMetrics
   | where TimeGenerated > ago(1h)
   | where Namespace == "pets"
   | where Name == "memoryWorkingSetBytes"
   | summarize AvgMem = avg(Val) by PodUid, bin(TimeGenerated, 5m)
   | order by AvgMem desc
   ```

**Remediation:**
- Increase memory limits for affected pods
- Check for memory leaks in application code
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 4: Scheduling Failures

**Symptoms:** Pods stuck in Pending, scheduler can't find a node with enough resources

**Diagnostic steps:**
1. Check pod events:
   ```bash
   kubectl describe pod <pod-name> -n pets | grep -A 10 "Events"
   ```
2. Check what resources the pod requests:
   ```bash
   kubectl get pod <pod-name> -n pets -o jsonpath='{.spec.containers[0].resources.requests}'
   ```
3. Compare to node capacity:
   ```bash
   kubectl describe nodes | grep -A 10 "Allocated resources"
   ```
4. Look for oversized requests:
   ```bash
   kubectl get pods -n pets -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory'
   ```

**Remediation:**
- Reduce resource requests to realistic values
- Scale up the node pool
- Delete unused workloads consuming capacity
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 5: Node Health

**Symptoms:** Node reporting conditions like NotReady, DiskPressure, MemoryPressure, PIDPressure

**Diagnostic steps:**
1. Check node conditions:
   ```bash
   kubectl get nodes
   kubectl describe node <node-name> | grep -A 5 "Conditions"
   ```
2. Check system pod health:
   ```bash
   kubectl get pods -n kube-system
   ```
3. Query node metrics:
   ```kql
   KubeNodeInventory
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Computer, Status, Labels
   | order by TimeGenerated desc
   ```

**Remediation:**
- Cordon and drain the unhealthy node
- Scale the node pool if capacity is insufficient
- Investigate Azure VM-level issues through Azure Monitor
