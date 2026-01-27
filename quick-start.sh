#!/bin/bash
# Quick Start Script for Local k3d Deployment
# Usage: ./quick-start.sh

set -e

echo "🚀 Confluent Platform GitOps Demo - Quick Start"
echo "================================================"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed. Aborting." >&2; exit 1; }

echo "✅ Prerequisites check passed"
echo ""

# Install k3d if not present
if ! command -v k3d &> /dev/null; then
    echo "📦 Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# Install Helm if not present
if ! command -v helm &> /dev/null; then
    echo "📦 Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Create k3d cluster
echo "🏗️  Creating k3d cluster..."
k3d cluster create cfk-demo --agents 3 || echo "Cluster may already exist, continuing..."

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Install CFK Operator
echo "📦 Installing Confluent for Kubernetes Operator..."
helm repo add confluentinc https://packages.confluent.io/helm || true
helm repo update

kubectl create namespace confluent-operator --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent-operator \
  --set namespaced=false \
  --wait

echo "⏳ Waiting for CFK operator to be ready..."
kubectl wait --for=condition=ready pod -l app=confluent-operator -n confluent-operator --timeout=120s

# Install Argo CD
echo "📦 Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for Argo CD to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get Argo CD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Deploy Confluent Platform
echo "🚀 Deploying Confluent Platform..."
kubectl apply -k overlays/dev

echo ""
echo "✅ Deployment Complete!"
echo "======================="
echo ""
echo "📊 Monitor deployment:"
echo "   kubectl get pods -n confluent -w"
echo ""
echo "🎛️  Argo CD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   URL: https://localhost:8080"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "🎮 Control Center (once ready):"
echo "   kubectl port-forward controlcenter-0 9021:9021 -n confluent"
echo "   URL: http://localhost:9021"
echo ""
echo "⏳ Full deployment takes 10-15 minutes"
echo "   Watch progress: kubectl get pods -n confluent -w"
echo ""
