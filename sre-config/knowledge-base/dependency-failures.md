# Dependency Failure Investigation Runbook

Diagnose cascading failures caused by backend dependency outages in the pets e-commerce application on AKS. Covers MongoDB and RabbitMQ failures and their downstream impact.

---

## Application Architecture

| Service | Role | Dependencies |
|---------|------|-------------|
| store-front | Customer web UI | order-service, product-service |
| store-admin | Admin dashboard | order-service, product-service, makeline-service |
| order-service | Accepts orders, writes to DB and queue | mongodb, rabbitmq |
| product-service | Serves product catalog | mongodb |
| makeline-service | Processes orders from queue | mongodb, rabbitmq |
| virtual-customer | Simulates orders | store-front |
| virtual-worker | Simulates order processing | makeline-service |
| mongodb | Primary data store | PersistentVolumeClaim (mongodb-data-pvc) |
| rabbitmq | Message queue | In-memory |

---

## Step 1: Identify the Root Dependency

When multiple services report errors simultaneously, the root cause is usually a shared dependency:

1. Check which pods are unhealthy:
   ```bash
   kubectl get pods -n pets
   ```
2. Check logs across failing services:
   ```bash
   kubectl logs -l app=order-service -n pets --tail=20
   kubectl logs -l app=product-service -n pets --tail=20
   kubectl logs -l app=makeline-service -n pets --tail=20
   ```
3. Check backing services:
   ```bash
   kubectl get pods -n pets -l app=mongodb
   kubectl get pods -n pets -l app=rabbitmq
   ```

| Pattern | Root Cause |
|---------|-----------|
| order-service, product-service, makeline-service all failing | MongoDB is down |
| order-service failing, makeline-service idle | RabbitMQ is down |
| Only one service failing | Isolated issue (see pod-failures runbook) |

---

## Step 2: MongoDB Down

**Symptoms:**
- order-service, product-service, makeline-service return errors or fail health checks
- store-front loads but shows empty catalog or can't place orders
- MongoDB pod has 0 replicas or is in CrashLoopBackOff

**Diagnostic steps:**
1. Check MongoDB pod status:
   ```bash
   kubectl get deployment mongodb -n pets
   kubectl get pods -l app=mongodb -n pets
   ```
2. Check MongoDB PVC:
   ```bash
   kubectl get pvc mongodb-data-pvc -n pets
   ```
3. Check logs of dependent services for connection errors:
   ```bash
   kubectl logs -l app=order-service -n pets --tail=10 | grep -i "mongo\|connection\|error"
   ```
4. Query Log Analytics for the timeline:
   ```kql
   KubePodInventory
   | where Namespace == "pets"
   | where Name contains "mongodb"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Name, PodStatus, PodRestartCount
   | order by TimeGenerated desc
   ```

**Remediation:**
- Scale MongoDB back up:
  ```bash
  kubectl scale deployment mongodb -n pets --replicas=1
  ```
- Or apply healthy baseline:
  ```bash
  kubectl apply -f k8s/base/application.yaml
  ```
- Dependent services should auto-recover once MongoDB is available

---

## Step 3: RabbitMQ Down

**Symptoms:**
- order-service can't publish messages to the queue
- makeline-service has no work to process
- Orders may appear accepted but never fulfilled

**Diagnostic steps:**
1. Check RabbitMQ pod:
   ```bash
   kubectl get pods -l app=rabbitmq -n pets
   kubectl logs -l app=rabbitmq -n pets --tail=20
   ```
2. Check dependent service logs:
   ```bash
   kubectl logs -l app=order-service -n pets --tail=10 | grep -i "rabbit\|amqp\|queue"
   ```

**Remediation:**
- Restart RabbitMQ:
  ```bash
  kubectl rollout restart deployment rabbitmq -n pets
  ```
- Scale back if needed:
  ```bash
  kubectl scale deployment rabbitmq -n pets --replicas=1
  ```

---

## Step 4: Cascading Failure Analysis

To demonstrate root cause analysis, trace the failure chain:

1. **Identify symptoms:** Multiple services failing
2. **Find the common dependency:** Usually mongodb or rabbitmq
3. **Verify the dependency is down:** Check pod status, replica count
4. **Trace the timeline:** When did the dependency go down? Query events:
   ```bash
   kubectl get events -n pets --sort-by=.metadata.creationTimestamp | tail -20
   ```
5. **Correlate:** Show that all downstream failures started after the dependency failed

**Key investigation prompt for SRE Agent:**
> "Trace the dependency chain — what broke first and what was impacted downstream?"

This demonstrates SRE Agent's ability to perform root cause analysis across interconnected services rather than just reporting individual pod failures.
