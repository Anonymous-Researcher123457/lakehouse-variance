#!/usr/bin/env bash
set -euo pipefail

INGRESS_NAME="trino-ingress"
WAIT_SECS=600
CHECK_INTERVAL=10

# Manifests in ./YAML
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

# ============== AKS / kubectl setup ==============
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

# Ensure namespace exists
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"

# ============== Rollback wiring ==============
APPLIED_FILES=()
rollback() {
  echo "Rolling back applied resources..."
  for (( idx=${#APPLIED_FILES[@]}-1 ; idx>=0 ; idx-- )); do
    f="${APPLIED_FILES[$idx]}"
    echo "  - deleting ./YAML/${f}.yaml"
    kubectl delete -f "./YAML/${f}.yaml" -n "${NAMESPACE}" --ignore-not-found
  done
}
trap 'echo "Error occurred."; rollback; exit 1' ERR

# ============== Apply manifests ==============
echo "|=============== Launching Trino on AKS ===============|"
echo "Applying manifests in order..."
for f in "${YAML_FILES[@]}"; do
  path="./YAML/${f}.yaml"
  echo "kubectl apply -f ${path}"
  kubectl apply -f "${path}" -n "${NAMESPACE}"
  APPLIED_FILES+=("${f}")
done
echo "All manifests applied."

# ============== Wait for readiness ==============
echo "Waiting for Trino coordinator & workers..."
kubectl wait pod/trino-coord-pod -n "${NAMESPACE}" --for=condition=Ready --timeout=10m
kubectl rollout status statefulset/trino-worker -n "${NAMESPACE}" --timeout=10m

# ============== Ingress address discovery  ==============
echo "Resolving Ingress external address (${INGRESS_NAME})..."
elapsed=0
TRINO_INGRESS_ADDR=""

while [[ $elapsed -lt $WAIT_SECS ]]; do
  # Try hostname first , else IP
  host="$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  ip="$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

  if [[ -n "${host}" ]]; then
    TRINO_INGRESS_ADDR="${host}"
    break
  fi
  if [[ -n "${ip}" ]]; then
    TRINO_INGRESS_ADDR="${ip}"
    break
  fi

  sleep "${CHECK_INTERVAL}"
  elapsed=$((elapsed+CHECK_INTERVAL))
  echo "  ...still waiting (${elapsed}s/${WAIT_SECS}s)"
done

if [[ -z "${TRINO_INGRESS_ADDR}" ]]; then
  echo "Timed out waiting for Ingress external address."
  echo "Troubleshoot: kubectl get ing ${INGRESS_NAME} -n ${NAMESPACE} -o yaml"
  exit 1
fi

scheme="http"
echo "Trino should be reachable at: ${scheme}://${TRINO_INGRESS_ADDR}"
printf 'TRINO_HOST=%s\n' "${TRINO_INGRESS_ADDR}" > .trino.env

# ============== Health check ==============
deadline=$((SECONDS + WAIT_SECS))
while [ $SECONDS -lt $deadline ]; do
  if curl -s --fail "${scheme}://${TRINO_INGRESS_ADDR}/v1/info" | grep -q '"starting":false'; then
      took=$((WAIT_SECS - (deadline-SECONDS)))
      echo "Trino is ready after ${took}s."
      exit 0
  fi
  echo "... not ready yet, retrying in ${CHECK_INTERVAL}s."
  sleep "${CHECK_INTERVAL}"
done

echo "Timeout reached: Trino did not become ready in ${WAIT_SECS}s."
exit 1
