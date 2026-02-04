# Confluent Platform GitOps Demo with ArgoCD

Complete GitOps demonstration showing declarative management of the entire Confluent Platform ecosystem using ArgoCD and Helm on Kubernetes.

## What This Demo Shows

| Component | GitOps Capability |
|-----------|-------------------|
| **Kafka Cluster (KRaft)** | Declarative broker configuration, scaling, no Zookeeper |
| **Kafka Connect** | Connector CRDs - add/modify connectors via Git |
| **ksqlDB** | Queries as code - SQL stored in Git |
| **Kafka Streams** | Content routers and custom apps as separate ArgoCD applications |
| **Flink** | FlinkApplication CRDs managed independently |
| **Schema Registry** | Schema evolution managed alongside code |
| **Control Center** | Monitoring configuration as code |

Just for testing. 

## Project Structure

```
demo-cfk-argocd/
├── argocd/
│   ├── project.yaml                         # ArgoCD AppProject
│   └── applications/
│       ├── confluent-platform-prod.yaml     # Core platform
│       ├── confluent-platform-dev.yaml      # Dev environment
│       ├── content-router-prod.yaml         # Content routing
│       ├── content-router-syslog.yaml       # Syslog routing
│       ├── content-router-akamai.yaml       # Akamai CDN routing
│       ├── datagen-connectors-prod.yaml     # DataGen connectors
│       ├── flink-state-machine.yaml         # Flink example app
│       ├── flink-kafka-streaming.yaml       # Flink streaming job
│       ├── flink-hostname-enrichment.yaml   # Flink enrichment
│       └── syslog-reconstruction.yaml       # KStreams syslog app
├── charts/
│   ├── confluent-platform/                  # Core platform chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                      # Base defaults
│   │   ├── values-dev.yaml                  # Dev overrides
│   │   ├── values-prod.yaml                 # Prod overrides
│   │   └── templates/
│   │       ├── kafka.yaml
│   │       ├── kraftcontroller.yaml
│   │       ├── schemaregistry.yaml
│   │       ├── connect.yaml
│   │       ├── ksqldb.yaml
│   │       ├── ksqldb-queries.yaml
│   │       ├── controlcenter.yaml
│   │       ├── flink.yaml
│   │       └── kstreams-app.yaml
│   ├── content-router/                      # KStreams routing chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-syslog.yaml
│   │   ├── values-akamai.yaml
│   │   └── templates/
│   ├── datagen-connectors/                  # Connector definitions
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   ├── flink-application/                   # Flink job chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-state-machine.yaml
│   │   ├── values-kafka-streaming.yaml
│   │   ├── values-hostname-enrichment.yaml
│   │   └── templates/
│   └── syslog-reconstruction/               # Specialized KStreams
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── docs/
│   ├── CONFLUENT-PLATFORM-GITOPS-WHITEPAPER.md
│   ├── FLINK-APPLICATION-DEPLOYMENT-WALKTHROUGH.md
│   └── ARGOCD-REPO-CONNECTION.md
├── eks-cluster-config.yaml
└── quick-start.sh
```

## Quick Start

### Prerequisites

```bash
# Install CFK Operator
helm repo add confluentinc https://packages.confluent.io/helm
kubectl create namespace confluent-operator
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes \
  --namespace confluent-operator --set namespaced=false

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Deploy via ArgoCD

```bash
# Apply ArgoCD project and applications
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applications/confluent-platform-prod.yaml
kubectl apply -f argocd/applications/datagen-connectors-prod.yaml
```

## Components Deployed

### Core Platform (Confluent Platform 8.1 KRaft Mode)

| Component | Description |
|-----------|-------------|
| KRaft Controllers | Metadata management (3 replicas prod) |
| Kafka | Event streaming (3 brokers prod) |
| Schema Registry | Schema management |
| Kafka Connect | Connector runtime |
| ksqlDB | Stream processing SQL |
| Control Center | Monitoring UI |
| Flink Environment | CMF + FlinkEnvironment |

### DataGen Connectors

| Connector | Topic | Purpose |
|-----------|-------|---------|
| datagen-users | users | User profiles |
| datagen-pageviews | pageviews | Page view events |
| datagen-orders | orders | Order events |
| datagen-stock-trades | stock-trades | Stock trade data |
| datagen-network-events | network-events | Clickstream for ksqlDB |
| datagen-flink-input | flink-input | Input for Flink jobs |

### ksqlDB Queries

| Query | Description |
|-------|-------------|
| `CLICKSTREAM_RAW` | Stream from network-events topic |
| `REQUESTS_BY_STATUS` | Aggregates by HTTP status (1 min window) |
| `ERROR_RATE` | Tracks 4xx/5xx errors |

### Flink Applications

| Application | Description |
|-------------|-------------|
| state-machine-example | Built-in Flink example |
| kafka-streaming-job | Custom streaming processor |
| hostname-enrichment | Data enrichment pipeline |

### Kafka Streams Applications

| Application | Description |
|-------------|-------------|
| content-router-syslog | Syslog content routing |
| content-router-akamai | Akamai CDN routing |
| syslog-reconstruction | Syslog segment reassembly |

## GitOps Workflow Examples

### 1. Add a New Connector

Edit `charts/datagen-connectors/values.yaml`:

```yaml
connectors:
  - name: my-new-connector
    enabled: true
    class: io.confluent.kafka.connect.datagen.DatagenConnector
    taskMax: 1
    topic: my-new-topic
    quickstart: orders
