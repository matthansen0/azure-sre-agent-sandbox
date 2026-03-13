# Pets E-Commerce Application Architecture

## Overview

The pets e-commerce application is a multi-service application deployed on Azure Kubernetes Service (AKS) in the `pets` namespace. It simulates a pet supplies store with customer-facing ordering, admin management, and automated order fulfillment.

---

## Services

| Service | Language | Port | Description |
|---------|----------|------|-------------|
| store-front | Vue.js / Node.js | 8080 | Customer web storefront |
| store-admin | Vue.js / Node.js | 8081 | Admin dashboard |
| order-service | Go / Node.js | 3000 | Order creation and management API |
| product-service | Go / Node.js | 3002 | Product catalog API |
| makeline-service | Go / Node.js | 3001 | Order fulfillment processor |
| virtual-customer | Node.js | — | Simulates customer traffic placing orders |
| virtual-worker | Node.js | — | Simulates workers completing orders |

## Backing Services

| Service | Port | Persistence | Description |
|---------|------|-------------|-------------|
| mongodb | 27017 | PersistentVolumeClaim (Azure Managed Disk) | Primary data store for products and orders |
| rabbitmq | 5672 | In-memory | Message queue for order processing pipeline |

---

## Service Dependencies

```
Internet
  │
  ├──→ store-front (8080) ──→ order-service (3000) ──→ mongodb (27017)
  │         │                       │
  │         │                       └──→ rabbitmq (5672)
  │         │
  │         └──→ product-service (3002) ──→ mongodb (27017)
  │
  ├──→ store-admin (8081) ──→ order-service, product-service, makeline-service
  │
  │    makeline-service (3001) ──→ rabbitmq (5672) ──→ mongodb (27017)
  │
  │    virtual-customer ──→ store-front
  └──  virtual-worker ──→ makeline-service
```

---

## Kubernetes Resources

All resources are deployed in the `pets` namespace.

### Deployments
- `mongodb` — 1 replica, attached to `mongodb-data-pvc`
- `rabbitmq` — 1 replica, in-memory
- `product-service` — 1 replica
- `order-service` — 1 replica
- `makeline-service` — 1 replica
- `store-front` — 1 replica, type LoadBalancer (external)
- `store-admin` — 1 replica
- `virtual-customer` — 1 replica
- `virtual-worker` — 1 replica

### Services
- `mongodb` — ClusterIP on port 27017
- `rabbitmq` — ClusterIP on port 5672 (AMQP) and 15672 (Management)
- `product-service` — ClusterIP on port 3002
- `order-service` — ClusterIP on port 3000
- `makeline-service` — ClusterIP on port 3001
- `store-front` — LoadBalancer on port 80 → 8080
- `store-admin` — ClusterIP on port 80 → 8081

### Storage
- `mongodb-data-pvc` — PersistentVolumeClaim using `managed-csi` StorageClass (Azure Managed Disk)

---

## Azure Infrastructure

| Component | Azure Service | Purpose |
|-----------|--------------|---------|
| Compute | Azure Kubernetes Service (AKS) | Container orchestration |
| Registry | Azure Container Registry | Container image storage |
| Secrets | Azure Key Vault | Secrets management |
| Logs | Log Analytics Workspace | Centralized log storage |
| Telemetry | Application Insights | APM and request tracing |
| Dashboards | Azure Managed Grafana | Visualization |
| Metrics | Azure Monitor Workspace | Prometheus metrics |
| SRE | Azure SRE Agent | AI-powered diagnostics |

---

## Common Failure Modes

| Failure | Impact | Detection |
|---------|--------|-----------|
| MongoDB scaled to 0 | All data-dependent services fail | product-service/order-service health checks fail |
| RabbitMQ down | Orders accepted but never fulfilled | makeline-service has nothing to process |
| OOMKilled on any service | Pod restarts, request failures | Pod restart count increases, OOMKilled events |
| Network policy blocking order-service | Orders fail, front-end errors | Connection timeout between store-front and order-service |
| Service selector mismatch | Silent failure, zero endpoints | Service has 0 endpoints despite healthy pods |
| Wrong image tag | Pod stuck in ImagePullBackOff | Kubelet events show image pull errors |
| Missing ConfigMap | Pod won't start | CreateContainerConfigError |
| CPU stress workload | All pods degraded | High CPU across nodes |
| Probe misconfiguration | Unnecessary restarts | Readiness/liveness probe events |
| Oversized resource requests | Pods stuck in Pending | Scheduler events show insufficient resources |

---

## Monitoring & Alerting

### Log Analytics Queries

**Error logs across all services:**
```kql
ContainerLogV2
| where TimeGenerated > ago(1h)
| where PodNamespace == "pets"
| where LogMessage contains "error" or LogMessage contains "Error"
| summarize ErrorCount = count() by PodName, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**Pod restart history:**
```kql
KubePodInventory
| where TimeGenerated > ago(24h)
| where Namespace == "pets"
| where PodRestartCount > 0
| summarize MaxRestarts = max(PodRestartCount) by Name, bin(TimeGenerated, 1h)
| order by MaxRestarts desc
```

### Application Insights Queries

**Failed requests:**
```kql
requests
| where timestamp > ago(1h)
| where success == false
| summarize FailedCount = count() by name, resultCode, bin(timestamp, 5m)
| order by FailedCount desc
```
