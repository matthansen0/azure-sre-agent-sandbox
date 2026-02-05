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
| MongoDB Down | `mongodb-down.yaml` | Cascading dependency failure | Dependency tracing, root cause |
| Service Mismatch | `service-mismatch.yaml` | Silent networking failure | Endpoint/selector analysis |

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

### 9. MongoDB Down - Cascading Dependency Failure

**File:** `k8s/scenarios/mongodb-down.yaml`

**What happens:**
- Scales MongoDB deployment to 0 replicas (database goes offline)
- makeline-service can't connect to MongoDB, starts failing health checks
- Orders can still be placed (queued in RabbitMQ) but never get fulfilled
- This is the most realistic scenario: requires tracing a dependency chain

**How to break:**
```bash
kubectl apply -f k8s/scenarios/mongodb-down.yaml
```

**What to observe:**
```bash
# MongoDB has 0 replicas
kubectl get deployment mongodb -n pets

# makeline-service becomes unhealthy
kubectl get pods -n pets -l app=makeline-service

# Orders queue up in RabbitMQ but never complete
kubectl exec -n pets deploy/rabbitmq -- rabbitmqctl list_queues
```

**SRE Agent prompts:**
- "The app is up but orders aren't going through. What's wrong?"
- "Why is makeline-service failing health checks?"
- "Trace the dependency chain — what broke first?"
- "Scale the mongodb deployment back to 1 replica"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 10. Service Selector Mismatch - Silent Networking Failure

**File:** `k8s/scenarios/service-mismatch.yaml`

**What happens:**
- Replaces the order-service Service with a wrong selector (`app: order-service-v2`)
- The order-service pods are perfectly healthy (Running, Ready)
- But the Service has zero endpoints — traffic doesn't reach any pod
- The store-front loads fine, but placing an order fails silently

**Why this is interesting:**
- All pods show green — no crashes, no restarts, no OOM
- `kubectl get pods` looks completely healthy
- SRE Agent must check Service endpoints and selector labels, not just pod status
- This mimics a common real-world misconfiguration (typo in selector)

**How to break:**
```bash
kubectl apply -f k8s/scenarios/service-mismatch.yaml
```

**What to observe:**
```bash
# Pods are healthy!
kubectl get pods -n pets -l app=order-service

# But the Service has no endpoints
kubectl get endpoints order-service -n pets

# Compare selector vs. pod labels
kubectl get svc order-service -n pets -o jsonpath='{.spec.selector}'
kubectl get pods -n pets -l app=order-service --show-labels
```

**SRE Agent prompts:**
- "The site loads but placing an order fails. Everything looks healthy though."
- "Why does the order-service have no endpoints?"
- "Compare the order-service Service selector to the actual pod labels"
- "Fix the selector on the order-service Service to match the pods"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
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
