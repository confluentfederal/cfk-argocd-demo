# ApplicationSets Implementation Guide

## Automating ArgoCD Application Generation for Scalability

**Date:** February 2, 2026  
**Priority:** 2 of 6  
**Estimated Effort:** 2-3 hours

---

## Table of Contents

1. [Overview](#overview)
2. [Current State Analysis](#current-state-analysis)
3. [ApplicationSet Generators](#applicationset-generators)
4. [Implementation](#implementation)
5. [Migration Strategy](#migration-strategy)
6. [Advanced Patterns](#advanced-patterns)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Overview

ApplicationSets are an ArgoCD extension that automatically generates Applications based on templates and generators. Instead of manually creating each Application YAML, ApplicationSets can:

- Generate Applications from Git directories/files
- Generate Applications from cluster lists
- Generate Applications from external data sources
- Automatically add/remove Applications as source data changes

### Benefits

| Benefit | Description |
|---------|-------------|
| **Reduced Toil** | No manual Application YAML creation |
| **Consistency** | Same template enforces same patterns |
| **Self-Healing** | New values files auto-generate Applications |
| **Scalability** | Manage 100s of Applications with single config |

---

## Current State Analysis

### Current Flink Applications

You have 4 Flink Applications manually defined:

```
argocd/applications/
├── flink-state-machine.yaml
├── flink-kafka-streaming.yaml
├── flink-hostname-enrichment.yaml
└── flink-syslog-reconstruction.yaml
```

Each references the same chart with different values:

```
charts/flink-application/
├── values-state-machine.yaml
├── values-kafka-streaming.yaml
├── values-hostname-enrichment.yaml
└── values-syslog-reconstruction.yaml
```

### Current Content Routers

Similarly, you have 3 content routers:

```
argocd/applications/
├── content-router-prod.yaml
├── content-router-syslog.yaml
└── content-router-akamai.yaml
```

---

## ApplicationSet Generators

### Generator Types

| Generator | Use Case |
|-----------|----------|
| **Git Directory** | One app per directory in repo |
| **Git File** | One app per matching file (values files) |
| **List** | Static list of environments/clusters |
| **Cluster** | One app per registered cluster |
| **Matrix** | Combine generators (clusters × apps) |
| **Merge** | Override values from multiple sources |

---

## Implementation

### Step 1: Flink Applications ApplicationSet

Create `argocd/applicationsets/flink-applications.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: flink-applications
  namespace: argocd
spec:
  # Prevent accidental deletion
  syncPolicy:
    preserveResourcesOnDeletion: true
  
  generators:
    # Git file generator - finds all values-*.yaml files
    - git:
        repoURL: https://github.com/confluentfederal/demo-cfk-argocd.git
        revision: main
        files:
          - path: "charts/flink-application/values-*.yaml"
  
  template:
    metadata:
      # Extract name from filename: values-kafka-streaming.yaml → flink-kafka-streaming
      name: 'flink-{{path.basenameNormalized}}'
      namespace: argocd
      labels:
        app-type: flink
        generated-by: applicationset
        chart: flink-application
      annotations:
        # Track which ApplicationSet created this
        applicationset.argoproj.io/generator: git-file
    spec:
      project: confluent
      
      source:
        repoURL: https://github.com/confluentfederal/demo-cfk-argocd.git
        targetRevision: main
        path: charts/flink-application
        helm:
          releaseName: 'flink-{{path.basenameNormalized}}'
          valueFiles:
            - '{{path.filename}}'
      
      destination:
        server: https://kubernetes.default.svc
        namespace: confluent
      
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
```

### Step 2: Content Router ApplicationSet

Create `argocd/applicationsets/content-routers.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: content-routers
  namespace: argocd
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true
  
  generators:
    - git:
        repoURL: https://github.com/confluentfederal/demo-cfk-argocd.git
        revision: main
        files:
          - path: "charts/content-router/values-*.yaml"
  
  template:
    metadata:
      name: 'content-router-{{path.basenameNormalized}}'
      namespace: argocd
      labels:
        app-type: kstreams
        generated-by: applicationset
        chart: content-router
    spec:
      project: confluent
      
      source:
        repoURL: https://github.com/confluentfederal/demo-cfk-argocd.git
        targetRevision: main
        path: charts/content-router
        helm:
          releaseName: 'content-router-{{path.basenameNormalized}}'
          valueFiles:
            - '{{path.filename}}'
      
      destination:
        server: https://kubernetes.default.svc
        namespace: confluent
      
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Step 3: Apply ApplicationSets

```bash
# Create applicationsets directory
mkdir -p argocd/applicationsets

# Apply ApplicationSets
kubectl apply -f argocd/applicationsets/flink-applications.yaml
kubectl apply -f argocd/applicationsets/content-routers.yaml

# Verify generated Applications
kubectl get applications -n argocd -l generated-by=applicationset
```

---

## Migration Strategy

### Phase 1: Deploy ApplicationSets Alongside Existing Apps

1. Create ApplicationSets with different naming convention temporarily
2. Verify they generate correctly
3. Compare configurations

```yaml
# Temporary name during migration
name: 'flink-as-{{path.basenameNormalized}}'  # "as" = ApplicationSet
```

### Phase 2: Delete Manual Applications

```bash
# List manual applications (without the label)
kubectl get applications -n argocd \
  -l '!generated-by' \
  | grep flink

# Delete manual applications one by one
kubectl delete application flink-state-machine -n argocd
kubectl delete application flink-kafka-streaming -n argocd
kubectl delete application flink-hostname-enrichment -n argocd
kubectl delete application flink-syslog-reconstruction -n argocd
```

### Phase 3: Rename ApplicationSet Apps (if needed)

Update the ApplicationSet to use the original naming:

```yaml
name: 'flink-{{path.basenameNormalized}}'
```

Re-apply and verify.

---

## Advanced Patterns

### Matrix Generator: Multi-Cluster Deployment

Deploy same apps across multiple clusters:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: flink-multi-cluster
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          # First generator: list of clusters
          - list:
              elements:
                - cluster: dev
                  url: https://dev-cluster.company.com
                - cluster: staging
                  url: https://staging-cluster.company.com
                - cluster: prod
                  url: https://prod-cluster.company.com
          
          # Second generator: list of applications
          - git:
              repoURL: https://github.com/confluentfederal/demo-cfk-argocd.git
              revision: main
              files:
                - path: "charts/flink-application/values-*.yaml"
  
  template:
    metadata:
      name: 'flink-{{path.basenameNormalized}}-{{cluster}}'
      labels:
        cluster: '{{cluster}}'
    spec:
      source:
        path: charts/flink-application
        helm:
          valueFiles:
            - '{{path.filename}}'
            - 'values-{{cluster}}.yaml'  # Cluster-specific overrides
      destination:
        server: '{{url}}'
        namespace: confluent
```

### List Generator with Environment Overrides

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: confluent-platform-environments
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - environment: dev
            branch: develop
            values: values-dev.yaml
            autoSync: "true"
          - environment: staging
            branch: main
            values: values-staging.yaml
            autoSync: "true"
          - environment: prod
            branch: main
            values: values-prod.yaml
            autoSync: "false"  # Manual sync for prod
  
  template:
    metadata:
      name: 'confluent-platform-{{environment}}'
      labels:
        environment: '{{environment}}'
    spec:
      project: confluent
      source:
        repoURL: https://github.com/confluentfederal/demo-cfk-argocd.git
        targetRevision: '{{branch}}'
        path: charts/confluent-platform
        helm:
          valueFiles:
            - values.yaml
            - '{{values}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'confluent-{{environment}}'
      syncPolicy:
        automated:
          prune: '{{autoSync}}'
          selfHeal: '{{autoSync}}'
```

### Merge Generator: Combine Data Sources

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: merged-config
  namespace: argocd
spec:
  generators:
    - merge:
        mergeKeys:
          - app
        generators:
          # Base configuration
          - list:
              elements:
                - app: flink-streaming
                  memory: "1024m"
                  cpu: "0.5"
          
          # Override for specific environments
          - list:
              elements:
                - app: flink-streaming
                  memory: "4096m"  # Override memory for this app
  
  template:
    metadata:
      name: '{{app}}'
    spec:
      source:
        helm:
          parameters:
            - name: jobManager.resource.memory
              value: '{{memory}}'
            - name: jobManager.resource.cpu
              value: '{{cpu}}'
```

---

## Best Practices

### 1. Use Labels for Tracking

```yaml
labels:
  generated-by: applicationset
  applicationset: flink-applications
  app-type: flink
```

### 2. Enable Preservation on Delete

Prevents accidental deletion of running workloads:

```yaml
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true
```

### 3. Use Consistent Naming Conventions

| Pattern | Example |
|---------|---------|
| `{chart}-{variant}` | `flink-kafka-streaming` |
| `{chart}-{env}` | `confluent-platform-prod` |
| `{chart}-{cluster}-{env}` | `flink-streaming-east-prod` |

### 4. Organize ApplicationSets by Domain

```
argocd/
├── applications/           # Static applications (if any)
├── applicationsets/
│   ├── platform/          # Core platform
│   │   └── confluent-platform.yaml
│   ├── streaming/         # Streaming apps
│   │   ├── flink-applications.yaml
│   │   └── content-routers.yaml
│   └── connectors/        # Kafka Connect
│       └── connectors.yaml
└── project.yaml
```

### 5. Template Validation

Add annotations for debugging:

```yaml
annotations:
  generated-from: '{{path}}'
  generator-revision: '{{revision}}'
```

---

## Troubleshooting

### Check ApplicationSet Status

```bash
kubectl get applicationset -n argocd
kubectl describe applicationset flink-applications -n argocd
```

### View Generated Applications

```bash
# List all generated apps
kubectl get applications -n argocd -l generated-by=applicationset

# See which ApplicationSet created an app
kubectl get application flink-kafka-streaming -n argocd \
  -o jsonpath='{.metadata.ownerReferences[0].name}'
```

### Debug Generator Output

```bash
# Check ApplicationSet controller logs
kubectl logs -l app.kubernetes.io/name=argocd-applicationset-controller \
  -n argocd --tail=100
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No apps generated | Wrong file path pattern | Check `path` in git generator |
| Duplicate apps | Overlapping generators | Use unique naming patterns |
| Apps not updating | Git cache | Force refresh: `argocd app get --hard-refresh` |
| Template errors | Invalid Go template | Check controller logs |

### Validate Template Locally

```bash
# Install argocd-applicationset CLI
# Then validate:
argocd-applicationset generate argocd/applicationsets/flink-applications.yaml
```

---

## Complete Directory Structure After Implementation

```
argocd/
├── applicationsets/
│   ├── flink-applications.yaml      # Generates all Flink apps
│   ├── content-routers.yaml         # Generates all content routers
│   └── README.md                    # ApplicationSet documentation
├── applications/
│   ├── confluent-platform-prod.yaml # Keep static for now
│   ├── confluent-platform-dev.yaml  # Keep static for now
│   └── datagen-connectors-prod.yaml # Keep static for now
└── project.yaml
```

---

## Adding New Applications

### Before: Manual Process

1. Create new values file
2. Create new ArgoCD Application YAML
3. Commit both files
4. Apply Application

### After: Simplified Process

1. Create new values file: `charts/flink-application/values-new-job.yaml`
2. Commit and push
3. ApplicationSet automatically creates the Application

```bash
# Add new Flink job
cat > charts/flink-application/values-anomaly-detection.yaml << 'EOF'
namespace: confluent
flinkEnvironment: flink-env

image:
  repository: company/anomaly-detection
  tag: "1.0.0"

job:
  jarURI: local:///opt/flink/usrlib/anomaly-detection.jar
  entryClass: com.company.AnomalyDetectionJob
  parallelism: 2
EOF

git add charts/flink-application/values-anomaly-detection.yaml
git commit -m "Add anomaly detection Flink job"
git push

# Application is automatically created!
kubectl get application flink-anomaly-detection -n argocd
```

---

## Next Steps

After completing this guide, proceed to:
- [03-SYNC-WINDOWS.md](./03-SYNC-WINDOWS.md) - Control when syncs can occur

---

*Guide Version: 1.0 | Last Updated: February 2, 2026*
