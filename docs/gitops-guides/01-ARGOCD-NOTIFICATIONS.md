# ArgoCD Notifications Setup Guide

## Integrating ArgoCD with GitLab for Pipeline Status Updates

**Date:** February 2, 2026  
**Priority:** 1 of 6  
**Estimated Effort:** 1-2 hours

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [GitLab Configuration](#gitlab-configuration)
5. [Slack Configuration (Optional)](#slack-configuration-optional)
6. [Notification Templates](#notification-templates)
7. [Trigger Configuration](#trigger-configuration)
8. [Testing](#testing)
9. [Troubleshooting](#troubleshooting)

---

## Overview

ArgoCD Notifications enables you to:
- Update GitLab commit/MR status based on deployment state
- Send Slack alerts for sync failures or health issues
- Trigger webhooks for custom integrations
- Create audit trails of deployment events

### Architecture

```
┌─────────────┐     ┌─────────────────────┐     ┌─────────────┐
│   ArgoCD    │────▶│ ArgoCD Notifications│────▶│   GitLab    │
│  (Events)   │     │    Controller       │     │   (Status)  │
└─────────────┘     └─────────────────────┘     └─────────────┘
                              │
                              ├────────────────▶ Slack
                              │
                              └────────────────▶ Webhooks
```

---

## Prerequisites

- ArgoCD v2.4+ (notifications included by default)
- GitLab personal access token with `api` scope
- kubectl access to ArgoCD namespace

### Verify ArgoCD Version

```bash
kubectl get deployment argocd-server -n argocd \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## Installation

### Step 1: Create GitLab Token Secret

```bash
# Create a GitLab Personal Access Token with 'api' scope
# Store it as a Kubernetes secret

kubectl create secret generic argocd-notifications-secret \
  -n argocd \
  --from-literal=gitlab-token=<your-gitlab-token>
```

### Step 2: Configure Notification Services

```yaml
# argocd-notifications-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # GitLab Service Configuration
  service.gitlab: |
    token: $gitlab-token
    baseUrl: https://gitlab.company.com
  
  # Slack Service Configuration (optional)
  service.slack: |
    token: $slack-token
    
  # Webhook Service Configuration (optional)
  service.webhook.deployment-tracker: |
    url: https://your-webhook-endpoint.com/deployments
    headers:
      - name: Authorization
        value: Bearer $webhook-token
```

Apply the configuration:

```bash
kubectl apply -f argocd-notifications-cm.yaml
```

---

## GitLab Configuration

### Commit Status Updates

This updates the commit status in GitLab, showing deployment state directly in merge requests.

```yaml
# Add to argocd-notifications-cm.yaml data section
data:
  # ... existing config ...
  
  template.gitlab-commit-status: |
    webhook:
      gitlab:
        method: POST
        path: /api/v4/projects/{{call .repo.FullNameByRepoURL .app.spec.source.repoURL | urlencode}}/statuses/{{.app.status.sync.revision}}
        body: |
          {
            "state": "{{if eq .app.status.sync.status \"Synced\"}}success{{else if eq .app.status.sync.status \"OutOfSync\"}}pending{{else}}failed{{end}}",
            "target_url": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
            "description": "ArgoCD: {{.app.status.sync.status}} / {{.app.status.health.status}}",
            "context": "argocd/{{.app.metadata.name}}"
          }
```

### Merge Request Comments

Post deployment updates as comments on merge requests:

```yaml
  template.gitlab-mr-comment: |
    webhook:
      gitlab:
        method: POST
        path: /api/v4/projects/{{call .repo.FullNameByRepoURL .app.spec.source.repoURL | urlencode}}/merge_requests/{{.app.metadata.annotations.gitlab-mr-id}}/notes
        body: |
          {
            "body": "## ArgoCD Deployment Update\n\n**Application:** {{.app.metadata.name}}\n**Status:** {{.app.status.sync.status}}\n**Health:** {{.app.status.health.status}}\n**Revision:** {{.app.status.sync.revision}}\n\n[View in ArgoCD]({{.context.argocdUrl}}/applications/{{.app.metadata.name}})"
          }
```

---

## Slack Configuration (Optional)

### Step 1: Create Slack App

1. Go to https://api.slack.com/apps
2. Create New App → From scratch
3. Add OAuth Scope: `chat:write`
4. Install to Workspace
5. Copy Bot User OAuth Token

### Step 2: Add Slack Secret

```bash
kubectl create secret generic argocd-notifications-secret \
  -n argocd \
  --from-literal=gitlab-token=<gitlab-token> \
  --from-literal=slack-token=<slack-bot-token> \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 3: Configure Slack Templates

```yaml
  template.slack-sync-status: |
    message: |
      {{if eq .app.status.sync.status "Synced"}}:white_check_mark:{{else if eq .app.status.sync.status "OutOfSync"}}:warning:{{else}}:x:{{end}} *{{.app.metadata.name}}*
      Sync Status: {{.app.status.sync.status}}
      Health: {{.app.status.health.status}}
      <{{.context.argocdUrl}}/applications/{{.app.metadata.name}}|View in ArgoCD>
    slack:
      attachments: |
        [{
          "color": "{{if eq .app.status.sync.status \"Synced\"}}good{{else if eq .app.status.sync.status \"OutOfSync\"}}warning{{else}}danger{{end}}",
          "fields": [
            {"title": "Application", "value": "{{.app.metadata.name}}", "short": true},
            {"title": "Environment", "value": "{{.app.metadata.labels.environment}}", "short": true},
            {"title": "Revision", "value": "{{.app.status.sync.revision | substr 0 7}}", "short": true},
            {"title": "Sync Status", "value": "{{.app.status.sync.status}}", "short": true}
          ]
        }]
```

---

## Notification Templates

### Complete Template Collection

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # Services
  service.gitlab: |
    token: $gitlab-token
    baseUrl: https://gitlab.company.com
  
  service.slack: |
    token: $slack-token
  
  # Context (ArgoCD URL for links)
  context: |
    argocdUrl: https://argocd.company.com

  # Templates
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} is now synced and healthy.
    slack:
      attachments: |
        [{
          "color": "good",
          "title": "{{.app.metadata.name}} Deployed Successfully",
          "fields": [
            {"title": "Revision", "value": "{{.app.status.sync.revision | substr 0 7}}", "short": true},
            {"title": "Environment", "value": "{{.app.metadata.labels.environment}}", "short": true}
          ]
        }]

  template.app-health-degraded: |
    message: |
      :warning: Application {{.app.metadata.name}} health is degraded.
    slack:
      attachments: |
        [{
          "color": "danger",
          "title": "{{.app.metadata.name}} Health Degraded",
          "text": "Application health status changed to {{.app.status.health.status}}",
          "fields": [
            {"title": "Health Status", "value": "{{.app.status.health.status}}", "short": true},
            {"title": "Sync Status", "value": "{{.app.status.sync.status}}", "short": true}
          ]
        }]

  template.app-sync-failed: |
    message: |
      :x: Application {{.app.metadata.name}} sync failed.
    slack:
      attachments: |
        [{
          "color": "danger",
          "title": "{{.app.metadata.name}} Sync Failed",
          "text": "{{.app.status.operationState.message}}",
          "fields": [
            {"title": "Sync Status", "value": "{{.app.status.sync.status}}", "short": true},
            {"title": "Started", "value": "{{.app.status.operationState.startedAt}}", "short": true}
          ]
        }]

  template.app-sync-running: |
    message: |
      :arrows_counterclockwise: Application {{.app.metadata.name}} sync in progress.
    slack:
      attachments: |
        [{
          "color": "warning",
          "title": "{{.app.metadata.name}} Syncing",
          "fields": [
            {"title": "Target Revision", "value": "{{.app.spec.source.targetRevision}}", "short": true}
          ]
        }]

  template.gitlab-commit-status: |
    webhook:
      gitlab:
        method: POST
        path: /api/v4/projects/{{call .repo.FullNameByRepoURL .app.spec.source.repoURL | urlencode}}/statuses/{{.app.status.sync.revision}}
        body: |
          {
            "state": "{{if eq .app.status.sync.status \"Synced\"}}success{{else if eq .app.status.sync.status \"OutOfSync\"}}pending{{else}}failed{{end}}",
            "target_url": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
            "description": "ArgoCD: {{.app.status.sync.status}} / {{.app.status.health.status}}",
            "context": "argocd/{{.app.metadata.name}}"
          }
```

---

## Trigger Configuration

### Define When Notifications Fire

```yaml
  # Triggers - define when to send notifications
  trigger.on-deployed: |
    - when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
      send: [app-deployed, gitlab-commit-status]
  
  trigger.on-health-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [app-health-degraded]
  
  trigger.on-sync-failed: |
    - when: app.status.sync.status == 'Unknown' or app.status.operationState.phase == 'Failed'
      send: [app-sync-failed, gitlab-commit-status]
  
  trigger.on-sync-running: |
    - when: app.status.operationState.phase == 'Running'
      send: [app-sync-running]
  
  trigger.on-sync-status-change: |
    - when: app.status.sync.status != 'Synced'
      send: [gitlab-commit-status]
```

---

## Testing

### Step 1: Annotate an Application

```bash
# Subscribe an application to notifications
kubectl patch application confluent-platform-prod -n argocd \
  --type merge -p '{
    "metadata": {
      "annotations": {
        "notifications.argoproj.io/subscribe.on-deployed.slack": "#deployments",
        "notifications.argoproj.io/subscribe.on-sync-failed.slack": "#alerts",
        "notifications.argoproj.io/subscribe.on-deployed.gitlab": ""
      }
    }
  }'
```

### Step 2: Force a Sync to Test

```bash
# Trigger a sync
kubectl annotate application confluent-platform-prod -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Watch for notification controller logs
kubectl logs -l app.kubernetes.io/name=argocd-notifications-controller \
  -n argocd -f
```

### Step 3: Verify in GitLab

1. Navigate to the repository
2. Click on the latest commit
3. Verify the ArgoCD status appears

---

## Troubleshooting

### Check Notification Controller Logs

```bash
kubectl logs -l app.kubernetes.io/name=argocd-notifications-controller \
  -n argocd --tail=100
```

### Verify Secret Configuration

```bash
kubectl get secret argocd-notifications-secret -n argocd -o yaml
```

### Test GitLab API Connectivity

```bash
# From within the cluster
kubectl run test-gitlab --rm -it --image=curlimages/curl -- \
  curl -H "PRIVATE-TOKEN: <token>" \
  https://gitlab.company.com/api/v4/projects
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Notifications not firing | App not subscribed | Add subscription annotation |
| GitLab 401 error | Invalid token | Regenerate PAT with `api` scope |
| Slack not posting | Wrong channel | Verify channel name (no #) |
| Template errors | Invalid Go template | Check logs for template errors |

### Debug Mode

Enable debug logging:

```yaml
# Edit argocd-notifications-controller deployment
spec:
  template:
    spec:
      containers:
        - name: argocd-notifications-controller
          args:
            - /app/argocd-notifications-controller
            - --loglevel=debug
```

---

## Complete Configuration File

Save this as `argocd/notifications/argocd-notifications-config.yaml`:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
type: Opaque
stringData:
  gitlab-token: "<your-gitlab-token>"
  slack-token: "<your-slack-token>"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.gitlab: |
    token: $gitlab-token
    baseUrl: https://gitlab.company.com
  
  service.slack: |
    token: $slack-token
  
  context: |
    argocdUrl: https://argocd.company.com
  
  template.app-deployed: |
    message: Application {{.app.metadata.name}} deployed successfully.
    slack:
      attachments: |
        [{"color": "good", "title": "{{.app.metadata.name}} Deployed", "fields": [{"title": "Revision", "value": "{{.app.status.sync.revision | substr 0 7}}", "short": true}]}]
  
  template.app-sync-failed: |
    message: Application {{.app.metadata.name}} sync failed.
    slack:
      attachments: |
        [{"color": "danger", "title": "{{.app.metadata.name}} Failed", "text": "{{.app.status.operationState.message}}"}]
  
  template.gitlab-commit-status: |
    webhook:
      gitlab:
        method: POST
        path: /api/v4/projects/{{call .repo.FullNameByRepoURL .app.spec.source.repoURL | urlencode}}/statuses/{{.app.status.sync.revision}}
        body: |
          {"state": "{{if eq .app.status.sync.status \"Synced\"}}success{{else}}failed{{end}}", "target_url": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}", "context": "argocd/{{.app.metadata.name}}"}
  
  trigger.on-deployed: |
    - when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
      send: [app-deployed, gitlab-commit-status]
  
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase == 'Failed'
      send: [app-sync-failed, gitlab-commit-status]
```

---

## Next Steps

After completing this guide, proceed to:
- [02-APPLICATIONSETS.md](./02-APPLICATIONSETS.md) - Reduce manual Application creation

---

*Guide Version: 1.0 | Last Updated: February 2, 2026*
