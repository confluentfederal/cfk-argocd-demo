# Confluent Platform GitOps Demo on AWS EKS

This guide walks through deploying Confluent Platform on AWS EKS using GitOps with Argo CD.

## Prerequisites

### Required Tools
```bash
# Install AWS CLI (if not installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure

# Install eksctl
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
tar -xzf eksctl_$(uname -s)_amd64.tar.gz
sudo mv eksctl /usr/local/bin/

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installations
eksctl version
kubectl version --client
helm version
aws --version
```

### Required AWS IAM Permissions
You need the following IAM policies attached to your user:
- `EKSUserFullAccess` (custom policy with eks:*)
- `AmazonEC2FullAccess`
- `IAMFullAccess`
- `AWSCloudFormationFullAccess`

## Step 1: Create EKS Cluster

**IMPORTANT:** If you hit AWS Organization SCP restrictions blocking EKS cluster creation, contact your AWS Organization admin to:
- Grant exemption for your account, OR
- Create a cluster for you, OR  
- Provide access to an existing cluster

### Option A: Create New Cluster (Public Subnets Only - No NAT Gateway)

```bash
# Create cluster config to avoid NAT Gateway (if SCP blocks it)
cat > eks-cluster-config.yaml <<'EKSEOF'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: cfk-demo
  region: us-east-1
  version: "1.28"

vpc:
  nat:
    gateway: Disable  # Avoid NAT Gateway if blocked by SCP

managedNodeGroups:
  - name: cfk-nodes
    instanceType: m5.xlarge
    desiredCapacity: 3
    minSize: 3
    maxSize: 6
    privateNetworking: false  # Use public subnets
    volumeSize: 100
    labels:
      role: confluent
    tags:
      Environment: demo
EKSEOF

# Create the cluster (takes 15-20 minutes)
eksctl create cluster -f eks-cluster-config.yaml

# Verify cluster access
kubectl get nodes
```

### Option B: Use Existing EKS Cluster

```bash
# Update kubeconfig to access existing cluster
aws eks update-kubeconfig --region us-east-1 --name <EXISTING_CLUSTER_NAME>

# Verify access
kubectl get nodes
```

## Step 2: Install EBS CSI Driver (Required for Persistent Volumes)

```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM service account for EBS CSI driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster cfk-demo \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# Install EBS CSI driver addon
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster cfk-demo \
  --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole \
  --force

# Verify the addon
eksctl get addon --cluster cfk-demo

# Create gp3 StorageClass
cat <<SCEOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
SCEOF

# Set as default storage class
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

## Step 3: Install Confluent for Kubernetes Operator

```bash
# Create namespace for operator
kubectl create namespace confluent-operator

# Add Confluent Helm repo
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

# Install CFK operator (cluster-wide)
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent-operator \
  --set namespaced=false

# Verify operator is running
kubectl get pods -n confluent-operator
kubectl wait --for=condition=ready pod -l app=confluent-operator -n confluent-operator --timeout=120s
```

## Step 4: Install Argo CD

```bash
# Create namespace
kubectl create namespace argocd

# Install Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD Admin Password: ${ARGOCD_PASSWORD}"

# Expose Argo CD UI via LoadBalancer (AWS will create an ELB)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get the Argo CD URL (wait a minute for ELB to provision)
echo "Waiting for LoadBalancer to provision..."
sleep 60
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Argo CD UI: https://${ARGOCD_URL}"
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
```

## Step 5: Create Your GitOps Repository

This repo already exists at: `https://github.com/confluentfederal/cfk-argocd-demo`

Repository structure:
```
.
├── base/
│   ├── confluent-platform.yaml  # Base Confluent Platform resources
│   └── kustomization.yaml       # Base kustomization
├── overlays/
│   └── dev/
│       └── kustomization.yaml   # Dev overlay with customizations
└── README.md
```

## Step 6: Deploy Confluent Platform via Argo CD

### Option A: Using Argo CD UI

1. Open the Argo CD URL from Step 4
2. Login with username `admin` and the password from Step 4
3. Click **"+ NEW APP"**
4. Fill in:
   - **Application Name:** `confluent-platform`
   - **Project:** `default`
   - **Sync Policy:** 
     - ✅ Automatic
     - ✅ Prune Resources
     - ✅ Self Heal
   - **Source:**
     - **Repository URL:** `https://github.com/confluentfederal/cfk-argocd-demo.git`
     - **Revision:** `HEAD`
     - **Path:** `overlays/dev`
   - **Destination:**
     - **Cluster URL:** `https://kubernetes.default.svc`
     - **Namespace:** `confluent`
   - **Sync Options:**
     - ✅ Auto-Create Namespace
5. Click **CREATE**

### Option B: Using kubectl

```bash
cat <<APPEOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: confluent-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/confluentfederal/cfk-argocd-demo.git
    targetRevision: HEAD
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: confluent
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
APPEOF
```

## Step 7: Monitor Deployment

```bash
# Watch Argo CD sync
kubectl get application confluent-platform -n argocd -w

# Watch pods being created
kubectl get pods -n confluent -w

# Check all Confluent resources
kubectl get kafka,zookeeper,schemaregistry,controlcenter -n confluent
```

Expected deployment time: **10-15 minutes** for all components to be fully ready.

## Step 8: Access Control Center

