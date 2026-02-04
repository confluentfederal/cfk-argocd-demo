# ArgoCD Observability Guide

## Setting Up Prometheus and Grafana for GitOps Monitoring

**Date:** February 2, 2026  
**Priority:** 5 of 6  
**Estimated Effort:** 3-4 hours

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Prometheus Installation](#prometheus-installation)
5. [ArgoCD Metrics Configuration](#argocd-metrics-configuration)
6. [Grafana Installation](#grafana-installation)
7. [ArgoCD Dashboard](#argocd-dashboard)
8. [Alerting Rules](#alerting-rules)
9. [Key Metrics Reference](#key-metrics-reference)
10. [Troubleshooting](#troubleshooting)

---

## Overview

A comprehensive observability stack for GitOps provides:

- **Metrics** - Quantitative data about sync status, health, and performance
- **Dashboards** - Visual representation of GitOps health
- **Alerts** - Proactive notification of issues
- **Audit** - Historical tracking of deployments

### What You'll Monitor

| Component | Metrics |
|-----------|---------|
| ArgoCD | Sync status, health, reconciliation time |
| Applications | Deploy frequency, failure rate |
| Git | Fetch latency, webhook events |
| Clusters | Resource sync status |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GitOps Observability Stack                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │   ArgoCD     │    │  Prometheus  │    │   Grafana    │          │
│  │   Metrics    │───▶│   Server     │───▶│  Dashboards  │          │
│  │   :8082      │    │              │    │              │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│                             │                                        │
│                             ▼                                        │
│                      ┌──────────────┐                               │
│                      │ AlertManager │──▶ Slack/PagerDuty/Email     │
│                      └──────────────┘                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- kubectl access with cluster-admin privileges
- Helm 3.x installed

---

## Prometheus Installation

### Option 1: kube-prometheus-stack (Recommended)

This includes Prometheus, Grafana, and AlertManager:

```bash
# Add Prometheus community helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --wait
```

### Option 2: Prometheus Operator Only

If you have existing Grafana:

```bash
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --wait
```

---

## ArgoCD Metrics Configuration

### Step 1: Enable Metrics

ArgoCD exposes metrics by default on port 8082. Verify:

```bash
# Check metrics endpoint
kubectl port-forward svc/argocd-metrics -n argocd 8082:8082 &
curl localhost:8082/metrics | head -50
```

### Step 2: Create ServiceMonitor

Create `argocd/monitoring/servicemonitor.yaml`:

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: monitoring
  labels:
    release: prometheus  # Match your Prometheus selector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  namespaceSelector:
    matchNames:
      - argocd
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-server-metrics
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  namespaceSelector:
    matchNames:
      - argocd
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-repo-server-metrics
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-repo-server
  namespaceSelector:
    matchNames:
      - argocd
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-applicationset-controller-metrics
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-applicationset-controller
  namespaceSelector:
    matchNames:
      - argocd
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

Apply the ServiceMonitors:

```bash
kubectl apply -f argocd/monitoring/servicemonitor.yaml
```

### Step 3: Verify Scraping

```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090 &

# Open browser: http://localhost:9090/targets
# Look for argocd-* targets showing "UP"
```

---

## Grafana Installation

If you used kube-prometheus-stack, Grafana is already installed.

### Access Grafana

```bash
# Get Grafana password
kubectl get secret prometheus-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo

# Port forward
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Access at http://localhost:3000
# Username: admin
# Password: (from above)
```

---

## ArgoCD Dashboard

### Import Official Dashboard

1. In Grafana, go to **Dashboards** → **Import**
2. Enter Dashboard ID: `14584` (ArgoCD official)
3. Select Prometheus data source
4. Click **Import**

### Custom GitOps Dashboard

Create a custom dashboard with these panels:

```json
{
  "dashboard": {
    "title": "GitOps Overview",
    "panels": [
      {
        "title": "Application Sync Status",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(argocd_app_info{sync_status=\"Synced\"})",
            "legendFormat": "Synced"
          },
          {
            "expr": "sum(argocd_app_info{sync_status=\"OutOfSync\"})",
            "legendFormat": "OutOfSync"
          }
        ]
      },
      {
        "title": "Application Health Status",
        "type": "piechart",
        "targets": [
          {
            "expr": "sum by (health_status) (argocd_app_info)",
            "legendFormat": "{{health_status}}"
          }
        ]
      },
      {
        "title": "Sync Operations (24h)",
        "type": "timeseries",
        "targets": [
          {
            "expr": "sum(increase(argocd_app_sync_total[24h])) by (name)",
            "legendFormat": "{{name}}"
          }
        ]
      },
      {
        "title": "Git Fetch Latency",
        "type": "timeseries",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, sum(rate(argocd_git_request_duration_seconds_bucket[5m])) by (le))",
            "legendFormat": "p95 latency"
          }
        ]
      }
    ]
  }
}
```

### Dashboard JSON (Full)

Save as `argocd/monitoring/grafana-dashboard.json`:

```json
{
  "annotations": {
    "list": []
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null }
            ]
          }
        }
      },
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "id": 1,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "targets": [
        {
          "expr": "count(argocd_app_info)",
          "legendFormat": "Total Apps"
        }
      ],
      "title": "Total Applications",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null }
            ]
          }
        }
      },
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "id": 2,
      "targets": [
        {
          "expr": "sum(argocd_app_info{sync_status=\"Synced\"})",
          "legendFormat": "Synced"
        }
      ],
      "title": "Synced Applications",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "green", "value": 0 }
            ]
          }
        }
      },
      "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
      "id": 3,
      "targets": [
        {
          "expr": "sum(argocd_app_info{sync_status=\"OutOfSync\"})",
          "legendFormat": "OutOfSync"
        }
      ],
      "title": "OutOfSync Applications",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "green", "value": 0 }
            ]
          }
        }
      },
      "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
      "id": 4,
      "targets": [
        {
          "expr": "sum(argocd_app_info{health_status!=\"Healthy\"})",
          "legendFormat": "Unhealthy"
        }
      ],
      "title": "Unhealthy Applications",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "showPoints": "auto"
          }
        }
      },
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "id": 5,
      "targets": [
        {
          "expr": "sum(increase(argocd_app_sync_total{phase=\"Succeeded\"}[1h])) by (name)",
          "legendFormat": "{{name}}"
        }
      ],
      "title": "Successful Syncs (1h)",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "linear"
          }
        }
      },
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "id": 6,
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(argocd_git_request_duration_seconds_bucket[5m])) by (le))",
          "legendFormat": "p95"
        },
        {
          "expr": "histogram_quantile(0.50, sum(rate(argocd_git_request_duration_seconds_bucket[5m])) by (le))",
          "legendFormat": "p50"
        }
      ],
      "title": "Git Fetch Latency",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      },
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 12 },
      "id": 7,
      "options": {
        "legend": {
          "displayMode": "list",
          "placement": "bottom"
        }
      },
      "targets": [
        {
          "expr": "argocd_app_info",
          "format": "table",
          "instant": true
        }
      ],
      "title": "Application Status Table",
      "type": "table",
      "transformations": [
        {
          "id": "organize",
          "options": {
            "excludeByName": {
              "Time": true,
              "Value": true,
              "__name__": true
            },
            "indexByName": {
              "name": 0,
              "project": 1,
              "sync_status": 2,
              "health_status": 3,
              "namespace": 4
            }
          }
        }
      ]
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["argocd", "gitops"],
  "templating": {
    "list": [
      {
        "current": {},
        "hide": 0,
        "includeAll": false,
        "label": "Data Source",
        "multi": false,
        "name": "datasource",
        "options": [],
        "query": "prometheus",
        "refresh": 1,
        "type": "datasource"
      }
    ]
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "title": "ArgoCD GitOps Overview",
  "uid": "argocd-gitops-overview"
}
```

### Create Dashboard ConfigMap

```yaml
# argocd/monitoring/grafana-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"  # Auto-discovered by Grafana
data:
  argocd-dashboard.json: |
    <paste dashboard JSON here>
```

---

## Alerting Rules

Create `argocd/monitoring/alerting-rules.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: argocd-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
    - name: argocd.rules
      rules:
        # Application OutOfSync
        - alert: ArgoCDAppOutOfSync
          expr: |
            argocd_app_info{sync_status="OutOfSync"} == 1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD application {{ $labels.name }} is OutOfSync"
            description: "Application {{ $labels.name }} in project {{ $labels.project }} has been OutOfSync for more than 10 minutes."
            runbook_url: "https://wiki.company.com/runbooks/argocd-outofsync"
        
        # Application Unhealthy
        - alert: ArgoCDAppUnhealthy
          expr: |
            argocd_app_info{health_status!="Healthy"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD application {{ $labels.name }} is unhealthy"
            description: "Application {{ $labels.name }} health status is {{ $labels.health_status }}."
            runbook_url: "https://wiki.company.com/runbooks/argocd-unhealthy"
        
        # Sync Failures
        - alert: ArgoCDSyncFailed
          expr: |
            increase(argocd_app_sync_total{phase="Failed"}[1h]) > 3
          for: 0m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD application {{ $labels.name }} sync failures"
            description: "Application {{ $labels.name }} has had {{ $value }} sync failures in the last hour."
        
        # Git Fetch Latency High
        - alert: ArgoCDGitFetchSlow
          expr: |
            histogram_quantile(0.95, sum(rate(argocd_git_request_duration_seconds_bucket[5m])) by (le)) > 30
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD Git fetch latency is high"
            description: "95th percentile Git fetch latency is {{ $value }}s."
        
        # Repo Server Down
        - alert: ArgoCDRepoServerDown
          expr: |
            up{job=~".*argocd-repo-server.*"} == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD Repo Server is down"
            description: "The ArgoCD Repo Server has been down for more than 1 minute."
        
        # Application Controller Down
        - alert: ArgoCDAppControllerDown
          expr: |
            up{job=~".*argocd-application-controller.*"} == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD Application Controller is down"
            description: "The ArgoCD Application Controller has been down for more than 1 minute."
        
        # High Reconciliation Queue
        - alert: ArgoCDReconciliationQueueHigh
          expr: |
            argocd_app_reconcile_bucket{le="30"} / argocd_app_reconcile_bucket{le="+Inf"} < 0.9
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD reconciliation taking too long"
            description: "Less than 90% of reconciliations complete within 30 seconds."
        
        # Production App Modified
        - alert: ArgoCDProdAppSynced
          expr: |
            increase(argocd_app_sync_total{name=~".*-prod", phase="Succeeded"}[5m]) > 0
          for: 0m
          labels:
            severity: info
          annotations:
            summary: "Production application {{ $labels.name }} was synced"
            description: "Application {{ $labels.name }} was successfully synced."
```

Apply alerting rules:

```bash
kubectl apply -f argocd/monitoring/alerting-rules.yaml
```

---

## Key Metrics Reference

### Application Metrics

| Metric | Description | Type |
|--------|-------------|------|
| `argocd_app_info` | Application information (labels) | Gauge |
| `argocd_app_sync_total` | Total syncs by phase | Counter |
| `argocd_app_reconcile` | Reconciliation latency | Histogram |
| `argocd_app_health_status` | Health status by app | Gauge |

### Git Metrics

| Metric | Description | Type |
|--------|-------------|------|
| `argocd_git_request_total` | Git requests | Counter |
| `argocd_git_request_duration_seconds` | Git request latency | Histogram |
| `argocd_git_fetch_fail_total` | Git fetch failures | Counter |

### Cluster Metrics

| Metric | Description | Type |
|--------|-------------|------|
| `argocd_cluster_info` | Cluster information | Gauge |
| `argocd_cluster_api_resource_objects` | Resources managed | Gauge |
| `argocd_cluster_events_total` | Cluster events | Counter |

### Repository Metrics

| Metric | Description | Type |
|--------|-------------|------|
| `argocd_repo_pending_request_total` | Pending requests | Gauge |

### Useful PromQL Queries

```promql
# Applications by health status
sum by (health_status) (argocd_app_info)

# Sync success rate (last 24h)
sum(increase(argocd_app_sync_total{phase="Succeeded"}[24h])) /
sum(increase(argocd_app_sync_total[24h])) * 100

# Average reconciliation time
histogram_quantile(0.5, sum(rate(argocd_app_reconcile_bucket[5m])) by (le))

# Applications out of sync for > 1 hour
argocd_app_info{sync_status="OutOfSync"} 
  unless (argocd_app_info offset 1h)

# Deployments per day by app
sum by (name) (increase(argocd_app_sync_total{phase="Succeeded"}[24h]))
```

---

## Troubleshooting

### Metrics Not Showing

```bash
# Check if metrics endpoint is exposed
kubectl get svc -n argocd | grep metrics

# Check ServiceMonitor discovery
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090
# Visit http://localhost:9090/targets
```

### Dashboard Empty

```bash
# Verify Prometheus can query ArgoCD metrics
kubectl exec -it prometheus-prometheus-kube-prometheus-prometheus-0 -n monitoring -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=argocd_app_info'

# Check Grafana data source configuration
# Grafana → Configuration → Data Sources → Prometheus
```

### Alerts Not Firing

```bash
# Check AlertManager is running
kubectl get pods -n monitoring | grep alertmanager

# View pending alerts
kubectl port-forward svc/alertmanager-main -n monitoring 9093:9093
# Visit http://localhost:9093

# Check PrometheusRule was loaded
kubectl get prometheusrule -n monitoring
kubectl describe prometheusrule argocd-alerts -n monitoring
```

---

## Complete Monitoring Stack

### Directory Structure

```
argocd/
└── monitoring/
    ├── servicemonitor.yaml
    ├── alerting-rules.yaml
    ├── grafana-dashboard.json
    └── grafana-dashboard-configmap.yaml
```

### Apply All

```bash
kubectl apply -f argocd/monitoring/
```

---

## Next Steps

After completing this guide, proceed to:
- [06-APPPROJECTS.md](./06-APPPROJECTS.md) - Implement RBAC with separate AppProjects

---

*Guide Version: 1.0 | Last Updated: February 2, 2026*