```

Commit, push, ArgoCD syncs automatically.

### 2. Scale Kafka Cluster

Edit `charts/confluent-platform/values-prod.yaml`:

```yaml
kafka:
  replicas: 5
```

### 3. Add a ksqlDB Query

Edit `charts/confluent-platform/values.yaml`:

```yaml
ksqldb:
  queries:
    items:
      05-my-aggregation.sql: |
        CREATE TABLE IF NOT EXISTS my_aggregation AS
        SELECT key, COUNT(*) as cnt
        FROM my_stream
        GROUP BY key
        EMIT CHANGES;
```

### 4. Deploy a New Content Router

1. Create values file: `charts/content-router/values-myrouter.yaml`
2. Create ArgoCD app: `argocd/applications/content-router-myrouter.yaml`
3. Commit and push
4. Apply: `kubectl apply -f argocd/applications/content-router-myrouter.yaml`

### 5. Deploy a New Flink Application

1. Create values file: `charts/flink-application/values-myjob.yaml`
2. Create ArgoCD app: `argocd/applications/flink-myjob.yaml`
3. Commit and push
4. Apply: `kubectl apply -f argocd/applications/flink-myjob.yaml`

### 6. Switch an Application to a Different Branch

```bash
# Switch to develop branch
kubectl patch application confluent-platform-prod -n argocd \
  --type merge -p '{"spec":{"source":{"targetRevision":"develop"}}}'

# Switch back to main
kubectl patch application confluent-platform-prod -n argocd \
  --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'

# Check current branch
kubectl get application confluent-platform-prod -n argocd \
  -o jsonpath='{.spec.source.targetRevision}'
```

**Example: syslog-reconstruction v2 branch**

The `feature/syslog-v2` branch has optimized settings (2 replicas, faster windows):

```bash
# Switch to v2
kubectl patch application syslog-reconstruction -n argocd \
  --type merge -p '{"spec":{"source":{"targetRevision":"feature/syslog-v2"}}}'

# Switch back to main
kubectl patch application syslog-reconstruction -n argocd \
  --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'

# Force sync after switch
kubectl annotate application syslog-reconstruction -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

| Setting | main | feature/syslog-v2 |
|---------|------|-------------------|
| replicas | 1 | 2 |
| window.sizeSeconds | 30 | 15 |
| window.gracePeriodSeconds | 60 | 30 |

## Environment Configuration

| Setting | Dev | Prod |
|---------|-----|------|
| KRaft replicas | 1 | 3 |
| Kafka replicas | 1 | 3 |
| Kafka storage | 10Gi | 100Gi |
| Connect workers | 1 | 2 |
| ksqlDB replicas | 1 | 2 |

## Accessing Services

### Control Center
```bash
kubectl port-forward controlcenter-0 9021:9021 -n confluent
# http://localhost:9021
```

### ArgoCD
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### ksqlDB CLI
```bash
kubectl exec -it ksqldb-0 -n confluent -- ksql http://localhost:8088
```

### Flink Dashboard
```bash
kubectl port-forward svc/<flink-app>-rest 8081:8081 -n confluent
# http://localhost:8081
```

## Operational Commands

### ArgoCD

```bash
# List applications
kubectl get applications -n argocd

# Force sync
kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Check sync status
kubectl get application <name> -n argocd -o jsonpath='{.status.sync.status}'
```

### Confluent Platform

```bash
# List components
kubectl get kafka,connect,schemaregistry,ksqldb,controlcenter -n confluent

# List connectors
kubectl get connector -n confluent

# List Flink apps
kubectl get flinkapplication,flinkdeployment -n confluent
```

### Kafka Topics

```bash
# List topics
kubectl exec kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9092

# Consume messages
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --topic <topic> --bootstrap-server localhost:9092 --max-messages 5
```

## Troubleshooting

### Pods Pending
```bash
kubectl describe pod <pod> -n confluent
# Check: PVC binding, resource limits, node capacity
```

### Connector Not Running
```bash
kubectl get connector -n confluent
kubectl describe connector <name> -n confluent
```

### ArgoCD Out of Sync
```bash
kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

### Flink Job Failed
```bash
kubectl describe flinkdeployment <name> -n confluent
kubectl logs -l app=<name> -n confluent --tail=100
```

## Documentation

- [GitOps Whitepaper](docs/CONFLUENT-PLATFORM-GITOPS-WHITEPAPER.md) - Complete implementation guide
- [Flink Deployment Walkthrough](docs/FLINK-APPLICATION-DEPLOYMENT-WALKTHROUGH.md) - Step-by-step Flink setup
- [ArgoCD Repo Connection](docs/ARGOCD-REPO-CONNECTION.md) - Connecting ArgoCD to GitHub

## Technologies

- **Confluent Platform 8.1** - Apache Kafka with KRaft mode
- **CFK 3.1** - Confluent for Kubernetes operator
- **ArgoCD** - GitOps continuous delivery
- **Helm** - Kubernetes package manager
- **Apache Flink** - Stream processing

## References

- [CFK Documentation](https://docs.confluent.io/operator/current/overview.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Flink on Confluent](https://docs.confluent.io/platform/current/flink/overview.html)
