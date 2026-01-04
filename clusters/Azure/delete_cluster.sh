#!/usr/bin/env bash
set -euo pipefail


command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }

echo "|=============== Tearing Down Kubernetes Cluster ===============|"

echo "Logging in with device code…"
az login --use-device-code 1>/dev/null

echo "Setting subscription to ${SUBSCRIPTION_ID}…"
az account set --subscription "${SUBSCRIPTION_ID}"

# =======================
# Delete AKS cluster
# =======================
echo "Deleting AKS cluster ${AKS_CLUSTER_NAME}…"
az aks delete \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER_NAME}" \
  --yes --no-wait

echo "Deleting resource group ${RESOURCE_GROUP} (this removes all contained resources)…"
az group delete \
  --name "${RESOURCE_GROUP}" \
  --yes --no-wait

echo "Teardown initiated. Resources will be cleaned up in the background."
