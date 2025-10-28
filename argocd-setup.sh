#!/bin/bash
# =====================================================================
# 🚀 ArgoCD + Minikube Full Auto Deployment Script (Dynamic Build Tag)
# =====================================================================
# ✅ Starts Minikube
# ✅ Ensures ArgoCD running
# ✅ Builds local Docker image (with dynamic tag)
# ✅ Updates Deployment YAML + pushes to GitHub
# ✅ ArgoCD auto-syncs & deploys the app
# =====================================================================

set -e  # Exit on any error

# ---------------- CONFIGURATION ----------------
APP_NAME="hello-web"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
DEPLOY_FILE="deployment.yaml"
GIT_REPO_URL="https://github.com/smit-darji/argocd_cicd.git"
GIT_BRANCH="Master"   # or 'main'
IMAGE_TAG=$(date +%Y%m%d%H%M)
# ------------------------------------------------

echo "=========================================="
echo "🚀 Starting ArgoCD + WebApp Deployment"
echo "=========================================="

# 🧩 Step 1: Ensure Minikube running
if ! minikube status >/dev/null 2>&1; then
  echo "👉 Starting Minikube..."
  minikube start --driver=docker
else
  echo "✅ Minikube already running."
fi

# 🧱 Step 2: Check namespaces
kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${ARGOCD_NAMESPACE}
kubectl get ns ${APP_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${APP_NAMESPACE}

# 🐳 Step 3: Build Docker image inside Minikube
echo "🐳 Building local Docker image..."
eval $(minikube docker-env)
docker build -t ${APP_NAME}:${IMAGE_TAG} .

# 📦 Step 4: Load image into Minikube (optional)
echo "📦 Loading image into Minikube cache..."
minikube image load ${APP_NAME}:${IMAGE_TAG}

# 🧩 Step 5: Update image tag dynamically in YAML
echo "🧩 Updating ${DEPLOY_FILE} with image tag ${IMAGE_TAG}..."
sed -i "s|image: ${APP_NAME}:.*|image: ${APP_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}

# Ensure imagePullPolicy Never for local Minikube usage
if ! grep -q "imagePullPolicy" ${DEPLOY_FILE}; then
  sed -i "/image: ${APP_NAME}:${IMAGE_TAG}/a\          imagePullPolicy: Never" ${DEPLOY_FILE}
fi

grep "image:" ${DEPLOY_FILE}

# 🪣 Step 6: Commit + push changes to GitHub (GitOps trigger)
echo "🪣 Committing & pushing to GitHub..."
git add ${DEPLOY_FILE}
git commit -m "Auto deploy ${APP_NAME}:${IMAGE_TAG}"
git push origin ${GIT_BRANCH}

# 🔐 Step 7: Check ArgoCD app existence
if ! argocd app get ${APP_NAME} >/dev/null 2>&1; then
  echo "🚀 Creating new ArgoCD app: ${APP_NAME} ..."
  argocd app create ${APP_NAME} \
    --repo ${GIT_REPO_URL} \
    --path . \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace ${APP_NAMESPACE} \
    --revision ${GIT_BRANCH}
else
  echo "✅ ArgoCD app ${APP_NAME} already exists."
fi

# 🔄 Step 8: Enable auto-sync
argocd app set ${APP_NAME} --sync-policy automated --self-heal --auto-prune

# 🌀 Step 9: Sync app manually (for fresh deploy)
argocd app sync ${APP_NAME}

# 🕵️ Step 10: Wait for pod rollout
echo "⏳ Waiting for pods in namespace ${APP_NAMESPACE}..."
kubectl rollout status deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=120s || true

# 🌍 Step 11: Show service URL
echo "🌍 Checking service URL..."
if kubectl get svc ${APP_NAME}-service -n ${APP_NAMESPACE} >/dev/null 2>&1; then
  minikube service ${APP_NAME}-service -n ${APP_NAMESPACE} --url
else
  echo "⚠️ No service found — check ArgoCD or Deployment YAML."
fi

echo "=========================================="
echo "🎉 Deployment Complete!"
echo "✅ Image Tag: ${IMAGE_TAG}"
echo "✅ Namespace: ${APP_NAMESPACE}"
echo "✅ ArgoCD UI: https://localhost:8080"
echo "=========================================="
