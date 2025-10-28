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

# ⚙️ Step 3: Ensure ArgoCD installed
if ! kubectl get pods -n ${ARGOCD_NAMESPACE} | grep -q argocd-server; then
  echo "📦 Installing ArgoCD..."
  kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "⏳ Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=300s
else
  echo "✅ ArgoCD already installed."
fi

# 🌐 Step 4: Start port-forward in background (for CLI)
echo "🌐 Exposing ArgoCD API on localhost:8080..."
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443 >/dev/null 2>&1 &
sleep 10

# 🔑 Step 5: Get ArgoCD admin password
ARGO_PWD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "🔑 ArgoCD Admin Password: ${ARGO_PWD}"

# 🧠 Step 6: Ensure ArgoCD CLI installed
if ! command -v argocd &> /dev/null; then
  echo "📦 Installing ArgoCD CLI..."
  sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo chmod +x /usr/local/bin/argocd
  echo "✅ ArgoCD CLI installed globally at /usr/local/bin/argocd"
else
  echo "✅ ArgoCD CLI already installed."
fi


# 🔐 Step 7: Login via CLI
echo "🔐 Logging into ArgoCD CLI..."
argocd login localhost:8080 --username admin --password "${ARGO_PWD}" --insecure

# 🐳 Step 8: Build Docker image inside Minikube
echo "🐳 Building local Docker image..."
eval $(minikube docker-env)
docker build -t ${APP_NAME}:${IMAGE_TAG} .

# 📦 Step 9: Load image into Minikube
echo "📦 Loading image into Minikube cache..."
minikube image load ${APP_NAME}:${IMAGE_TAG}

# 🧩 Step 10: Update image tag in YAML
echo "🧩 Updating ${DEPLOY_FILE} with image tag ${IMAGE_TAG}..."
sed -i "s|image: ${APP_NAME}:.*|image: ${APP_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}

# Add imagePullPolicy if missing
if ! grep -q "imagePullPolicy" ${DEPLOY_FILE}; then
  sed -i "/image: ${APP_NAME}:${IMAGE_TAG}/a\          imagePullPolicy: Never" ${DEPLOY_FILE}
fi

grep "image:" ${DEPLOY_FILE}

# 🪣 Step 11: Commit + push to GitHub
echo "🪣 Pushing updated tag to GitHub..."
git add .
git commit -m "Auto deploy ${APP_NAME}:${IMAGE_TAG}" || true
git push

# 🚀 Step 12: Create or update ArgoCD app
if ! argocd app get ${APP_NAME} >/dev/null 2>&1; then
  echo "🚀 Creating new ArgoCD app: ${APP_NAME}"
  argocd app create ${APP_NAME} \
    --repo ${GIT_REPO_URL} \
    --path . \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace ${APP_NAMESPACE} \
    --revision ${GIT_BRANCH}
else
  echo "✅ ArgoCD app ${APP_NAME} already exists."
fi

# 🔄 Step 13: Enable auto-sync
argocd app set ${APP_NAME} --sync-policy automated --self-heal --auto-prune

# 🌀 Step 14: Sync manually
echo "🌀 Syncing app..."
argocd app sync ${APP_NAME}

# 🕵️ Step 15: Wait for deployment
echo "⏳ Waiting for pods in namespace ${APP_NAMESPACE}..."
kubectl rollout status deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=180s || true

# 🌍 Step 16: Show URL
echo "🌍 Getting service URL..."
if kubectl get svc ${APP_NAME}-service -n ${APP_NAMESPACE} >/dev/null 2>&1; then
  minikube service ${APP_NAME}-service -n ${APP_NAMESPACE} --url
else
  echo "⚠️ No service found. Check Deployment YAML or ArgoCD status."
fi

echo "=========================================="
echo "🎉 Deployment Complete!"
echo "✅ Image Tag: ${IMAGE_TAG}"
echo "✅ Namespace: ${APP_NAMESPACE}"
echo "✅ ArgoCD UI: https://localhost:8080"
echo "=========================================="
