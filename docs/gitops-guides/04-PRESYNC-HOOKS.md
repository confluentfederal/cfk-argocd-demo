# PreSync Validation Hooks Guide

## Adding Automated Checks Before Critical Deployments

**Date:** February 2, 2026  
**Priority:** 4 of 6  
**Estimated Effort:** 2-3 hours

---

## Table of Contents

1. [Overview](#overview)
2. [Hook Types](#hook-types)
3. [Use Cases](#use-cases)
4. [Implementation](#implementation)
5. [Common Validation Patterns](#common-validation-patterns)
6. [Hook Deletion Policies](#hook-deletion-policies)
7. [Advanced Patterns](#advanced-patterns)
8. [Troubleshooting](#troubleshooting)

---

## Overview

ArgoCD Resource Hooks allow you to run Kubernetes Jobs at specific points in the sync lifecycle. PreSync hooks run **before** any resources are applied, enabling:

- Validation checks before deployment
- Database migrations
- Prerequisite verification
- Smoke tests of dependencies
- Schema validation

### Sync Lifecycle

```
┌──────────────────────────────────────────────────────────────────┐
│                      ArgoCD Sync Lifecycle                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐          │
│  │ PreSync │──▶│  Sync   │──▶│PostSync │──▶│SyncFail │          │
│  │  Hooks  │   │Resources│   │  Hooks  │   │  Hooks  │          │
│  └─────────┘   └─────────┘   └─────────┘   └─────────┘          │
│       │             │             │             │                │
│       ▼             ▼             ▼             ▼                │
│   Validate     Apply all     Run smoke     Cleanup on           │
│   prereqs      manifests      tests        failure              │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Hook Types

| Hook | When It Runs | Use Case |
|------|--------------|----------|
| `PreSync` | Before sync | Validation, migrations |
| `Sync` | With main resources | Resources that need ordering |
| `PostSync` | After sync | Smoke tests, notifications |
| `SyncFail` | If sync fails | Cleanup, alerting |
| `Skip` | Never (disabled) | Temporarily disable hook |

---

## Use Cases

### For Confluent Platform

| Hook | Validates |
|------|-----------|
| Kafka Topics | Required topics exist before deploying consumers |
| Schema Registry | Schemas registered before producers start |
| Kafka Connectivity | Brokers reachable before deploying Connect |
| Flink Environment | FlinkEnvironment ready before FlinkApplication |
| Resource Quotas | Sufficient cluster resources available |

---

## Implementation

### Step 1: PreSync Hook for Topic Validation

Add to `charts/confluent-platform/templates/hooks/`:

```yaml
# charts/confluent-platform/templates/hooks/validate-kafka.yaml
{{- if .Values.hooks.validateKafka.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "confluent-platform.fullname" . }}-validate-kafka
  namespace: {{ .Values.namespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: "-5"
  labels:
    app.kubernetes.io/component: validation-hook
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/component: validation-hook
    spec:
      restartPolicy: Never
      containers:
        - name: validate-kafka
          image: confluentinc/cp-kafka:{{ .Values.kafka.image.tag | default "7.5.0" }}
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "=== Kafka PreSync Validation ==="
              
              BOOTSTRAP="{{ .Values.kafka.bootstrapServers | default "kafka:9092" }}"
              MAX_RETRIES=30
              RETRY_INTERVAL=10
              
              # Wait for Kafka to be available
              echo "Checking Kafka connectivity..."
              for i in $(seq 1 $MAX_RETRIES); do
                if kafka-broker-api-versions --bootstrap-server $BOOTSTRAP > /dev/null 2>&1; then
                  echo "✓ Kafka is reachable"
                  break
                fi
                if [ $i -eq $MAX_RETRIES ]; then
                  echo "✗ Failed to connect to Kafka after $MAX_RETRIES attempts"
                  exit 1
                fi
                echo "Attempt $i/$MAX_RETRIES - Kafka not ready, waiting..."
                sleep $RETRY_INTERVAL
              done
              
              # List existing topics
              echo ""
              echo "Existing topics:"
              kafka-topics --list --bootstrap-server $BOOTSTRAP
              
              # Validate required topics
              {{- if .Values.hooks.validateKafka.requiredTopics }}
              echo ""
              echo "Validating required topics..."
              REQUIRED_TOPICS="{{ join " " .Values.hooks.validateKafka.requiredTopics }}"
              for topic in $REQUIRED_TOPICS; do
                if kafka-topics --describe --topic $topic --bootstrap-server $BOOTSTRAP > /dev/null 2>&1; then
                  echo "✓ Topic exists: $topic"
                else
                  echo "✗ Missing required topic: $topic"
                  {{- if .Values.hooks.validateKafka.createMissingTopics }}
                  echo "  Creating topic: $topic"
                  kafka-topics --create --topic $topic \
                    --partitions {{ .Values.hooks.validateKafka.defaultPartitions | default 3 }} \
                    --replication-factor {{ .Values.hooks.validateKafka.defaultReplicationFactor | default 3 }} \
                    --bootstrap-server $BOOTSTRAP
                  echo "✓ Created topic: $topic"
                  {{- else }}
                  exit 1
                  {{- end }}
                fi
              done
              {{- end }}
              
              echo ""
              echo "=== Validation Complete ==="
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
{{- end }}
```

### Step 2: Add Values Configuration

Update `charts/confluent-platform/values.yaml`:

```yaml
# Validation hooks configuration
hooks:
  validateKafka:
    enabled: true
    requiredTopics:
      - flink-input
      - flink-output
      - content-router-input
    createMissingTopics: true
    defaultPartitions: 3
    defaultReplicationFactor: 3
  
  validateSchemaRegistry:
    enabled: true
    requiredSchemas: []
  
  validateConnect:
    enabled: true
    waitForConnectReady: true
```

### Step 3: Schema Registry Validation Hook

```yaml
# charts/confluent-platform/templates/hooks/validate-schema-registry.yaml
{{- if .Values.hooks.validateSchemaRegistry.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "confluent-platform.fullname" . }}-validate-sr
  namespace: {{ .Values.namespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: "-4"
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: validate-sr
          image: curlimages/curl:latest
          command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "=== Schema Registry Validation ==="
              
              SR_URL="{{ .Values.schemaRegistry.url | default "http://schemaregistry:8081" }}"
              MAX_RETRIES=30
              
              # Wait for Schema Registry
              echo "Checking Schema Registry connectivity..."
              for i in $(seq 1 $MAX_RETRIES); do
                if curl -s "$SR_URL/subjects" > /dev/null 2>&1; then
                  echo "✓ Schema Registry is reachable"
                  break
                fi
                if [ $i -eq $MAX_RETRIES ]; then
                  echo "✗ Failed to connect to Schema Registry"
                  exit 1
                fi
                echo "Attempt $i/$MAX_RETRIES - Schema Registry not ready..."
                sleep 10
              done
              
              # List existing subjects
              echo ""
              echo "Registered subjects:"
              curl -s "$SR_URL/subjects" | tr ',' '\n' | tr -d '[]"'
              
              {{- if .Values.hooks.validateSchemaRegistry.requiredSchemas }}
              echo ""
              echo "Validating required schemas..."
              {{- range .Values.hooks.validateSchemaRegistry.requiredSchemas }}
              if curl -s "$SR_URL/subjects/{{ . }}/versions" > /dev/null 2>&1; then
                echo "✓ Schema exists: {{ . }}"
              else
                echo "✗ Missing required schema: {{ . }}"
                exit 1
              fi
              {{- end }}
              {{- end }}
              
              echo ""
              echo "=== Schema Registry Validation Complete ==="
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
{{- end }}
```

### Step 4: Flink Environment Validation

```yaml
# charts/flink-application/templates/hooks/validate-flink-env.yaml
{{- if .Values.hooks.validateFlinkEnv.enabled | default true }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "flink-application.fullname" . }}-validate-env
  namespace: {{ .Values.namespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: "-5"
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: {{ .Values.serviceAccount | default "flink" }}
      containers:
        - name: validate-env
          image: bitnami/kubectl:latest
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "=== Flink Environment Validation ==="
              
              FLINK_ENV="{{ .Values.flinkEnvironment | default "flink-env" }}"
              NAMESPACE="{{ .Values.namespace }}"
              MAX_RETRIES=30
              
              echo "Checking FlinkEnvironment: $FLINK_ENV"
              
              for i in $(seq 1 $MAX_RETRIES); do
                STATUS=$(kubectl get flinkenvironment $FLINK_ENV -n $NAMESPACE \
                  -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                
                if [ "$STATUS" = "READY" ]; then
                  echo "✓ FlinkEnvironment is READY"
                  break
                fi
                
                if [ $i -eq $MAX_RETRIES ]; then
                  echo "✗ FlinkEnvironment not ready after $MAX_RETRIES attempts"
                  echo "  Current status: $STATUS"
                  exit 1
                fi
                
                echo "Attempt $i/$MAX_RETRIES - Status: $STATUS"
                sleep 10
              done
              
              # Verify CMF is running
              echo ""
              echo "Checking Confluent Manager for Flink..."
              CMF_STATUS=$(kubectl get deployment confluent-manager-for-apache-flink \
                -n $NAMESPACE -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
              
              if [ "$CMF_STATUS" -gt 0 ]; then
                echo "✓ CMF has $CMF_STATUS available replicas"
              else
                echo "✗ CMF not available"
                exit 1
              fi
              
              echo ""
              echo "=== Flink Environment Validation Complete ==="
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
{{- end }}
```

---

## Common Validation Patterns

### Pattern 1: Database Migration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: flyway/flyway:latest
          command:
            - flyway
            - migrate
          env:
            - name: FLYWAY_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url
```

### Pattern 2: External Service Health Check

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: check-external-deps
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: check
          image: curlimages/curl:latest
          command:
            - sh
            - -c
            - |
              # Check external API
              curl -sf https://api.external-service.com/health || exit 1
              
              # Check internal service
              curl -sf http://auth-service.internal:8080/health || exit 1
              
              echo "All dependencies healthy"
```

### Pattern 3: Resource Quota Validation

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: check-resources
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: resource-checker
      containers:
        - name: check
          image: bitnami/kubectl:latest
          command:
            - bash
            - -c
            - |
              # Get cluster capacity
              TOTAL_CPU=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.cpu}' | tr ' ' '\n' | awk '{s+=$1}END{print s}')
              TOTAL_MEM=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.memory}' | tr ' ' '\n' | sed 's/Ki//' | awk '{s+=$1}END{print s/1024/1024}')
              
              echo "Cluster resources: ${TOTAL_CPU} CPU, ${TOTAL_MEM}Gi Memory"
              
              # Check if we have enough for this deployment
              REQUIRED_CPU=4
              REQUIRED_MEM=16
              
              if [ $TOTAL_CPU -lt $REQUIRED_CPU ]; then
                echo "Insufficient CPU: need $REQUIRED_CPU, have $TOTAL_CPU"
                exit 1
              fi
              
              echo "Resource check passed"
```

---

## Hook Deletion Policies

| Policy | Behavior |
|--------|----------|
| `HookSucceeded` | Delete hook after successful completion |
| `HookFailed` | Delete hook after failure |
| `BeforeHookCreation` | Delete existing hook before creating new one |

### Recommended Configuration

```yaml
annotations:
  argocd.argoproj.io/hook: PreSync
  argocd.argoproj.io/hook-delete-policy: HookSucceeded
  # Add BeforeHookCreation to handle retries
  # argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
```

---

## Advanced Patterns

### Sync Waves with Hooks

Control order of execution:

```yaml
# Wave -10: Create namespaces and secrets
# Wave -5: Validate prerequisites
# Wave 0: Deploy main resources
# Wave 5: Post-deployment validation

annotations:
  argocd.argoproj.io/hook: PreSync
  argocd.argoproj.io/sync-wave: "-5"  # Runs before wave -4, -3, etc.
```

### Conditional Hooks

Only run in certain environments:

```yaml
{{- if eq .Values.environment "production" }}
apiVersion: batch/v1
kind: Job
metadata:
  name: production-validation
  annotations:
    argocd.argoproj.io/hook: PreSync
...
{{- end }}
```

### PostSync Smoke Tests

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: test
          image: curlimages/curl:latest
          command:
            - sh
            - -c
            - |
              # Wait for service to be ready
              sleep 30
              
              # Test endpoint
              HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://my-service:8080/health)
              
              if [ "$HTTP_CODE" = "200" ]; then
                echo "✓ Service healthy"
                exit 0
              else
                echo "✗ Service returned: $HTTP_CODE"
                exit 1
              fi
```

---

## Troubleshooting

### Hook Not Running

```bash
# Check if hook is recognized
kubectl get job -n confluent | grep validate

# Check ArgoCD application for hook status
argocd app get confluent-platform-prod --show-operation
```

### Hook Failing

```bash
# Get hook job logs
kubectl logs job/confluent-platform-validate-kafka -n confluent

# Describe job for events
kubectl describe job confluent-platform-validate-kafka -n confluent
```

### Hook Stuck

```bash
# Check pod status
kubectl get pods -n confluent | grep validate

# Force delete stuck hook
kubectl delete job confluent-platform-validate-kafka -n confluent

# Retry sync
argocd app sync confluent-platform-prod
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Hook never runs | Wrong annotation | Check `argocd.argoproj.io/hook` annotation |
| Hook runs every sync | Missing delete policy | Add `hook-delete-policy: HookSucceeded` |
| Hook timeout | Resource limits too low | Increase `backoffLimit` or resources |
| Hook fails but sync continues | Hook not blocking | Verify hook phase is `PreSync` |

### Debugging Hook Execution

```bash
# Watch hooks during sync
kubectl get jobs -n confluent -w &
argocd app sync confluent-platform-prod

# Check ArgoCD UI for hook status
# Settings → Applications → Select app → Resource Tree
# Look for Job resources with hook annotations
```

---

## Complete Hook Values Configuration

Add to `charts/confluent-platform/values.yaml`:

```yaml
# PreSync/PostSync hooks configuration
hooks:
  # Kafka validation
  validateKafka:
    enabled: true
    requiredTopics:
      - flink-input
      - flink-output
      - content-router-input
      - syslog-raw
    createMissingTopics: true
    defaultPartitions: 3
    defaultReplicationFactor: 3
  
  # Schema Registry validation
  validateSchemaRegistry:
    enabled: true
    requiredSchemas: []
  
  # Connect validation
  validateConnect:
    enabled: true
    waitForConnectReady: true
  
  # Post-deployment smoke test
  smokeTest:
    enabled: true
    endpoints:
      - url: "http://kafka:9092"
        type: tcp
      - url: "http://schemaregistry:8081/subjects"
        type: http
```

---

## Next Steps

After completing this guide, proceed to:
- [05-OBSERVABILITY.md](./05-OBSERVABILITY.md) - Set up monitoring and alerting

---

*Guide Version: 1.0 | Last Updated: February 2, 2026*
