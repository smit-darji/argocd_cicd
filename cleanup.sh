#!/bin/bash
set -e

# ============================================================
# 🧹 CLEANUP SCRIPT — RESET FULL GITOPS ENVIRONMENT
# Author: Smit Darji
# ============================================================

APP_NAME="k8s-app"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
IMAGE_NAME="smitdarji/k8s"

echo "============================================"
echo "🧹 CLEANUP STARTED..."
echo "============================================"

# --- Delete ArgoCD Application ---
echo "🗑️  Deleting ArgoCD Application..."
kubectl delete application ${APP_NAME}-app -n ${ARGOCD_NAMESPACE} --ignore-not-found=true || true

# --- Delete app namespace ---
echo "🗑️  Deleting Application Namespace (${APP_NAMESPACE})..."
kubectl delete namespace ${APP_NAMESPACE} --ignore-not-found=true || true

# --- Delete ArgoCD namespace ---
echo "🗑️  Deleting ArgoCD Namespace (${ARGOCD_NAMESPACE})..."
kubectl delete namespace ${ARGOCD_NAMESPACE} --ignore-not-found=true || true

# --- Delete Minikube cluster ---
if minikube status >/dev/null 2>&1; then
  echo "🧨 Deleting Minikube cluster..."
  minikube delete
else
  echo "⚠️  Minikube not running — skipping delete."
fi

# --- Clean Docker images & containers ---
echo "🐳 Cleaning up Docker containers and images..."
docker container prune -f || true
docker image prune -a -f || true
docker volume prune -f || true
docker network prune -f || true

# --- Remove any Kubernetes config cache ---
echo "🧾 Removing local kubeconfig cache..."
rm -rf ~/.kube/cache || true
rm -rf ~/.minikube || true

echo "============================================"
echo "✅ CLEANUP COMPLETE!"
echo "System is now fresh and ready for a new deployment."
echo "============================================"