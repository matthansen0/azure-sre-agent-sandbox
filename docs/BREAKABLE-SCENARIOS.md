# Breakable Scenarios Guide

This guide explains each failure scenario available in the demo lab and how to use them for demonstrating Azure SRE Agent capabilities.

## Quick Reference

| Scenario | File | What Breaks | SRE Agent Diagnosis |
|----------|------|-------------|---------------------|
| OOMKilled | `oom-killed.yaml` | Memory exhaustion | Identifies OOM events, recommends memory limits |
| CrashLoop | `crash-loop.yaml` | Startup failure | Shows exit codes, logs analysis |
| ImagePullBackOff | `image-pull-backoff.yaml` | Bad image reference | Registry/image troubleshooting |
| High CPU | `high-cpu.yaml` | Resource exhaustion | Performance analysis |
| Pending Pods | `pending-pods.yaml` | Insufficient resources | Scheduling analysis |
| Probe Failure | `probe-failure.yaml` | Health check failure | Probe configuration analysis |
| Network Block | `network-block.yaml` | Connectivity issues | Network policy analysis |
| Missing Config | `missing-config.yaml` | ConfigMap reference | Configuration troubleshooting |

## Scenario Details

---

### 1. OOMKilled - Out of Memory

**File:** `k8s/scenarios/oom-killed.yaml`

**What happens:**
- Deploys order-service with extremely low memory limits (16Mi)
- Pod starts, runs for a few seconds, then gets killed by OOM Killer
- Kubernetes restarts the pod, cycle repeats

**How to break:**
```bash
kubectl apply -f k8s/scenarios/oom-killed.yaml
```

**What to observe:**
```bash
# Watch pods restart
kubectl get pods -n pets -w

# See OOMKilled status
kubectl describe pod -l app=order-service -n pets | grep -A 5 "Last State"
```

**SRE Agent prompts:**
- "Why is the order-service pod restarting repeatedly?"
- "I see OOMKilled events. What memory should I allocate?"
- "Diagnose the memory issues in the pets namespace"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 2. CrashLoopBackOff - Application Crash

**File:** `k8s/scenarios/crash-loop.yaml`

**What happens:**
- Deploys product-service with a command that exits immediately
- Container starts, runs invalid command, exits with code 1
- Kubernetes keeps restarting, enters CrashLoopBackOff

**How to break:**
```bash
kubectl apply -f k8s/scenarios/crash-loop.yaml
```

**What to observe:**
```bash
# See CrashLoopBackOff status
kubectl get pods -n pets | grep product-service

# Check container logs
kubectl logs -l app=product-service -n pets --previous
```

**SRE Agent prompts:**
- "Why is product-service in CrashLoopBackOff?"
- "Show me the logs for the crashing pods"
- "What's causing exit code 1 in my application?"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 3. ImagePullBackOff - Invalid Image

**File:** `k8s/scenarios/image-pull-backoff.yaml`

**What happens:**
- Deploys makeline-service referencing a non-existent image tag
- Kubelet can't pull the image from registry
- Pod stays in ImagePullBackOff state

**How to break:**
```bash
kubectl apply -f k8s/scenarios/image-pull-backoff.yaml
```

**What to observe:**
```bash
# See ImagePullBackOff status
kubectl get pods -n pets | grep makeline

# Check events
kubectl describe pod -l app=makeline-service -n pets | grep -A 10 Events
```

**SRE Agent prompts:**
- "Why can't my pods start? I see ImagePullBackOff"
- "Help me troubleshoot the container image issue"
- "What's wrong with the makeline-service deployment?"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 4. High CPU Utilization

**File:** `k8s/scenarios/high-cpu.yaml`

**What happens:**
- Deploys stress-test pods that consume excessive CPU
- Other workloads may slow down due to resource contention
- Alerts may trigger based on CPU thresholds

**How to break:**
```bash
kubectl apply -f k8s/scenarios/high-cpu.yaml
```

**What to observe:**
```bash
# Watch CPU usage
kubectl top pods -n pets

# Check node pressure
kubectl top nodes
```

**SRE Agent prompts:**
- "My application is slow. What's consuming all the CPU?"
- "Analyze CPU usage across my pods"
- "Which pods are causing resource contention?"

**How to fix:**
```bash
kubectl delete deployment cpu-stress-test -n pets
```

---

### 5. Pending Pods - Insufficient Resources

