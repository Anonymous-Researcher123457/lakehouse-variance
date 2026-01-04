#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-my-iam}"
YAML_DIR="./YAML"

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

# -------- Delete all given manifests in reverse order--------
echo "Deleting resources (reverse order)..."
for (( idx=${#YAML_FILES[@]}-1 ; idx>=0 ; idx-- )); do
  f="${YAML_FILES[$idx]}"
  path="${YAML_DIR}/${f}.yaml"
  echo "Deleting ${path}"
  kubectl delete -f "${path}" -n "${K8S_NAMESPACE}" --ignore-not-found --wait=true --timeout=120s || \
    echo "Could not delete ${f} (may not exist)"

  # If the Ingress hangs on a finalizer, strip it so deletion can complete
  if [[ "$f" == "trino-ingress" ]]; then
    for i in {1..24}; do
      if ! kubectl -n "${K8S_NAMESPACE}" get ingress trino-ingress >/dev/null 2>&1; then
        echo "Ingress trino-ingress deleted"
        break
      fi
      # If it's Terminating (deletionTimestamp set), drop the ALB finalizer
      if kubectl -n "${K8S_NAMESPACE}" get ingress trino-ingress -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null | grep -q .; then
        echo "Ingress stuck terminating; stripping ALB finalizer…"
        kubectl -n "${K8S_NAMESPACE}" patch ingress trino-ingress \
          -p '{"metadata":{"finalizers":null}}' --type=merge || true
      fi
      sleep 5
    done
  fi
done

echo "Teardown complete."

