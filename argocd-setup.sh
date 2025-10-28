#!/bin/bash

# --------------------------------------------------------
# 🚀 ArgoCD Setup & GitOps Deployment Script for Minikube
# --------------------------------------------------------
# This script will:
# 1️⃣ Start Minikube
# 2️⃣ Install ArgoCD
# 3️⃣ Port-forward dashboard
# 4️⃣ Deploy app from GitHub repo
# 5️⃣ Enable auto-sync (CI/CD)
# --------------------------------------------------------

set -e  # Stop on error

# 🔧 CONFIGURATION
ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="webapps"
APP_NAME="hello-web"
GIT_REPO_URL="https://github.com/<your-username>/k8s-webapp.git"  # <-- CHANGE THIS
GIT_REPO_PATH="."   # path inside repo where k8s yaml files live (e.g. ./k8s)
GIT_BRANCH="main"

echo "=========================================="
echo "🚀 Starting ArgoCD Setup for Kubernetes CI/CD"
echo "=========================================="

# 🧹 Step 1: Start Minikube
echo "👉 Starting Minikube..."
minikube start --driver=docker

# 🧩 Step 2: Create namespaces
echo "👉 Creating namespaces..."
kubectl create namespace ${ARGOCD_NAMESPACE} || true
kubectl create namespace ${APP_NAMESPACE} || true

# ⚙️ Step 3: Install ArgoCD
echo "👉 Installing ArgoCD..."
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ⏳ Wait for ArgoCD pods
echo "⏳ Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=180s

# 🌐 Step 4: Port-forward ArgoCD dashboard (in background)
echo "🌐 Starting ArgoCD Dashboard on https://localhost:8080 ..."
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443 >/dev/null 2>&1 &
sleep 5

# 🔑 Step 5: Retrieve initial admin password
echo "🔑 Getting ArgoCD admin password..."
ARGO_PWD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "=========================================="
echo "ArgoCD UI: https://localhost:8080"
echo "Username : admin"
echo "Password : ${ARGO_PWD}"
echo "=========================================="

# 🧠 Step 6: Install ArgoCD CLI (if missing)
if ! command -v argocd &> /dev/null; then
  echo "📦 Installing ArgoCD CLI (user local path)..."
  curl -sSL -o ~/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x ~/argocd
  export PATH=$PATH:~
  echo "✅ ArgoCD CLI installed at ~/argocd"
else
  echo "✅ ArgoCD CLI already installed."
fi

# ⏳ Step 7: Wait for dashboard
echo "⌛ Waiting for ArgoCD server to be ready..."
sleep 20

# 🔐 Step 8: Login ArgoCD CLI
echo "🔐 Logging into ArgoCD CLI..."
argocd login localhost:8080 --username admin --password "${ARGO_PWD}" --insecure

# 🚀 Step 9: Create ArgoCD Application
echo "🚀 Creating ArgoCD application: ${APP_NAME}"
argocd app create ${APP_NAME} \
  --repo ${GIT_REPO_URL} \
  --path ${GIT_REPO_PATH} \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace ${APP_NAMESPACE} \
  --revision ${GIT_BRANCH}

# 🔄 Step 10: Enable Auto-Sync
echo "🔄 Enabling auto-sync for ${APP_NAME}..."
argocd app set ${APP_NAME} --sync-policy automated --self-heal --auto-prune

# ✅ Step 11: Sync app for first deployment
echo "✅ Syncing application..."
argocd app sync ${APP_NAME}

# 📊 Step 12: Verify deployment
echo "📊 Checking deployed resources..."
kubectl get all -n ${APP_NAMESPACE}

echo "🎉 DONE!"
echo "=========================================="
echo "🌐 ArgoCD Dashboard: https://localhost:8080"
echo "🧭 App Name: ${APP_NAME}"
echo "💾 Repo: ${GIT_REPO_URL}"
echo "=========================================="