```bash
# Expose Control Center via LoadBalancer
kubectl patch svc controlcenter -n confluent -p '{"spec": {"type": "LoadBalancer"}}'

# Get Control Center URL (wait a minute for ELB)
echo "Waiting for LoadBalancer to provision..."
sleep 60
C3_URL=$(kubectl get svc controlcenter -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Control Center: http://${C3_URL}:9021"
```

Open the URL in your browser to access Control Center.

## Step 9: Demonstrate GitOps Workflow

### Add a New Component (Schema Registry already included)

```bash
# Clone your repo
git clone https://github.com/confluentfederal/cfk-argocd-demo.git
cd cfk-argocd-demo

# Add Kafka Connect
cat >> base/confluent-platform.yaml <<'CONNEOF'
---
apiVersion: platform.confluent.io/v1beta1
kind: Connect
metadata:
  name: connect
  namespace: confluent
spec:
  replicas: 2
  image:
    application: confluentinc/cp-server-connect:7.9.0
    init: confluentinc/confluent-init-container:3.1.0
  dependencies:
    kafka:
      bootstrapEndpoint: kafka:9071
    schemaRegistry:
      url: http://schemaregistry.confluent.svc.cluster.local:8081
CONNEOF

# Commit and push
git add .
git commit -m "Add Kafka Connect"
git push
```

**Watch Argo CD automatically deploy Connect!**
- In Argo CD UI: Watch the sync happen
- In kubectl: `kubectl get pods -n confluent -w`

### Scale Kafka Cluster

```bash
# Edit the patch in overlays/dev/kustomization.yaml
# Change Kafka replicas from 3 to 5

git add .
git commit -m "Scale Kafka to 5 brokers"
git push

# Watch Argo CD scale the cluster
kubectl get pods -n confluent -l app=kafka -w
```

## Step 10: Cleanup

```bash
# Delete the Argo CD application (this removes all Confluent resources)
kubectl delete application confluent-platform -n argocd

# Wait for resources to be deleted
kubectl get pods -n confluent -w

# Delete the cluster
eksctl delete cluster --name cfk-demo --region us-east-1
```

## Troubleshooting

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n confluent
# Check for PVC binding issues or resource constraints
```

### Argo CD not syncing
```bash
# Manual sync
kubectl patch application confluent-platform -n argocd --type merge -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "normal"}}}'

# Check Argo CD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### EBS CSI issues
```bash
# Verify CSI driver is installed
kubectl get pods -n kube-system -l app=ebs-csi-controller

# Check StorageClass
kubectl get sc
```

### Control Center not accessible
```bash
# Check if pod is ready
kubectl get pods -n confluent -l app=controlcenter

# Check service
kubectl get svc controlcenter -n confluent

# Check logs
kubectl logs controlcenter-0 -n confluent --tail=50
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     AWS EKS Cluster                      │
│                                                          │
│  ┌────────────────┐         ┌──────────────────────┐   │
│  │   Argo CD      │────────▶│ Confluent Platform   │   │
│  │   (GitOps)     │         │                      │   │
│  └────────────────┘         │ • Zookeeper (3)      │   │
│         │                   │ • Kafka (3)          │   │
│         │                   │ • Schema Registry    │   │
│         ▼                   │ • Control Center     │   │
│  ┌────────────────┐         │ • Connect (optional) │   │
│  │  GitHub Repo   │         └──────────────────────┘   │
│  │  (Source of    │                                     │
│  │   Truth)       │         ┌──────────────────────┐   │
│  └────────────────┘         │  CFK Operator        │   │
│                             └──────────────────────┘   │
│                                                          │
│  ┌───────────────────────────────────────────────────┐ │
│  │              EBS Volumes (gp3)                    │ │
│  └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Demo Script for Customer

1. **Show Git Repository** - Infrastructure as Code
   - Walk through the repository structure
   - Explain base vs overlays
   - Show how Kustomize works

2. **Show Argo CD UI** - Sync status, health checks
   - Show application sync status
   - Explain the resource tree
   - Demonstrate auto-sync feature

3. **Make a change in Git** - Add component or scale
   - Edit a file locally
   - Commit and push
   - Show the commit in GitHub

4. **Watch auto-deployment** - GitOps in action
   - Watch Argo CD detect the change
   - See the sync happen automatically
   - Watch new pods being created

5. **Show Control Center** - Running Confluent Platform
   - Browse to Control Center UI
   - Show cluster health
   - Display topics, brokers, etc.

6. **Demonstrate rollback** - Revert Git commit
   - Revert the previous commit
   - Push the revert
   - Watch Argo CD roll back automatically

## Notes

- **Resource Requirements:** m5.xlarge nodes recommended (minimum 3 nodes)
- **Costs:** ~$0.50/hour for the demo cluster (stop when not in use)
- **Security:** This is a demo setup - production requires TLS, RBAC, etc.
- **Persistence:** Data persists on EBS volumes until cluster deletion
- **AWS Region:** Adjust `us-east-1` to your preferred region throughout

## Cost Optimization Tips

- Use Spot instances for worker nodes to save ~70%:
  ```yaml
  managedNodeGroups:
    - name: cfk-nodes
      instanceTypes: ["m5.xlarge"]
      spot: true
  ```
- Delete the cluster when not demoing: `eksctl delete cluster --name cfk-demo`
- Start with 1 replica for non-prod demos, scale to 3 for production-like demos

## References

- [Confluent for Kubernetes Documentation](https://docs.confluent.io/operator/current/overview.html)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [eksctl Documentation](https://eksctl.io/)
