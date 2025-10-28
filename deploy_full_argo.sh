#!/bin/bash
set -e

# ============================================================
# 🚀 FULL GITOPS PIPELINE — DOCKER + KUBERNETES + ARGOCD
# Author: Smit Darji
# ============================================================

APP_NAME="login-page"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
DEPLOY_FILE="k8s/deployment.yaml"
GIT_REPO_URL="https://github.com/smit-darji/argocd_cicd.git"
GIT_BRANCH="Master"
IMAGE_NAME="smitdarji/k8s"
IMAGE_TAG="v0.0.6"
APP_PATH="k8s"

echo "🚀 Starting deployment for ${APP_NAME}..."

# --- Start Minikube if needed ---
if ! minikube status >/dev/null 2>&1; then
  echo "🧩 Starting Minikube..."
  minikube start --driver=docker
else
  echo "✅ Minikube is already running."
fi

# --- Ensure ArgoCD is installed ---
if ! kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1; then
  echo "📦 Installing ArgoCD..."
  kubectl create namespace ${ARGOCD_NAMESPACE}
  kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "⏳ Waiting for ArgoCD pods..."
  kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=300s || true
else
  echo "✅ ArgoCD is already installed."
fi

# --- Expose ArgoCD Server via NodePort ---
echo "🌐 Exposing ArgoCD server..."
kubectl patch svc argocd-server -n ${ARGOCD_NAMESPACE} -p '{"spec": {"type": "NodePort"}}' || true

# --- Build & Push Docker image ---
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
echo "🐳 Building Docker image: ${FULL_IMAGE}"
docker build -t ${FULL_IMAGE} .
echo "📤 Pushing image to Docker Hub..."
docker push ${FULL_IMAGE}

# --- Update deployment file ---
echo "🧩 Updating image tag in ${DEPLOY_FILE}..."
sed -i "s|image: ${IMAGE_NAME}:.*|image: ${FULL_IMAGE}|g" ${DEPLOY_FILE}
grep "image:" ${DEPLOY_FILE}

# --- Commit & push changes to Git ---
echo "🪶 Committing updated deployment to Git..."
git add .
git commit -m "Update image to ${FULL_IMAGE}" || echo "No changes to commit."
git push origin ${GIT_BRANCH}

# --- Ensure Application Namespace exists ---
echo "🏗️ Ensuring namespace ${APP_NAMESPACE} exists..."
kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# --- Create / Update ArgoCD Application ---
echo "🚀 Creating/Updating ArgoCD Application..."
cat <<EOF | kubectl apply --validate=false -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}-app
  namespace: ${ARGOCD_NAMESPACE}
spec:
  project: default
  source:
    repoURL: ${GIT_REPO_URL}
    targetRevision: ${GIT_BRANCH}
    path: ${APP_PATH}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${APP_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# --- Wait and sync ---
echo "🔄 Syncing ArgoCD Application..."
kubectl -n ${ARGOCD_NAMESPACE} wait --for=condition=Healthy application/${APP_NAME}-app --timeout=180s || true
kubectl -n ${ARGOCD_NAMESPACE} wait --for=condition=Synced application/${APP_NAME}-app --timeout=180s || true

# --- Wait for Deployment ---
echo "⏳ Waiting for ${APP_NAME} deployment to roll out..."
kubectl rollout status deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=180s || true

# --- Gather Access Details ---
ARGOCD_IP=$(minikube ip)
ARGOCD_PORT=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
ARGOCD_PASS=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

# --- Get Web App URL ---
APP_SERVICE="${APP_NAME}-service"
APP_URL=$(minikube service ${APP_SERVICE} -n ${APP_NAMESPACE} --url 2>/dev/null || echo "⚠️  App Service not exposed yet")

# --- Display Final Output ---
echo ""
echo "✅ Application deployed successfully!"
echo ""
echo "============================================"
echo "🌍 ACCESS DETAILS"
echo "--------------------------------------------"
echo "ArgoCD Dashboard : http://${ARGOCD_IP}:${ARGOCD_PORT}"
echo "Local Dashboard  : http://localhost:8080 (use: kubectl port-forward svc/argocd-server -n argocd 8080:80)"
echo "Web App (UI)     : ${APP_URL}"
echo "Username         : admin"
echo "Password         : ${ARGOCD_PASS}"
echo "============================================"
echo ""
echo "🧠 To redeploy with a new image:"
echo "1️⃣ Update IMAGE_TAG in this script"
echo "2️⃣ Run ./deploy_full_argo.sh"
echo "ArgoCD will auto-sync and redeploy 🚀"
echo "============================================"
