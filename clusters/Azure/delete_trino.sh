#!/usr/bin/env bash
set -euo pipefail

YAML_DIR="./YAML"

YAML_FILES=(
  "namespace"
  "trino-sa"
  "hive-config"
  "core-site-config"
  "hive-service"
  "hive-metastore-postgres"
  "trino-connector-iceberg-config"
  "trino-coord-config"
  "trino-jvm-config"
  "trino-worker-config"
  "trino-service"
  "trino-worker-service"
  "trino-worker"
  "trino-coord"
  "trino-ingress"
)

# -------- AWS / kubectl setup --------
echo "Checking Azure login..."
if ! az account show >/dev/null 2>&1; then
  echo "Not logged in. Device code flow..."
  az login --use-device-code >/dev/null
fi

echo "Using subscription: ${SUBSCRIPTION_ID}"
az account set --subscription "${SUBSCRIPTION_ID}"

echo "Getting kubeconfig for AKS cluster ${AKS_CLUSTER_NAME} ${RESOURCE_GROUP}"
az aks get-credentials -g "${RESOURCE_GROUP}" -n "${AKS_CLUSTER_NAME}" --overwrite-existing >/dev/null

ctx="$(kubectl config current-context)"
echo "kubectl context: ${ctx}"

# -------- Delete all given manifests in reverse order--------
echo "Deleting resources (reverse order)..."
for (( idx=${#YAML_FILES[@]}-1 ; idx>=0 ; idx-- )); do
  f="${YAML_FILES[$idx]}"
  path="${YAML_DIR}/${f}.yaml"
  echo "Deleting ${path}"
  kubectl delete -f "${path}" -n "${NAMESPACE}" --ignore-not-found --wait=true || \
    echo "Could not delete ${f} (may not exist)"
done

echo "Teardown complete."

