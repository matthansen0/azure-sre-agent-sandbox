# Network and Connectivity Investigation Runbook

Diagnose and remediate network connectivity issues in the AKS cluster running the pets e-commerce application. Covers network policy blocks, service selector mismatches, and DNS resolution failures.

---

## Step 1: Identify the Network Issue

**Symptoms to look for:**
- Requests timing out between services
- Services returning connection refused errors
- Service endpoints list is empty
- Orders not processing despite all pods being "Running"

| Symptom | Likely Cause | Jump To |
|---------|-------------|---------|
| Connection refused / timeout between pods | Network policy blocking traffic | Step 2A |
| Service has 0 endpoints, pods are Running | Selector mismatch on Service | Step 2B |
| DNS resolution failures | CoreDNS or service naming issue | Step 2C |
| External traffic cannot reach store-front | Ingress / LoadBalancer misconfiguration | Step 2D |

---

## Step 2A: Network Policy Block

**Symptoms:** Pods are Running and Ready, but inter-service communication fails

**Diagnostic steps:**
1. List network policies:
   ```bash
   kubectl get networkpolicies -n pets
   ```
2. Inspect the blocking policy:
   ```bash
   kubectl describe networkpolicy <policy-name> -n pets
   ```
3. Test connectivity between pods:
   ```bash
   kubectl exec <source-pod> -n pets -- curl -s --connect-timeout 5 http://order-service:3000/health
   ```
4. Check if the policy denies all ingress:
   ```bash
   kubectl get networkpolicy <policy-name> -n pets -o jsonpath='{.spec.ingress}'
   ```

**Remediation:**
- Delete the blocking network policy:
  ```bash
  kubectl delete networkpolicy <policy-name> -n pets
  ```
- Or apply the healthy baseline which removes scenario-injected policies:
  ```bash
  kubectl apply -f k8s/base/application.yaml
  ```

---

## Step 2B: Service Selector Mismatch

**Symptoms:** Service exists, pods are Running, but the Service has zero endpoints. Traffic to the service fails silently.

**Diagnostic steps:**
1. Check service endpoints:
   ```bash
   kubectl get endpoints <service-name> -n pets
   ```
2. Compare service selector to pod labels:
   ```bash
   kubectl get svc <service-name> -n pets -o jsonpath='{.spec.selector}'
   kubectl get pods -n pets --show-labels | grep <service-name>
   ```
3. Look for label drift:
   ```bash
   kubectl get deployment <service-name> -n pets -o jsonpath='{.spec.template.metadata.labels}'
   ```

**Key insight:** This is a *silent failure* — all pods appear healthy, but traffic never reaches them because the Service selector doesn't match the pod labels. SRE Agent should compare `.spec.selector` on the Service with `.metadata.labels` on the pods.

**Remediation:**
- Fix the Service selector to match pod labels
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2C: DNS Resolution

**Symptoms:** Services cannot resolve each other by name

**Diagnostic steps:**
1. Test DNS from inside a pod:
   ```bash
   kubectl exec <pod-name> -n pets -- nslookup mongodb.pets.svc.cluster.local
   ```
2. Check CoreDNS pods:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```
3. Check CoreDNS logs:
   ```bash
   kubectl logs -l k8s-app=kube-dns -n kube-system --tail=50
   ```

**Remediation:**
- Restart CoreDNS if it's unhealthy
- Verify Service names match what applications expect

---

## Step 2D: External Access Issues

**Symptoms:** External users cannot reach the store-front

**Diagnostic steps:**
1. Check LoadBalancer service:
   ```bash
   kubectl get svc store-front -n pets
   ```
2. Verify external IP is assigned:
   ```bash
   kubectl get svc store-front -n pets -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
3. Test external connectivity:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://<external-ip>
   ```

**Remediation:**
- Wait for LoadBalancer IP to be provisioned
- Check NSG rules on the AKS subnet
- Verify the store-front pod is healthy and listening on the correct port

---

## Dependency Map

```
store-front ──→ order-service ──→ mongodb
    │                │
    └──→ product-service ──→ mongodb
              │
              └──→ rabbitmq
                      │
            makeline-service ──→ mongodb
```

When investigating connectivity issues, trace the dependency chain to determine which link is broken.
