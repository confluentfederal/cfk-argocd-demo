# Confluent Platform 8.1 GitOps Demo with Argo CD

Complete GitOps demonstration showing declarative management of the entire Confluent Platform ecosystem using Argo CD.

## What This Demo Shows

| Component | GitOps Capability |
|-----------|-------------------|
| **Kafka Cluster** | Declarative broker configuration, scaling |
| **Kafka Connect** | Connector CRDs - add/modify connectors via Git |
| **ksqlDB** | Queries as code - SQL stored in Git |
| **Kafka Streams** | Application deployments managed by Argo CD |
| **Flink** | FlinkApplication CRDs (requires CMF operator) |
| **Schema Registry** | Schema evolution managed alongside code |
| **Control Center** | Monitoring configuration as code |

## Project Structure

```
.
├── base/
│   ├── kustomization.yaml          # Base kustomization
│   ├── confluent-platform.yaml     # Core CP 8.1 components
│   ├── connectors.yaml             # Declarative Kafka Connect connectors
│   ├── ksqldb-queries.yaml         # ksqlDB queries as ConfigMaps
│   ├── kstreams-app.yaml           # Kafka Streams application deployment
│   └── flink.yaml                  # Flink environment & applications
├── overlays/
│   ├── dev/                        # Local k3d development (reduced resources)
│   │   └── kustomization.yaml
│   └── prod/                       # Production AWS/AKS (full resources)
│       └── kustomization.yaml
├── argocd-application.yaml         # Argo CD Application manifest
├── quick-start.sh                  # One-command local setup
└── docs/
    └── CONVERSATION-SUMMARY.md
```

## Quick Start (Local Development)

```bash
# Ensure Docker Desktop is running, then:
chmod +x quick-start.sh
./quick-start.sh
```

This will:
1. Create a k3d cluster with 3 nodes
2. Install CFK 3.1.1 operator
3. Install Argo CD
4. Deploy Confluent Platform 8.1

## Components Deployed

### Core Platform (CP 8.1.1)
- **Zookeeper** - Coordination service (3 replicas prod, 1 dev)
- **Kafka** - Event streaming (3 brokers prod, 1 dev)
- **Schema Registry** - Schema management
- **Control Center** - Monitoring UI

### Data Integration
- **Kafka Connect** - With declarative connector management
  - DataGen connector (users topic)
  - DataGen connector (pageviews topic)
- **ksqlDB** - Stream processing with queries as code

### Stream Processing
- **Kafka Streams** - Sample pageview-enricher application
- **Flink** - FlinkApplication for aggregations (requires CMF)

## GitOps Workflow Demo

### 1. Add a New Connector
Edit `base/connectors.yaml`:

```yaml
---
apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: my-new-connector
  namespace: confluent
spec:
  class: io.confluent.kafka.connect.datagen.DatagenConnector
  taskMax: 1
  connectClusterRef:
    name: connect
  configs:
    kafka.topic: my-new-topic
    quickstart: orders
```

Commit, push, watch Argo CD deploy it.

### 2. Scale Kafka Cluster
Edit overlay patch in `overlays/dev/kustomization.yaml`:

```yaml
- target:
    kind: Kafka
    name: kafka
  patch: |-
    - op: replace
      path: /spec/replicas
      value: 3
```

### 3. Add ksqlDB Query
Add to `base/ksqldb-queries.yaml`:

```yaml
05-new-aggregation.sql: |
  CREATE TABLE my_aggregation AS
  SELECT key, COUNT(*) as cnt
  FROM my_stream
  GROUP BY key;
```

### 4. Deploy Kafka Streams Update
Update image tag in `base/kstreams-app.yaml`, commit, and Argo CD rolls it out.

## Accessing Services

### Control Center
```bash
kubectl port-forward controlcenter-0 9021:9021 -n confluent
# http://localhost:9021
```

### Argo CD
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### ksqlDB CLI
```bash
kubectl exec -it ksqldb-0 -n confluent -- ksql http://localhost:8088
```

## Demo Script (30 minutes)

### Introduction (5 min)
1. Explain GitOps principles
2. Show repository structure
3. Highlight declarative approach

### Live Demo (15 min)
1. **Show Argo CD** - Synced resources, health status
2. **Add connector via Git** - Commit, watch auto-deploy
3. **Show data flowing** - Control Center topics view
4. **Scale Kafka** - Modify replica count, observe rolling update
5. **Add ksqlDB query** - Show query deployment

### Deep Dive (10 min)
1. Kustomize base + overlays pattern
2. Environment promotion (dev → prod)
3. Rollback demonstration
4. Discuss production considerations

## Environment Comparison

| Setting | Dev (k3d) | Prod (AWS/AKS) |
|---------|-----------|----------------|
| Kafka replicas | 1 | 3 |
| Zookeeper replicas | 1 | 3 |
| Connect workers | 1 | 2 |
| ksqlDB replicas | 1 | 2 |
| Storage per broker | 10Gi | 100Gi |
| Flink | Disabled | Enabled |

## Production Deployment (AWS/AKS)

### Prerequisites
- EKS or AKS cluster (3+ nodes, m5.xlarge or equivalent)
- EBS CSI driver (AWS) or Azure Disk CSI (AKS)
- CFK 3.1.1 operator installed
- CMF operator (for Flink)

### Deploy
```bash
# Point Argo CD at production overlay
kubectl apply -f argocd-application.yaml
# Edit repoURL and change path to overlays/prod
```

## Flink Setup (Optional)

Flink requires the Confluent Manager for Flink (CMF) operator:

```bash
# Install CMF operator (separate from CFK)
helm upgrade --install cmf-operator \
  confluentinc/confluent-manager-for-apache-flink \
  --namespace confluent-operator

# Then uncomment flink.yaml in base/kustomization.yaml
```

## Troubleshooting

### Pods Pending
```bash
kubectl describe pod <pod> -n confluent
# Check PVC binding, resource limits
```

### Connector Not Creating
```bash
kubectl get connector -n confluent
kubectl describe connector <name> -n confluent
kubectl logs -l app=connect -n confluent
```

### Argo CD Out of Sync
```bash
# Force sync
kubectl patch application confluent-platform -n argocd \
  --type merge -p '{"operation": {"sync": {}}}'
```

## Cleanup

```bash
# Delete application
kubectl delete application confluent-platform -n argocd

# Delete cluster (local)
k3d cluster delete cfk-demo
```

## Technologies

- **Confluent Platform 8.1.1** - Apache Kafka 4.1
- **CFK 3.1.1** - Confluent for Kubernetes operator
- **Argo CD** - GitOps continuous delivery
- **Kustomize** - Configuration management
- **k3d** - Local Kubernetes (development)

## References

- [CFK Documentation](https://docs.confluent.io/operator/current/overview.html)
- [Declarative Connectors](https://www.confluent.io/blog/declarative-connectors-with-confluent-for-kubernetes/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Flink with CFK](https://docs.confluent.io/operator/current/co-manage-flink.html)
