#!/bin/bash
# =====================================================================
# 🚀 ArgoCD + Minikube Full Auto Deployment Script (Simplified & Fixed)
# =====================================================================
# ✅ Starts Minikube
# ✅ Installs & exposes ArgoCD
# ✅ Builds local Docker image
# ✅ Updates deployment.yaml dynamically
# ✅ Pushes changes to GitHub
# ✅ Deploys & syncs via ArgoCD
# =====================================================================

set -e  # Exit on any error

# ---------------- CONFIGURATION ----------------
APP_NAME="hello-web"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
DEPLOY_FILE="deployment.yaml"
GIT_REPO_URL="https://github.com/smit-darji/argocd_cicd.git"
GIT_BRANCH="Master"
IMAGE_TAG="v1"
# ------------------------------------------------

echo "=========================================="
echo "🚀 Starting ArgoCD + WebApp Deployment"
echo "=========================================="

# 🧩 Step 1: Start Minikube
if ! minikube status >/dev/null 2>&1; then
  echo "👉 Starting Minikube..."
  minikube start --driver=docker
else
  echo "✅ Minikube already running."
fi

# 🧱 Step 2: Create namespaces if missing
kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${ARGOCD_NAMESPACE}
kubectl get ns ${APP_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${APP_NAMESPACE}

# ⚙️ Step 3: Install ArgoCD
if ! kubectl get pods -n ${ARGOCD_NAMESPACE} | grep -q argocd-server; then
  echo "📦 Installing ArgoCD..."
  kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "⏳ Waiting for ArgoCD pods..."
  kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=300s
else
  echo "✅ ArgoCD already installed."
fi

# 🌐 Step 4: Expose ArgoCD API
echo "🌐 Exposing ArgoCD API on localhost:8080..."
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443 >/dev/null 2>&1 &

# ✅ Wait for port-forward to be active
echo "⏳ Waiting for ArgoCD API..."
for i in {1..20}; do
  if nc -z localhost 8080 2>/dev/null; then
    echo "✅ ArgoCD API is reachable on localhost:8080"
    break
  fi
  echo "⌛ Retrying in 3s..."
  sleep 3
done

if ! nc -z localhost 8080 2>/dev/null; then
  echo "❌ Failed to connect to ArgoCD API. Try manual port-forward:"
  echo "👉 kubectl port-forward svc/argocd-server -n argocd 8080:443"
  exit 1
fi

# 🔑 Step 5: Get ArgoCD admin password
ARGO_PWD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "🔑 ArgoCD Admin Password: ${ARGO_PWD}"

# 🧠 Step 6: Ensure ArgoCD CLI is installed
if ! command -v argocd &> /dev/null; then
  echo "📦 Installing ArgoCD CLI..."
  sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo chmod +x /usr/local/bin/argocd
else
  echo "✅ ArgoCD CLI already installed."
fi

# 🔐 Step 7: Login to ArgoCD
echo "🔐 Logging into ArgoCD CLI..."
argocd login localhost:8080 --username admin --password "${ARGO_PWD}" --insecure

# 🐳 Step 8: Build Docker image inside Minikube
echo "🐳 Building Docker image inside Minikube..."
eval $(minikube docker-env)
docker build -t ${APP_NAME}:${IMAGE_TAG} .

# 📦 Step 9: Load image into Minikube
echo "📦 Loading image into Minikube cache..."
minikube image load ${APP_NAME}:${IMAGE_TAG}

# 🧩 Step 10: Update deployment.yaml
echo "🧩 Updating ${DEPLOY_FILE}..."
sed -i "s|image:.*|image: ${APP_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}
if grep -q "imagePullPolicy" ${DEPLOY_FILE}; then
  sed -i "s|imagePullPolicy:.*|imagePullPolicy: Never|g" ${DEPLOY_FILE}
else
  sed -i "/image: ${APP_NAME}:${IMAGE_TAG}/a\        imagePullPolicy: Never" ${DEPLOY_FILE}
fi
echo "✅ Deployment file updated."

# 🪣 Step 11: Commit & push changes
echo "🪣 Pushing to GitHub..."
if ! git diff --quiet; then
  git add .
  git commit -m "Auto deploy ${APP_NAME}:${IMAGE_TAG}"
  git push origin ${GIT_BRANCH}
else
  echo "ℹ️ No changes to commit."
fi

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
  echo "✅ ArgoCD app ${APP_NAME} already exists. Updating..."
fi

# 🔄 Step 13: Enable auto-sync
argocd app set ${APP_NAME} --sync-policy automated --self-heal --auto-prune

# 🌀 Step 14: Sync app
echo "🌀 Syncing app..."
argocd app sync ${APP_NAME}

# 🕵️ Step 15: Wait for rollout
echo "⏳ Waiting for rollout..."
kubectl rollout status deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=180s || true

# 🌍 Step 16: Get service URL
echo "🌍 Getting service URL..."
SERVICE_URL=$(minikube service ${APP_NAME}-service -n ${APP_NAMESPACE} --url | head -n1)
if [ -n "$SERVICE_URL" ]; then
  echo "✅ Application running at: ${SERVICE_URL}"
else
  echo "⚠️ No service found. Check your service.yaml."
fi

echo "=========================================="
echo "🎉 Deployment Complete!"
echo "✅ Image Tag: ${IMAGE_TAG}"
echo "✅ Namespace: ${APP_NAMESPACE}"
echo "✅ ArgoCD UI: https://localhost:8080"
echo "=========================================="
