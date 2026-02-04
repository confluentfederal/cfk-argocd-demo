# Sync Windows Implementation Guide

## Controlling When ArgoCD Can Deploy to Production

**Date:** February 2, 2026  
**Priority:** 3 of 6  
**Estimated Effort:** 1 hour

---

## Table of Contents

1. [Overview](#overview)
2. [Use Cases](#use-cases)
3. [Sync Window Types](#sync-window-types)
4. [Implementation](#implementation)
5. [Common Patterns](#common-patterns)
6. [Testing Sync Windows](#testing-sync-windows)
7. [Operational Procedures](#operational-procedures)
8. [Troubleshooting](#troubleshooting)

---

## Overview

Sync Windows control **when** ArgoCD can automatically or manually sync applications. They're essential for:

- Preventing deployments during business-critical hours
- Enforcing change management policies
- Coordinating maintenance windows
- Ensuring deployments only happen during monitored periods

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        Time Schedule                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Mon-Fri 10am-6pm     │████████ ALLOW ████████│                 │
│                        ─────────────────────────                 │
│  Mon-Fri 6pm-10pm     │▒▒▒▒▒▒▒ DENY ▒▒▒▒▒▒▒▒│                  │
│                        ─────────────────────────                 │
│  Weekends             │▒▒▒▒▒▒▒ DENY ▒▒▒▒▒▒▒▒│                  │
│                        ─────────────────────────                 │
│                                                                  │
│  ████ = Automated syncs allowed                                 │
│  ▒▒▒▒ = Only manual syncs (or none)                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Use Cases

| Use Case | Window Type | Schedule |
|----------|-------------|----------|
| No prod deploys after hours | Deny | 6pm-8am daily |
| No weekend deployments | Deny | Fri 6pm - Mon 8am |
| Maintenance window only | Allow | Sun 2am-6am |
| No deploys during peak | Deny | 9am-10am (morning traffic) |
| Holiday freeze | Deny | Dec 20 - Jan 2 |

---

## Sync Window Types

### Allow Windows

Only syncs during specified windows:

```yaml
- kind: allow
  schedule: '0 10 * * 1-5'  # 10am Mon-Fri
  duration: 8h               # Until 6pm
  applications:
    - '*-prod'
```

### Deny Windows

Block syncs during specified windows:

```yaml
- kind: deny
  schedule: '0 18 * * *'  # 6pm daily
  duration: 14h           # Until 8am
  applications:
    - '*-prod'
```

### Manual Sync Override

Allow manual syncs even during deny windows:

```yaml
- kind: deny
  schedule: '0 18 * * *'
  duration: 14h
  applications:
    - '*-prod'
  manualSync: true  # Allow manual sync during this window
```

---

## Implementation

### Step 1: Update AppProject

Sync windows are defined in the **AppProject**, not individual Applications.

Update `argocd/project.yaml`:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent
  namespace: argocd
spec:
  description: Confluent Platform GitOps project
  
  sourceRepos:
    - 'https://github.com/confluentfederal/*'
  
  destinations:
    - namespace: confluent
      server: https://kubernetes.default.svc
    - namespace: confluent-operator
      server: https://kubernetes.default.svc
  
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: platform.confluent.io
      kind: '*'
  
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  
  # ============================================
  # SYNC WINDOWS - Control deployment timing
  # ============================================
  syncWindows:
    # -----------------------------------------
    # Production: Business hours only
    # -----------------------------------------
    # Deny automated syncs outside business hours
    - kind: deny
      schedule: '0 18 * * *'  # 6pm daily
      duration: 14h            # Until 8am next day
      applications:
        - '*-prod'
      manualSync: true         # Allow emergency manual syncs
    
    # Deny automated syncs on weekends
    - kind: deny
      schedule: '0 0 * * 6'   # Saturday midnight
      duration: 48h            # Until Monday midnight
      applications:
        - '*-prod'
      manualSync: true
    
    # -----------------------------------------
    # Development: Always allowed
    # -----------------------------------------
    - kind: allow
      schedule: '* * * * *'   # Always
      duration: 24h
      applications:
        - '*-dev'
    
    # -----------------------------------------
    # Maintenance Windows
    # -----------------------------------------
    # Weekly maintenance window - Sunday 2am-6am
    - kind: allow
      schedule: '0 2 * * 0'   # Sunday 2am
      duration: 4h
      applications:
        - '*'
      # Full access during maintenance
      manualSync: true
```

### Step 2: Apply Changes

```bash
kubectl apply -f argocd/project.yaml
```

### Step 3: Verify Configuration

```bash
kubectl get appproject confluent -n argocd -o yaml | grep -A 50 syncWindows
```

---

## Common Patterns

### Pattern 1: Standard Business Hours

```yaml
syncWindows:
  # Allow syncs Mon-Fri 9am-5pm
  - kind: allow
    schedule: '0 9 * * 1-5'
    duration: 8h
    applications:
      - '*-prod'
    
  # Deny all other times
  - kind: deny
    schedule: '0 17 * * 1-5'  # 5pm Mon-Fri
    duration: 16h
    applications:
      - '*-prod'
    manualSync: true
    
  - kind: deny
    schedule: '0 0 * * 0,6'   # Weekends
    duration: 24h
    applications:
      - '*-prod'
    manualSync: true
```

### Pattern 2: Multiple Environments with Different Rules

```yaml
syncWindows:
  # Production: Very restricted
  - kind: deny
    schedule: '0 18 * * *'
    duration: 14h
    applications:
      - 'confluent-platform-prod'
      - '*-prod'
    manualSync: true
  
  # Staging: Allow during extended hours
  - kind: allow
    schedule: '0 6 * * 1-5'
    duration: 16h  # 6am-10pm
    applications:
      - '*-staging'
  
  # Development: Always allowed
  - kind: allow
    schedule: '* * * * *'
    duration: 24h
    applications:
      - '*-dev'
```

### Pattern 3: Change Freeze Periods

```yaml
syncWindows:
  # Holiday freeze: Dec 20 - Jan 3
  # Note: Use multiple deny windows for long periods
  - kind: deny
    schedule: '0 0 20 12 *'  # Dec 20
    duration: 336h            # 14 days
    applications:
      - '*-prod'
    manualSync: false  # No syncs at all
  
  # Quarterly earnings period
  - kind: deny
    schedule: '0 0 28-31 3,6,9,12 *'  # Last days of quarter
    duration: 72h
    applications:
      - '*-prod'
    manualSync: true
```

### Pattern 4: Cluster-Specific Windows

```yaml
syncWindows:
  # East Coast cluster: EST business hours
  - kind: allow
    schedule: '0 9 * * 1-5'  # 9am EST
    duration: 8h
    clusters:
      - 'https://east-cluster.company.com'
  
  # West Coast cluster: PST business hours
  - kind: allow
    schedule: '0 12 * * 1-5'  # 9am PST = 12pm UTC
    duration: 8h
    clusters:
      - 'https://west-cluster.company.com'
```

---

## Testing Sync Windows

### Check Active Windows

```bash
# Get current sync window status
kubectl get appproject confluent -n argocd \
  -o jsonpath='{.status.syncWindows}'
```

### Test Sync Behavior

```bash
# Attempt a sync during a deny window
argocd app sync confluent-platform-prod

# Expected output during deny window:
# FATA[0000] sync windows block synchronization
```

### View Window Status in UI

1. Navigate to ArgoCD UI
2. Click **Settings** → **Projects** → **confluent**
3. View **Sync Windows** section
4. Active windows shown with green indicator

### Simulate Window Timing

```bash
# Check what windows are active at a specific time
# Using argocd CLI:
argocd proj windows list confluent

# Output:
# ID  STATUS   KIND   SCHEDULE       DURATION  APPLICATIONS   NAMESPACES  CLUSTERS  MANUALSYNC
# 0   Active   deny   0 18 * * *     14h       *-prod                               true
# 1   Inactive allow  0 10 * * 1-5   8h        *-prod                               false
```

---

## Operational Procedures

### Emergency Deployment During Deny Window

If `manualSync: true` is set:

```bash
# Manual sync bypasses automated deny
argocd app sync confluent-platform-prod --force
```

If `manualSync: false` is set (strict freeze):

```bash
# Option 1: Temporarily modify the window
kubectl patch appproject confluent -n argocd --type=json \
  -p '[{"op": "replace", "path": "/spec/syncWindows/0/manualSync", "value": true}]'

# Perform sync
argocd app sync confluent-platform-prod

# Revert window
kubectl patch appproject confluent -n argocd --type=json \
  -p '[{"op": "replace", "path": "/spec/syncWindows/0/manualSync", "value": false}]'
```

### Adding Temporary Allow Window

For a one-time deployment outside normal hours:

```bash
# Add temporary allow window (next 2 hours)
kubectl patch appproject confluent -n argocd --type=json \
  -p '[{
    "op": "add",
    "path": "/spec/syncWindows/-",
    "value": {
      "kind": "allow",
      "schedule": "0 '"$(date -u +%H)"' '"$(date -u +%d)"' '"$(date -u +%m)"' *",
      "duration": "2h",
      "applications": ["confluent-platform-prod"]
    }
  }]'

# Perform deployment
argocd app sync confluent-platform-prod

# Remove temporary window
kubectl patch appproject confluent -n argocd --type=json \
  -p '[{"op": "remove", "path": "/spec/syncWindows/-1"}]'
```

### Documentation for On-Call

Create runbook entry:

```markdown
## Emergency Production Deployment

### During Deny Window (with manualSync: true)
1. Verify you have change approval
2. Run: `argocd app sync <app-name> --force`
3. Monitor sync status
4. Document in incident ticket

### During Strict Freeze (manualSync: false)
1. Get director/VP approval
2. Create incident ticket
3. Enable manual sync temporarily (see procedure above)
4. Perform sync
5. Revert manual sync setting
6. Document all actions
```

---

## Troubleshooting

### Sync Blocked Unexpectedly

```bash
# Check active windows
argocd proj windows list confluent

# Check application's project
kubectl get application confluent-platform-prod -n argocd \
  -o jsonpath='{.spec.project}'

# Verify app name matches window pattern
# Pattern '*-prod' matches 'confluent-platform-prod'
```

### Window Not Taking Effect

```bash
# Verify AppProject was updated
kubectl get appproject confluent -n argocd -o yaml | grep -A 30 syncWindows

# Check for typos in cron schedule
# Use: https://crontab.guru to validate

# Ensure timezone alignment (ArgoCD uses UTC)
date -u  # Check current UTC time
```

### Multiple Conflicting Windows

Rules of precedence:
1. **Deny** windows take precedence over **Allow** windows
2. More specific patterns take precedence
3. `manualSync: true` allows manual override during deny

```yaml
# Example: These windows conflict
syncWindows:
  - kind: allow
    schedule: '* * * * *'
    applications: ['*']
  
  - kind: deny
    schedule: '0 18 * * *'
    duration: 14h
    applications: ['*-prod']

# Result: *-prod blocked 6pm-8am, all others allowed
```

### Debugging Schedule Syntax

| Schedule | Description |
|----------|-------------|
| `0 10 * * 1-5` | 10:00 UTC, Mon-Fri |
| `0 18 * * *` | 18:00 UTC, every day |
| `0 0 * * 0` | Midnight UTC, Sunday |
| `0 2 * * 0` | 02:00 UTC, Sunday |
| `30 9 * * 1-5` | 09:30 UTC, Mon-Fri |

---

## Complete Project File

Save as `argocd/project.yaml`:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: confluent
  namespace: argocd
spec:
  description: Confluent Platform GitOps project
  
  sourceRepos:
    - 'https://github.com/confluentfederal/*'
  
  destinations:
    - namespace: confluent
      server: https://kubernetes.default.svc
    - namespace: confluent-operator
      server: https://kubernetes.default.svc
  
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: platform.confluent.io
      kind: '*'
  
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  
  # Orphaned resource monitoring
  orphanedResources:
    warn: true
  
  # Sync Windows
  syncWindows:
    # Production: Deny outside business hours
    - kind: deny
      schedule: '0 18 * * *'
      duration: 14h
      applications:
        - '*-prod'
      manualSync: true
    
    # Production: Deny weekends
    - kind: deny
      schedule: '0 0 * * 6'
      duration: 48h
      applications:
        - '*-prod'
      manualSync: true
    
    # Maintenance window: Sunday 2am-6am UTC
    - kind: allow
      schedule: '0 2 * * 0'
      duration: 4h
      applications:
        - '*'
      manualSync: true
```

---

## Next Steps

After completing this guide, proceed to:
- [04-PRESYNC-HOOKS.md](./04-PRESYNC-HOOKS.md) - Add validation before deployments

---

*Guide Version: 1.0 | Last Updated: February 2, 2026*
