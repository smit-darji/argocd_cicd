#!/bin/bash
# --------------------------------------------------------
# 🚀 ArgoCD WebApp Deployment Script (Minikube + GitOps)
# --------------------------------------------------------
#  - Builds Docker image
#  - Updates deployment YAML
#  - Pushes changes to GitHub
#  - ArgoCD automatically syncs
# --------------------------------------------------------

set -e  # Exit if any command fails

# ---------------- CONFIG ----------------
APP_NAME="hello-web"
DEPLOY_FILE="k8sdeploy.yaml"
IMAGE_TAG=$(date +%Y%m%d%H%M)   # e.g., 202510281230 (unique tag)
GITHUB_REPO="https://github.com/smit-darji/argocd_cicd.git"
BRANCH="Master"  # change if your repo uses 'Master'
# ----------------------------------------

echo "🌍 Using image tag: ${IMAGE_TAG}"

# 🐳 Step 1: Use Minikube Docker (optional)
echo "🐳 Setting Docker environment to Minikube..."
eval $(minikube docker-env)

# 🏗️ Step 2: Build new Docker image
echo "🏗️ Building Docker image: ${APP_NAME}:${IMAGE_TAG}"
docker build -t ${APP_NAME}:${IMAGE_TAG} .

# 📦 Step 3: Load image to Minikube cache
echo "📦 Loading image into Minikube..."
minikube image load ${APP_NAME}:${IMAGE_TAG}

# 🧩 Step 4: Update image tag in Deployment YAML
echo "🧩 Updating ${DEPLOY_FILE} with new image tag..."
sed -i "s|image: ${APP_NAME}:.*|image: ${APP_NAME}:${IMAGE_TAG}|g" ${DEPLOY_FILE}

grep "image:" ${DEPLOY_FILE}

🪣 Step 5: Commit and push to GitHub (GitOps trigger)
echo "🪣 Committing and pushing changes to GitHub..."
git add ${DEPLOY_FILE}
git commit -m "Deploy: updated ${APP_NAME} to tag ${IMAGE_TAG}"
git push origin ${BRANCH}

# # 🌀 Step 6: ArgoCD sync (optional manual trigger)
# echo "🌀 Triggering ArgoCD sync..."
# argocd app sync ${APP_NAME} || echo "⚠️ Manual sync required in ArgoCD UI if auto-sync disabled."

# ✅ Done
echo "✅ Deployment pushed! ArgoCD will detect changes and roll out new version."
echo "💡 Check status in ArgoCD UI → App: ${APP_NAME}"
