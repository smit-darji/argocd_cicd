#!/bin/bash
set -e

# === CONFIG ===
APP_NAME="login-page"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
DEPLOY_FILE="k8s/deployment.yaml"
GIT_REPO_URL="https://github.com/smit-darji/argocd_cicd.git"
GIT_BRANCH="Master"
IMAGE_NAME="smitdarji/k8s"
IMAGE_TAG="v0.0.4"
APP_PATH="k8s"

# === STEP 1: Ensure Minikube and Context ===
echo "🚀 Checking Minikube cluster..."
if ! minikube status >/dev/null 2>&1; then
  echo "⚙️  Starting Minikube..."
  minikube start
fi

kubectl config use-context minikube >/dev/null 2>&1
echo "✅ Minikube context ready!"

# === STEP 2: Build & Push Docker Image ===
echo "🐳 Building and pushing Docker image..."
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker push ${IMAGE_NAME}:${IMAGE_TAG}

# === STEP 3: Update Deployment YAML ===
echo "🧩 Updating image tag in ${DEPLOY_FILE}..."
sed -i "s|image: ${IMAGE_NAME}:.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}
grep "image:" ${DEPLOY_FILE}

# === STEP 4: Commit & Push to Git ===
echo "🪶 Committing updated deployment to Git..."
git add .
git commit -m "Update image to ${IMAGE_NAME}:${IMAGE_TAG}"
git push origin ${GIT_BRANCH}

# === STEP 5: Apply ArgoCD Application ===
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

# === STEP 6: Wait for Pod rollout ===
echo "⏳ Waiting for deployment rollout..."
kubectl rollout status deployment/${APP_NAME} -n ${APP_NAMESPACE} || true

# === STEP 7: Get URLs ===
ARGOCD_IP=$(minikube ip)
ARGOCD_PORT=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
ARGOCD_PASS=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
APP_SERVICE=$(kubectl get svc -n ${APP_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')
APP_PORT=$(kubectl get svc ${APP_SERVICE} -n ${APP_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "✅ Application deployed successfully!"
echo ""
echo "============================================"
echo "🌍 ACCESS DETAILS"
echo "--------------------------------------------"
echo "ArgoCD Dashboard : http://${ARGOCD_IP}:${ARGOCD_PORT}"
echo "Web App (UI)     : http://${ARGOCD_IP}:${APP_PORT}"
echo "Username         : admin"
echo "Password         : ${ARGOCD_PASS}"
echo "============================================"
echo "🧠 To redeploy with new image:"
echo "1️⃣ Update IMAGE_TAG in this script"
echo "2️⃣ Run ./deploy_full_argo.sh"
echo "============================================"
