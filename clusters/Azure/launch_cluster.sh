#!/usr/bin/env bash
set -euo pipefail

NODE_SIZE="Standard_D2s_v4"
NODE_COUNT=3
NODE_MIN=3
NODE_MAX=3

# =======================
# Config checks
# =======================
command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }

if ! az account show >/dev/null 2>&1; then
  echo "Not logged in, running device code login..."
  az login --use-device-code >/dev/null
else
  echo "Already logged in as $(az account show --query user.name -o tsv)"
fi
echo "Setting subscription to ${SUBSCRIPTION_ID}..."
az account set --subscription "${SUBSCRIPTION_ID}"

echo "Creating resource group ${RESOURCE_GROUP} in ${LOCATION} (idempotent)..."
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" 1>/dev/null

# =======================
# Create AKS 
# =======================
echo "Creating AKS cluster ${AKS_CLUSTER_NAME} ..."

az aks create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER_NAME}" \
  --location "${LOCATION}" \
  --node-vm-size "${NODE_SIZE}" \
  --node-count "${NODE_COUNT}" \
  --enable-cluster-autoscaler \
  --min-count "${NODE_MIN}" \
  --max-count "${NODE_MAX}" \
  --enable-managed-identity \
  --network-plugin azure \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys \
  --nodepool-labels pool=admin \
  "${VERSION_FLAG[@]}" 1>/dev/null

# =======================
# Kubeconfig
# =======================
echo "Fetching kubeconfig..."
az aks get-credentials --resource-group "${RESOURCE_GROUP}" --name "${AKS_CLUSTER_NAME}" --overwrite-existing 1>/dev/null

echo "Cluster ready. Current nodes:"
kubectl get nodes -o wide

# ============== Install NGINX Ingress Controller (AKS) ==============

set -euo pipefail

# 1) Ensure Helm is available
command -v helm >/dev/null 2>&1 || { echo "helm not found. Install Helm first."; exit 1; }

# 2) Add/update repo and install/upgrade controller (idempotent)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null

#install ingress helm chart
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassResource.default=true \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local

# 3) Wait for controller to be Ready
echo "Waiting for NGINX Ingress controller to be ready..."
kubectl rollout status deploy/ingress-nginx-controller \
  -n ingress-nginx --timeout=10m

# 4) Wait for public IP allocation 
echo "Waiting for NGINX Ingress EXTERNAL-IP..."
for i in {1..60}; do
  NGINX_LB_IP="$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  NGINX_LB_HOST="$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "$NGINX_LB_IP" || -n "$NGINX_LB_HOST" ]]; then
    echo "NGINX Ingress is exposed at: ${NGINX_LB_IP:-$NGINX_LB_HOST}"
    break
  fi
  sleep 5
done

if [[ -z "${NGINX_LB_IP:-$NGINX_LB_HOST}" ]]; then
  echo "Timed out waiting for NGINX Ingress external address."
  kubectl get svc ingress-nginx-controller -n ingress-nginx -o wide
  exit 1
fi
