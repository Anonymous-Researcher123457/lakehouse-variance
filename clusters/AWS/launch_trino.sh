#!/usr/bin/env bash
set -euo pipefail

# -------- Config --------
AWS_PROFILE="${AWS_PROFILE:-my-iam}"
INGRESS_NAME="trino-ingress"

WAIT_SECS=600
CHECK_INTERVAL=10

# Ordered list of YAML files (without .yaml extension) located in ./YAML/
YAML_FILES=(
  "namespace"
  "trino-sa"
  "hive-config"
  "core-site-s3a"
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
echo "Updating kubeconfig for EKS cluster: ${CLUSTER_NAME} in ${REGION}"
export AWS_SDK_LOAD_CONFIG=1
aws eks update-kubeconfig \
  --region "${REGION}" \
  --name "${CLUSTER_NAME}" \
  ${AWS_PROFILE:+--profile "${AWS_PROFILE}"} \
  --alias "eks-${REGION}"

ctx="$(kubectl config current-context)"
echo "kubectl context: ${ctx}"

kubectl get ns "${K8S_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${K8S_NAMESPACE}"

# Track for potential rollback
APPLIED_FILES=()
rollback() {
  echo "Rolling back applied resources..."
  for (( idx=${#APPLIED_FILES[@]}-1 ; idx>=0 ; idx-- )); do
    f="${APPLIED_FILES[$idx]}"
    echo "  - deleting ${f}.yaml"
    kubectl delete -f "./YAML/${f}.yaml" -n "${K8S_NAMESPACE}" --ignore-not-found
  done
}
trap 'echo "Error occurred."; rollback; exit 1' ERR

# -------- Apply manifests --------
echo "Applying manifests in order..."
for f in "${YAML_FILES[@]}"; do
  path="./YAML/${f}.yaml"
  echo "kubectl apply -f ${path}"
  kubectl apply -f "${path}" -n "${K8S_NAMESPACE}"
  APPLIED_FILES+=("${f}")
done
echo "All manifests applied."

# -------- Wait for coordinator & workers --------
echo "Waiting for Trino to become Ready..."

kubectl wait pod/trino-coord-pod -n "${K8S_NAMESPACE}" --for=condition=Ready --timeout=10m

kubectl rollout status statefulset/trino-worker -n "${K8S_NAMESPACE}" --timeout=10m

# -------- Ingress external address (AWS ALB) --------
echo "Waiting for Ingress external address (${INGRESS_NAME})..."
elapsed=0
TRINO_INGRESS_ADDR=""

# ALB sets .status.loadBalancer.ingress[0].hostname (not .ip)
while [[ $elapsed -lt $WAIT_SECS ]]; do
  host=$(kubectl get ingress "${INGRESS_NAME}" -n "${K8S_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${host}" ]]; then
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
TRINO_HOST="${TRINO_INGRESS_ADDR}"
printf 'TRINO_HOST=%s\n' "$TRINO_HOST" > .trino.env

# -------- Health check --------
deadline=$((SECONDS + WAIT_SECS))
while [ $SECONDS -lt $deadline ]; do
  if curl -s --fail "http://${TRINO_INGRESS_ADDR}/v1/info" | grep -q '"starting":false'; then
      echo "Trino is ready after $((WAIT_SECS - (deadline-SECONDS))) seconds."
      exit 0
  fi
  echo "… not ready yet, retrying in ${CHECK_INTERVAL}s."
  sleep "${CHECK_INTERVAL}"
done

echo "Timeout reached: Trino did not become ready in ${WAIT_SECS}s."
exit 1
