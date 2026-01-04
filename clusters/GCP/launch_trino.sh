#!/usr/bin/env bash
set -euo pipefail

INGRESS_NAME="trino-ingress"

WAIT_SECS=600
CHECK_INTERVAL=10

# Ordered list of YAML files located in ./YAML/
YAML_FILES=(
  "secret"
  "hive-config"
  "hive-sa"
  "hive-service"
  "hive-metastore-postgres"
  "trino-sa"
  "trino-connector-iceberg-config"
  "trino-coord-config"
  "trino-jvm-config"
  "trino-worker-config"
  "trino-ingress"
  "trino-backendconfig"
  "trino-service"
  "trino-worker-service"
  "trino-worker"
  "trino-coord"
  "namespace"
)

# -------- Gcloud/Kubectl Setup --------
echo "Ensuring gcloud is authenticated and pointing at project: ${PROJECT_NAME}"
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" --region "${GKE_REGION}" --project "${PROJECT_NAME}"

ctx="$(kubectl config current-context)"
echo "kubectl context: ${ctx}"

# Create namespace
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"

# Track for potential rollback
APPLIED_FILES=()

rollback() {
  echo "Rolling back applied resources..."
  # delete in reverse order for safety
  for (( idx=${#APPLIED_FILES[@]}-1 ; idx>=0 ; idx-- )); do
    f="${APPLIED_FILES[$idx]}"
    echo "  - deleting ${f}.yaml"
    kubectl delete -f "./YAML/${f}.yaml" -n "${NAMESPACE}" --ignore-not-found
  done
}
trap 'echo "Error occurred."; rollback; exit 1' ERR

# -------- Apply manifests --------
echo "Applying manifests in order..."
for f in "${YAML_FILES[@]}"; do
  path="./YAML/${f}.yaml"
  echo "kubectl apply -f ${path}"
  kubectl apply -f "${path}" -n "${NAMESPACE}"
  APPLIED_FILES+=("${f}")
done
echo "All manifests applied."

# -------- Wait for Trino pods --------
echo "Waiting for Trino coordinator & workers to become Ready..."
kubectl wait pod/trino-coord-pod \
  -n "${NAMESPACE}" \
  --for=condition=Ready --timeout=10m

kubectl rollout status statefulset/trino-worker \
  -n "${NAMESPACE}" \
  --timeout=10m

# -------- Ingress External Address --------
echo "Waiting for Ingress external address (${INGRESS_NAME})..."
elapsed=0
TRINO_INGRESS_ADDR=""
while [[ $elapsed -lt $WAIT_SECS ]]; do
  # Prefer IP if present, else hostname
  ip=$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  host=$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ip}" ]]; then
    TRINO_INGRESS_ADDR="${ip}"
    break
  elif [[ -n "${host}" ]]; then
    TRINO_INGRESS_ADDR="${host}"
    break
  fi
  sleep "${CHECK_INTERVAL}"
  elapsed=$((elapsed+CHECK_INTERVAL))
  echo "  ...still waiting (${elapsed}s/${WAIT_SECS}s)"
done

if [[ -z "${TRINO_INGRESS_ADDR}" ]]; then
  echo "Timed out waiting for Ingress external address."
  exit 1
fi
echo "Trino should be reachable at: http://${TRINO_INGRESS_ADDR}"
# -------- Health check --------
while [ $SECONDS -lt $WAIT_SECS ]; do
    if curl -s --fail "http://${TRINO_INGRESS_ADDR}:80/v1/info" | grep -q '"starting":false'; then
        echo "Trino is ready after $SECONDS seconds."
        TRINO_HOST="${TRINO_INGRESS_ADDR}"
        printf 'TRINO_HOST=%s\n' "$TRINO_HOST" > .trino.env
        exit 0
    fi
    echo "… not ready yet, retrying in ${CHECK_INTERVAL} seconds."
    sleep "${CHECK_INTERVAL}"
done

echo "Timeout reached: Trino did not become ready in ${WAIT_SECS}s."
exit 1

