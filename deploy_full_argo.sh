#!/bin/bash
set -e

# ============================================================
# 🚀 FULL GITOPS PIPELINE — DOCKER + KUBERNETES + ARGOCD
# Author: Smit Darji
# ============================================================

# --- Configuration ---
APP_NAME="k8s-app"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
IMAGE_NAME="smitdarji/k8s"
IMAGE_TAG="v1"
DEPLOY_FILE="k8s/deployment.yaml"
APP_PATH="k8s"
GIT_REPO_URL="https://github.com/smit-darji/argocd_cicd.git"
GIT_BRANCH="Master"

# ============================================================
# 🧩 MINIKUBE & CLUSTER SETUP
# ============================================================
echo "🧩 Starting Minikube..."
minikube status || minikube start --driver=docker

echo "✅ Kubernetes cluster ready:"
kubectl get nodes

# ============================================================
# 🚀 INSTALL ARGOCD
# ============================================================
echo "🚀 Installing ArgoCD..."
kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=300s

# --- Expose ArgoCD server ---
echo "🌐 Exposing ArgoCD server via NodePort..."
kubectl patch svc argocd-server -n ${ARGOCD_NAMESPACE} -p '{"spec": {"type": "NodePort"}}' || true

# --- Get ArgoCD access info ---
ARGOCD_IP=$(minikube ip)
ARGOCD_PORT=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o=jsonpath='{.spec.ports[0].nodePort}')
ARGOCD_PASS=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "============================================"
echo "🌍 ArgoCD Dashboard Access Info"
echo "--------------------------------------------"
echo "NodePort  : http://${ARGOCD_IP}:${ARGOCD_PORT}"
echo "Localhost : http://localhost:8080"
echo "Username  : admin"
echo "Password  : ${ARGOCD_PASS}"
echo "============================================"
echo ""

# --- Optional: Port-forward in background ---
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:80 >/dev/null 2>&1 &
sleep 5

# ============================================================
# 🐳 DOCKER BUILD & PUSH
# ============================================================
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
echo "🐳 Building Docker image: ${FULL_IMAGE}"
docker build -t ${FULL_IMAGE} .

echo "📤 Pushing Docker image..."
docker login
docker push ${FULL_IMAGE}

# ============================================================
# 🧩 UPDATE DEPLOYMENT YAML + PUSH TO GIT
# ============================================================
echo "🧩 Updating image tag in ${DEPLOY_FILE}..."
sed -i "s|image: ${IMAGE_NAME}:.*|image: ${FULL_IMAGE}|g" ${DEPLOY_FILE}
grep "image:" ${DEPLOY_FILE}

echo "🪶 Committing updated deployment file..."
git add .
git commit -m "Update image to ${FULL_IMAGE}" || echo "No changes to commit"
git push origin ${GIT_BRANCH}

# ============================================================
# 🧱 CREATE APP NAMESPACE
# ============================================================
kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# ============================================================
# 🚀 CREATE / UPDATE ARGOCD APPLICATION
# ============================================================
echo "🚀 Creating/Updating ArgoCD Application..."
cat <<EOF | kubectl apply -f -
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

# ============================================================
# ⏳ WAIT FOR DEPLOYMENT + SHOW APP URL
# ============================================================
echo "⏳ Waiting for deployment pods..."
kubectl wait --for=condition=Available deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=180s || true

echo "✅ Application deployed successfully!"
echo ""
echo "============================================"
echo "🌍 ACCESS DETAILS"
echo "--------------------------------------------"
echo "ArgoCD Dashboard : http://${ARGOCD_IP}:${ARGOCD_PORT}"
echo "Local Dashboard  : http://localhost:8080"
echo "Username         : admin"
echo "Password         : ${ARGOCD_PASS}"
echo ""

APP_URL=$(minikube service ${APP_NAME}-service -n ${APP_NAMESPACE} --url 2>/dev/null || true)
if [ -n "$APP_URL" ]; then
  echo "Web Application  : ${APP_URL}"
else
  echo "⚠️  App Service not exposed yet — check using:"
  echo "   kubectl get svc -n ${APP_NAMESPACE}"
fi

echo "============================================"
echo "🧠 To redeploy with new image:"
echo "1️⃣ Update IMAGE_TAG in this script"
echo "2️⃣ Run ./deploy_full_argo.sh"
echo "3️⃣ ArgoCD auto-syncs and redeploys 🚀"
echo "============================================"
