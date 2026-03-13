# AKS Pod Failure Investigation Runbook

Diagnose and remediate pod-level failures in the AKS cluster running the pets e-commerce application. This runbook covers OOMKilled, CrashLoopBackOff, ImagePullBackOff, Pending pods, probe failures, and missing configuration scenarios.

---

## Step 1: Identify the Failure Type

Run initial triage to classify the issue:

```bash
kubectl get pods -n pets --field-selector=status.phase!=Running
```

| Pod Status | Likely Cause | Jump To |
|------------|-------------|---------|
| OOMKilled | Memory limits too low or memory leak | Step 2A |
| CrashLoopBackOff | Application crash on startup | Step 2B |
| ImagePullBackOff | Bad image reference or registry auth | Step 2C |
| Pending | Insufficient cluster resources | Step 2D |
| Running but not Ready | Health probe failure | Step 2E |
| CreateContainerConfigError | Missing ConfigMap or Secret | Step 2F |

---

## Step 2A: OOMKilled

**Symptoms:** Pod restarts repeatedly, `LastState.Terminated.Reason = OOMKilled`

**Diagnostic steps:**
1. Check container termination reason:
   ```bash
   kubectl describe pod -l app=<service-name> -n pets | grep -A 5 "Last State"
   ```
2. Check current memory limits vs actual usage:
   ```bash
   kubectl top pods -n pets
   kubectl get pod <pod-name> -n pets -o jsonpath='{.spec.containers[0].resources}'
   ```
3. Query Log Analytics for memory trends:
   ```kql
   KubePodInventory
   | where Namespace == "pets"
   | where Name contains "<service-name>"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Name, PodStatus, PodRestartCount
   | order by TimeGenerated desc
   ```

**Remediation:**
- Increase memory limits in the deployment spec
- Check for memory leaks in application code
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2B: CrashLoopBackOff

**Symptoms:** Container starts, exits immediately, Kubernetes keeps restarting it

**Diagnostic steps:**
1. Check container exit code:
   ```bash
   kubectl describe pod -l app=<service-name> -n pets | grep -A 10 "Last State"
   ```
2. Check previous container logs:
   ```bash
   kubectl logs -l app=<service-name> -n pets --previous
   ```
3. Common exit codes:
   - Exit 1: Application error
   - Exit 137: Killed by signal (OOM or manual kill)
   - Exit 139: Segfault

**Remediation:**
- Fix the startup command or entrypoint
- Verify environment variables and config
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2C: ImagePullBackOff

**Symptoms:** Pod stuck in ImagePullBackOff or ErrImagePull

**Diagnostic steps:**
1. Check the image reference:
   ```bash
   kubectl describe pod -l app=<service-name> -n pets | grep "Image:"
   ```
2. Check events for pull errors:
   ```bash
   kubectl get events -n pets --field-selector reason=Failed --sort-by=.metadata.creationTimestamp
   ```
3. Verify image exists in registry:
   ```bash
   az acr repository show-tags --name <acr-name> --repository <image-name>
   ```

**Remediation:**
- Correct the image tag in the deployment
- Verify ACR credentials and AKS pull permissions
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2D: Pending Pods

**Symptoms:** Pods stuck in Pending, scheduler cannot place them

**Diagnostic steps:**
1. Check scheduler events:
   ```bash
   kubectl describe pod <pod-name> -n pets | grep -A 5 "Events"
   ```
2. Check node capacity vs requests:
   ```bash
   kubectl describe nodes | grep -A 5 "Allocated resources"
   kubectl top nodes
   ```
3. Look for resource shortfalls:
   ```kql
   KubeNodeInventory
   | where TimeGenerated > ago(30m)
   | project TimeGenerated, Computer, Status
   ```

**Remediation:**
- Scale down oversized resource requests
- Scale up the node pool
- Delete unused workloads consuming resources
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2E: Probe Failure

**Symptoms:** Pod is Running but not Ready, restarts due to liveness probe failure

**Diagnostic steps:**
1. Check probe configuration:
   ```bash
   kubectl get pod <pod-name> -n pets -o jsonpath='{.spec.containers[0].livenessProbe}'
   kubectl get pod <pod-name> -n pets -o jsonpath='{.spec.containers[0].readinessProbe}'
   ```
2. Check events for probe failure:
   ```bash
   kubectl describe pod <pod-name> -n pets | grep -A 3 "Unhealthy"
   ```
3. Test the health endpoint manually:
   ```bash
   kubectl exec <pod-name> -n pets -- curl -s localhost:<port>/health
   ```

**Remediation:**
- Fix the health endpoint path, port, or response
- Adjust probe timing (initialDelaySeconds, periodSeconds, failureThreshold)
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2F: Missing Configuration

**Symptoms:** Pod in CreateContainerConfigError, references a ConfigMap or Secret that doesn't exist

**Diagnostic steps:**
1. Check pod events:
   ```bash
   kubectl describe pod <pod-name> -n pets | grep -A 5 "Events"
   ```
2. List available ConfigMaps and Secrets:
   ```bash
   kubectl get configmaps -n pets
   kubectl get secrets -n pets
   ```
3. Check which configuration is referenced:
   ```bash
   kubectl get pod <pod-name> -n pets -o jsonpath='{.spec.containers[0].envFrom}'
   ```

**Remediation:**
- Create the missing ConfigMap or Secret
- Fix the reference in the deployment spec
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## General Recovery

To restore **all** services to a known healthy state:

```bash
kubectl apply -f k8s/base/application.yaml
```

This reapplies the baseline deployment with correct images, resource limits, probes, and configuration references for all services in the pets namespace.
