#!/bin/bash
# =====================================================================
# 🚀 ArgoCD + Minikube Full Auto Deployment Script (Latest Version)
# =====================================================================
# ✅ Starts Minikube
# ✅ Ensures ArgoCD is installed and running
# ✅ Builds local Docker image (with dynamic timestamp tag)
# ✅ Updates Deployment YAML automatically
# ✅ Pushes changes to GitHub
# ✅ Deploys app via ArgoCD and opens browser URL
# =====================================================================

set -e  # Exit on any error

# ---------------- CONFIGURATION ----------------
APP_NAME="hello-web"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
DEPLOY_FILE="deployment.yaml"
GIT_REPO_URL="https://github.com/smit-darji/argocd_cicd.git"
GIT_BRANCH="Master"   # or 'main'
IMAGE_TAG="v1"
# ------------------------------------------------

echo "=========================================="
echo "🚀 Starting ArgoCD + WebApp Deployment"
echo "=========================================="

# 🧩 Step 1: Ensure Minikube is running
if ! minikube status >/dev/null 2>&1; then
  echo "👉 Starting Minikube..."
  minikube start --driver=docker
else
  echo "✅ Minikube already running."
fi

# 🧱 Step 2: Ensure namespaces exist
kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${ARGOCD_NAMESPACE}
kubectl get ns ${APP_NAMESPACE} >/dev/null 2>&1 || kubectl create ns ${APP_NAMESPACE}

# ⚙️ Step 3: Install ArgoCD if not present
if ! kubectl get pods -n ${ARGOCD_NAMESPACE} | grep -q argocd-server; then
  echo "📦 Installing ArgoCD..."
  kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "⏳ Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=300s
else
  echo "✅ ArgoCD already installed."
fi

# 🌐 Step 4: Expose ArgoCD API on localhost
echo "🌐 Exposing ArgoCD API on localhost:8080..."
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443 >/dev/null 2>&1 &

# Wait until the API is ready
echo "⏳ Waiting for ArgoCD API to be available..."
for i in {1..30}; do
  if nc -z localhost 8080 2>/dev/null; then
    echo "✅ ArgoCD API is available on localhost:8080"
    break
  fi
  sleep 2
done


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

# 🔐 Step 7: Login to ArgoCD CLI
echo "🔐 Logging into ArgoCD CLI..."
argocd login localhost:8080 --username admin --password "${ARGO_PWD}" --insecure

# 🐳 Step 8: Build Docker image inside Minikube
echo "🐳 Building Docker image inside Minikube..."
eval $(minikube docker-env)
docker build -t ${APP_NAME}:${IMAGE_TAG} .

# 📦 Step 9: Load image into Minikube
echo "📦 Loading image into Minikube cache..."
minikube image load ${APP_NAME}:${IMAGE_TAG}

# 🧩 Step 10: Update image tag dynamically in deployment file
echo "🧩 Updating ${DEPLOY_FILE} with image tag ${IMAGE_TAG}..."

# Fix indentation and structure
yq eval -i ".spec.template.spec.containers[0].image = \"${APP_NAME}:${IMAGE_TAG}\"" ${DEPLOY_FILE} 2>/dev/null || {
  # Fallback if yq not installed
  sed -i "s|image:.*|image: ${APP_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}
}

# Ensure imagePullPolicy: Never
if grep -q "imagePullPolicy" ${DEPLOY_FILE}; then
  sed -i "s|imagePullPolicy:.*|imagePullPolicy: Never|g" ${DEPLOY_FILE}
else
  sed -i "/image: ${APP_NAME}:${IMAGE_TAG}/a\        imagePullPolicy: Never" ${DEPLOY_FILE}
fi

echo "✅ Updated deployment.yaml:"
echo "🧩 Updating image tag in ${DEPLOY_FILE}..."
sed -i "s|image: ${APP_NAME}:.*|image: ${APP_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}
grep "image:" ${DEPLOY_FILE}


# 🪣 Step 11: Commit and push to GitHub
echo "🪣 Checking for Git changes..."
if ! git diff --quiet; then
  git add .
  git commit -m "Auto deploy ${APP_NAME}:${IMAGE_TAG}"
  git push origin ${GIT_BRANCH}
  echo "✅ Changes pushed to GitHub."
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

# 🔄 Step 13: Enable auto-sync & self-heal
argocd app set ${APP_NAME} --sync-policy automated --self-heal --auto-prune

# 🌀 Step 14: Trigger sync manually
echo "🌀 Syncing ArgoCD app..."
argocd app sync ${APP_NAME}

# 🕵️ Step 15: Wait for rollout
echo "⏳ Waiting for deployment rollout..."
kubectl rollout status deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=180s || true

# 🌍 Step 16: Get and open app URL
echo "🌍 Getting service URL..."
SERVICE_URL=$(minikube service ${APP_NAME}-service -n ${APP_NAMESPACE} --url | head -n1)
if [ -n "$SERVICE_URL" ]; then
  echo "✅ Application running at: ${SERVICE_URL}"
  xdg-open "${SERVICE_URL}" >/dev/null 2>&1 || open "${SERVICE_URL}" || true
else
  echo "⚠️ No service found. Check your service.yaml or ArgoCD deployment."
fi

echo "=========================================="
echo "🎉 Deployment Complete!"
echo "✅ Image Tag: ${IMAGE_TAG}"
echo "✅ Namespace: ${APP_NAMESPACE}"
echo "✅ ArgoCD UI: https://localhost:8080"
echo "=========================================="
