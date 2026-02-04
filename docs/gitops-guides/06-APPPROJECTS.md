# AppProject RBAC Guide

## Creating Separate AppProjects for Platform and Applications

**Date:** February 2, 2026  
**Priority:** 6 of 6  
**Estimated Effort:** 1-2 hours

---

## Table of Contents

1. [Overview](#overview)
2. [Current State](#current-state)
3. [Target Architecture](#target-architecture)
4. [Implementation](#implementation)
5. [RBAC Configuration](#rbac-configuration)
6. [Migration Strategy](#migration-strategy)
7. [Operational Procedures](#operational-procedures)
8. [Best Practices](#best-practices)

---

## Overview

ArgoCD AppProjects provide:

- **Resource Isolation** - Control which resources apps can create
- **Repository Restrictions** - Limit which Git repos apps can use
- **Destination Restrictions** - Control target clusters/namespaces
- **Role-Based Access** - Define who can manage what
- **Sync Windows** - Environment-specific deployment timing

### Why Separate Projects?

| Concern | Single Project | Multiple Projects |
|---------|---------------|-------------------|
| Access Control | Everyone sees everything | Role-based visibility |
| Blast Radius | One misconfiguration affects all | Isolated failures |
| Resource Limits | Shared limits | Per-project limits |
| Sync Windows | Same for all apps | Environment-specific |
| Audit | Mixed logs | Clean separation |

---

## Current State

Your current single project:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent
  namespace: argocd
spec:
  sourceRepos:
    - 'https://github.com/confluentfederal/*'
  destinations:
    - namespace: confluent
      server: https://kubernetes.default.svc
```

### Issues with Current Approach

1. No separation between infrastructure and applications
2. Same permissions for all team members
3. Single sync window affects all apps
4. Difficult to audit who changed what

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ArgoCD Projects                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────┐  ┌──────────────────────┐                │
│  │ confluent-platform   │  │ confluent-apps       │                │
│  │ (Platform Team)      │  │ (App Teams)          │                │
│  ├──────────────────────┤  ├──────────────────────┤                │
│  │ • Kafka              │  │ • Flink Apps         │                │
│  │ • Schema Registry    │  │ • KStreams Apps      │                │
│  │ • Connect            │  │ • Content Routers    │                │
│  │ • ksqlDB             │  │                      │                │
│  │ • Control Center     │  │                      │                │
│  └──────────────────────┘  └──────────────────────┘                │
│                                                                      │
│  ┌──────────────────────┐  ┌──────────────────────┐                │
│  │ confluent-connectors │  │ confluent-dev        │                │
│  │ (Integration Team)   │  │ (All Teams)          │                │
│  ├──────────────────────┤  ├──────────────────────┤                │
│  │ • Connector configs  │  │ • Dev environment    │                │
│  │ • DataGen sources    │  │ • Unrestricted sync  │                │
│  └──────────────────────┘  └──────────────────────┘                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### Step 1: Create Platform Project

```yaml
# argocd/projects/confluent-platform.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent-platform
  namespace: argocd
  annotations:
    description: "Core Confluent Platform infrastructure"
spec:
  description: Confluent Platform infrastructure managed by Platform Team
  
  # Source repositories
  sourceRepos:
    - 'https://github.com/confluentfederal/demo-cfk-argocd.git'
  
  # Allowed destinations
  destinations:
    - namespace: confluent
      server: https://kubernetes.default.svc
    - namespace: confluent-operator
      server: https://kubernetes.default.svc
  
  # Cluster-scoped resources this project can manage
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: platform.confluent.io
      kind: '*'
    - group: flink.apache.org
      kind: '*'
  
  # Namespace-scoped resources this project can manage
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  
  # Resources this project CANNOT manage
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
    - group: ''
      kind: LimitRange
    - group: networking.k8s.io
      kind: NetworkPolicy
  
  # Orphaned resource detection
  orphanedResources:
    warn: true
    ignore:
      - group: ''
        kind: ConfigMap
        name: kube-root-ca.crt
  
  # Sync windows - strict for production
  syncWindows:
    # Business hours only for prod
    - kind: deny
      schedule: '0 18 * * *'
      duration: 14h
      applications:
        - '*-prod'
      manualSync: true
    
    # Deny weekends
    - kind: deny
      schedule: '0 0 * * 6'
      duration: 48h
      applications:
        - '*-prod'
      manualSync: true
  
  # RBAC roles for this project
  roles:
    - name: platform-admin
      description: Full access to platform project
      policies:
        - p, proj:confluent-platform:platform-admin, applications, *, confluent-platform/*, allow
        - p, proj:confluent-platform:platform-admin, clusters, get, *, allow
        - p, proj:confluent-platform:platform-admin, repositories, get, *, allow
        - p, proj:confluent-platform:platform-admin, logs, get, confluent-platform/*, allow
      groups:
        - platform-team
    
    - name: platform-viewer
      description: Read-only access to platform project
      policies:
        - p, proj:confluent-platform:platform-viewer, applications, get, confluent-platform/*, allow
        - p, proj:confluent-platform:platform-viewer, logs, get, confluent-platform/*, allow
      groups:
        - developers
```

### Step 2: Create Applications Project

```yaml
# argocd/projects/confluent-apps.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent-apps
  namespace: argocd
  annotations:
    description: "Flink and Kafka Streams applications"
spec:
  description: Streaming applications managed by application teams
  
  sourceRepos:
    - 'https://github.com/confluentfederal/demo-cfk-argocd.git'
    - 'https://github.com/confluentfederal/streaming-apps.git'
  
  destinations:
    - namespace: confluent
      server: https://kubernetes.default.svc
  
  # Only specific resource types for apps
  clusterResourceWhitelist: []  # No cluster resources
  
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ''
      kind: ConfigMap
    - group: ''
      kind: Secret
    - group: ''
      kind: Service
    - group: ''
      kind: ServiceAccount
    - group: flink.apache.org
      kind: FlinkApplication
    - group: flink.apache.org
      kind: FlinkDeployment
    - group: platform.confluent.io
      kind: KafkaTopic
  
  # More permissive sync windows for apps
  syncWindows:
    - kind: deny
      schedule: '0 22 * * *'
      duration: 8h
      applications:
        - '*-prod'
      manualSync: true
  
  orphanedResources:
    warn: true
  
  roles:
    - name: app-admin
      description: Full access to applications
      policies:
        - p, proj:confluent-apps:app-admin, applications, *, confluent-apps/*, allow
        - p, proj:confluent-apps:app-admin, logs, get, confluent-apps/*, allow
      groups:
        - app-developers
        - platform-team
    
    - name: app-deployer
      description: Can sync applications
      policies:
        - p, proj:confluent-apps:app-deployer, applications, get, confluent-apps/*, allow
        - p, proj:confluent-apps:app-deployer, applications, sync, confluent-apps/*, allow
      groups:
        - release-managers
```

### Step 3: Create Connectors Project

```yaml
# argocd/projects/confluent-connectors.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent-connectors
  namespace: argocd
  annotations:
    description: "Kafka Connect connectors"
spec:
  description: Kafka Connect connectors managed by integration team
  
  sourceRepos:
    - 'https://github.com/confluentfederal/demo-cfk-argocd.git'
  
  destinations:
    - namespace: confluent
      server: https://kubernetes.default.svc
  
  clusterResourceWhitelist: []
  
  namespaceResourceWhitelist:
    - group: platform.confluent.io
      kind: Connector
    - group: ''
      kind: ConfigMap
    - group: ''
      kind: Secret
  
  orphanedResources:
    warn: true
  
  roles:
    - name: connector-admin
      description: Full access to connectors
      policies:
        - p, proj:confluent-connectors:connector-admin, applications, *, confluent-connectors/*, allow
      groups:
        - integration-team
```

### Step 4: Create Development Project

```yaml
# argocd/projects/confluent-dev.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent-dev
  namespace: argocd
  annotations:
    description: "Development environment - unrestricted"
spec:
  description: Development environment for all teams
  
  sourceRepos:
    - '*'  # Allow any repository
  
  destinations:
    - namespace: confluent-dev
      server: https://kubernetes.default.svc
  
  # More permissive for dev
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: '*'
      kind: '*'
  
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  
  # No sync windows for dev
  syncWindows: []
  
  orphanedResources:
    warn: false  # Less strict for dev
  
  roles:
    - name: dev-admin
      description: Full access to dev environment
      policies:
        - p, proj:confluent-dev:dev-admin, applications, *, confluent-dev/*, allow
        - p, proj:confluent-dev:dev-admin, logs, get, confluent-dev/*, allow
      groups:
        - developers
        - platform-team
```

### Step 5: Apply All Projects

```bash
# Create projects directory
mkdir -p argocd/projects

# Apply all projects
kubectl apply -f argocd/projects/
```

---

## RBAC Configuration

### ArgoCD RBAC ConfigMap

```yaml
# argocd/rbac/argocd-rbac-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  
  policy.csv: |
    # Global admin role
    g, admin-team, role:admin
    
    # Platform team gets admin on platform project
    g, platform-team, proj:confluent-platform:platform-admin
    g, platform-team, proj:confluent-apps:app-admin
    g, platform-team, proj:confluent-connectors:connector-admin
    g, platform-team, proj:confluent-dev:dev-admin
    
    # App developers
    g, app-developers, proj:confluent-apps:app-admin
    g, app-developers, proj:confluent-dev:dev-admin
    g, app-developers, proj:confluent-platform:platform-viewer
    
    # Integration team
    g, integration-team, proj:confluent-connectors:connector-admin
    g, integration-team, proj:confluent-apps:app-admin
    
    # Release managers - can sync but not create/delete
    g, release-managers, proj:confluent-apps:app-deployer
    g, release-managers, proj:confluent-platform:platform-viewer
    
    # Read-only for all developers on platform
    g, developers, proj:confluent-platform:platform-viewer
  
  scopes: '[groups]'
```

### SSO Group Mapping

If using OIDC/SSO:

```yaml
# In argocd-cm ConfigMap
data:
  oidc.config: |
    name: GitLab
    issuer: https://gitlab.company.com
    clientID: argocd
    clientSecret: $oidc.gitlab.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
    # Map GitLab groups to ArgoCD groups
    groupsClaim: groups
```

---

## Migration Strategy

### Phase 1: Create New Projects (Non-Breaking)

```bash
# Apply new projects alongside existing
kubectl apply -f argocd/projects/confluent-platform.yaml
kubectl apply -f argocd/projects/confluent-apps.yaml
kubectl apply -f argocd/projects/confluent-connectors.yaml
kubectl apply -f argocd/projects/confluent-dev.yaml

# Verify projects created
kubectl get appprojects -n argocd
```

### Phase 2: Migrate Applications One by One

```bash
# Update application to use new project
kubectl patch application confluent-platform-prod -n argocd \
  --type merge -p '{"spec":{"project":"confluent-platform"}}'

kubectl patch application flink-kafka-streaming -n argocd \
  --type merge -p '{"spec":{"project":"confluent-apps"}}'
```

### Phase 3: Update Application YAMLs

Update each Application YAML in `argocd/applications/`:

```yaml
# Before
spec:
  project: confluent

# After
spec:
  project: confluent-platform  # or confluent-apps, etc.
```

### Phase 4: Deprecate Old Project

```bash
# Once all apps migrated, delete old project
kubectl delete appproject confluent -n argocd
```

---

## Operational Procedures

### Checking Project Assignment

```bash
# List all applications with their projects
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,PROJECT:.spec.project

# Example output:
# NAME                      PROJECT
# confluent-platform-prod   confluent-platform
# flink-kafka-streaming     confluent-apps
# datagen-connectors        confluent-connectors
```

### Project Access Audit

```bash
# List all roles in a project
kubectl get appproject confluent-platform -n argocd \
  -o jsonpath='{.spec.roles[*].name}'

# Check group membership
kubectl get appproject confluent-platform -n argocd \
  -o jsonpath='{.spec.roles[?(@.name=="platform-admin")].groups}'
```

### Moving Application Between Projects

```bash
# Move app from apps to platform project
kubectl patch application flink-kafka-streaming -n argocd \
  --type merge -p '{"spec":{"project":"confluent-platform"}}'
```

---

## Best Practices

### 1. Project Naming Convention

| Pattern | Example | Description |
|---------|---------|-------------|
| `{org}-{function}` | `confluent-platform` | By function |
| `{org}-{env}` | `confluent-prod` | By environment |
| `{org}-{team}` | `confluent-data-eng` | By team |

### 2. Resource Restriction Guidelines

| Project Type | Cluster Resources | Namespace Resources |
|--------------|-------------------|---------------------|
| Infrastructure | CRDs, Namespaces | All |
| Applications | None | Deployments, Services, ConfigMaps |
| Connectors | None | Connector CRs only |
| Development | All | All |

### 3. Sync Window Strategy

| Project | Sync Windows | Manual Sync |
|---------|--------------|-------------|
| Platform | Strict (business hours) | Emergency only |
| Apps | Moderate (extended hours) | Yes |
| Connectors | Strict | Yes |
| Dev | None | N/A |

### 4. Role Hierarchy

```
                    ┌─────────────────┐
                    │   Global Admin  │
                    │  (admin-team)   │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│Platform Admin │   │   App Admin   │   │Connector Admin│
│(platform-team)│   │(app-developers)│  │(integration)  │
└───────┬───────┘   └───────┬───────┘   └───────────────┘
        │                   │
        ▼                   ▼
┌───────────────┐   ┌───────────────┐
│Platform Viewer│   │  App Deployer │
│ (developers)  │   │(release-mgrs) │
└───────────────┘   └───────────────┘
```

---

## Complete Project Structure

```
argocd/
├── applications/                    # Application definitions
│   ├── confluent-platform-prod.yaml
│   ├── flink-*.yaml
│   └── ...
├── applicationsets/                 # ApplicationSet definitions
│   ├── flink-applications.yaml
│   └── content-routers.yaml
├── projects/                        # AppProject definitions
│   ├── confluent-platform.yaml
│   ├── confluent-apps.yaml
│   ├── confluent-connectors.yaml
│   └── confluent-dev.yaml
├── rbac/                           # RBAC configuration
│   └── argocd-rbac-cm.yaml
└── monitoring/                     # Observability
    ├── servicemonitor.yaml
    └── alerting-rules.yaml
```

---

## Verification Checklist

After implementation, verify:

- [ ] All projects created: `kubectl get appprojects -n argocd`
- [ ] Applications assigned to correct projects
- [ ] Sync windows active for production projects
- [ ] RBAC groups mapped correctly
- [ ] Team members have appropriate access
- [ ] Resource restrictions enforced
- [ ] Old project removed

---

## Summary

| Project | Purpose | Team | Restrictions |
|---------|---------|------|--------------|
| `confluent-platform` | Core infrastructure | Platform | Strict sync windows |
| `confluent-apps` | Streaming applications | App Devs | Moderate restrictions |
| `confluent-connectors` | Kafka Connect | Integration | Connector CRs only |
| `confluent-dev` | Development | All | Unrestricted |

---

*Guide Version: 1.0 | Last Updated: February 2, 2026*