**File:** `k8s/scenarios/pending-pods.yaml`

**What happens:**
- Deploys pods requesting 32Gi memory and 8 CPUs each
- No nodes can satisfy these requests
- Pods stay in Pending state indefinitely

**How to break:**
```bash
kubectl apply -f k8s/scenarios/pending-pods.yaml
```

**What to observe:**
```bash
# See pending pods
kubectl get pods -n pets | grep resource-hog

# Check events
kubectl describe pod -l app=resource-hog -n pets | grep -A 10 Events
```

**SRE Agent prompts:**
- "Why are my pods stuck in Pending?"
- "I can't schedule new workloads. What's wrong?"
- "Analyze cluster capacity and pending pods"

**How to fix:**
```bash
kubectl delete deployment resource-hog -n pets
```

---

### 6. Failed Liveness Probe

**File:** `k8s/scenarios/probe-failure.yaml`

**What happens:**
- Deploys service with liveness probe to non-existent endpoint
- Probe fails, Kubernetes restarts the container
- Pod shows high restart count

**How to break:**
```bash
kubectl apply -f k8s/scenarios/probe-failure.yaml
```

**What to observe:**
```bash
# Watch restarts increase
kubectl get pods -n pets -l app=unhealthy-service -w

# See probe failure events
kubectl describe pod -l app=unhealthy-service -n pets | grep -A 5 "Liveness"
```

**SRE Agent prompts:**
- "My pods keep restarting but the app seems fine"
- "Diagnose the health check failures"
- "What's wrong with my liveness probe configuration?"

**How to fix:**
```bash
kubectl delete deployment unhealthy-service -n pets
```

---

### 7. Network Policy Blocking

**File:** `k8s/scenarios/network-block.yaml`

**What happens:**
- Applies NetworkPolicy that blocks all traffic to order-service
- Service becomes unreachable from other pods
- API calls to order-service fail

**How to break:**
```bash
kubectl apply -f k8s/scenarios/network-block.yaml
```

**What to observe:**
```bash
# Test connectivity from store-front
kubectl exec -n pets deploy/store-front -- curl -s order-service:3000/health
# Should timeout or fail
```

**SRE Agent prompts:**
- "Why can't store-front reach order-service?"
- "Diagnose network connectivity issues in pets namespace"
- "What network policies are blocking my services?"

**How to fix:**
```bash
kubectl delete networkpolicy deny-order-service -n pets
```

---

### 8. Missing ConfigMap

**File:** `k8s/scenarios/missing-config.yaml`

**What happens:**
- Deploys service referencing non-existent ConfigMap
- Pod can't start because referenced config doesn't exist
- Shows ContainerCreateError

**How to break:**
```bash
kubectl apply -f k8s/scenarios/missing-config.yaml
```

**What to observe:**
```bash
# See the error
kubectl get pods -n pets | grep misconfigured

# Check events
kubectl describe pod -l app=misconfigured-service -n pets | grep -A 10 Events
```

**SRE Agent prompts:**
- "My pod won't start. Says something about ConfigMap?"
- "What configuration is missing for my deployment?"
- "Troubleshoot the ConfigMap reference error"

**How to fix:**
```bash
kubectl delete deployment misconfigured-service -n pets
```

---

## Demo Flow Suggestions

### Quick Demo (5 minutes)

1. Apply OOMKilled scenario
2. Show pods crashing in kubectl
3. Ask SRE Agent to diagnose
4. Apply fix and show recovery

### Comprehensive Demo (20 minutes)

1. **Introduction** - Show healthy application
2. **Break #1** - OOMKilled (resource issues)
3. **Break #2** - Network Policy (connectivity)
4. **Break #3** - CrashLoopBackOff (app errors)
5. **Advanced** - Show scheduled monitoring task
6. **Cleanup** - Restore all scenarios

### "Baking" for Advisor Recommendations

Some scenarios benefit from running longer to gather metrics:

1. Deploy CPU stress scenario
2. Wait 30-60 minutes
3. Check Azure Advisor for right-sizing recommendations
4. Use SRE Agent to analyze historical patterns

## Best Practices

- ✅ Always test scenarios in dev environment first
- ✅ Have baseline metrics before breaking things
- ✅ Document what you did and when for demos
- ✅ Keep fix commands ready
- ❌ Don't apply multiple breaking scenarios simultaneously
- ❌ Don't leave scenarios running unattended
