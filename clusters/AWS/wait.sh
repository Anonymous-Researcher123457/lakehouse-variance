#!/usr/bin/env bash
set -euo pipefail

K8S_NAMESPACE="pgr24james"
TIMER=0
SLEEP_TIME=10

echo "Monitoring pod workload-pod in K8S_NAMESPACE $K8S_NAMESPACE"

while true; do
  # Get pod phase (Pending, Running, Succeeded, Failed, Unknown)
  PHASE=$(kubectl get pod "workload-pod" -n "$K8S_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

  if [[ "$PHASE" == "Succeeded" ]]; then
    echo "Workload finished successfully!"
    break
  elif [[ "$PHASE" == "Failed" ]]; then
    echo "Workload failed!"
    kubectl logs "workload-pod" -n "$K8S_NAMESPACE" || true
    kubectl delete pod "workload-pod" -n "$K8S_NAMESPACE" --ignore-not-found --wait=true
    exit 1
  elif [[ "$PHASE" == "NotFound" ]]; then
    echo "Pod not found (yet)..."
  else
    echo "... Pod is $PHASE after ${TIMER}s"
  fi

  sleep "$SLEEP_TIME"
  TIMER=$((TIMER + SLEEP_TIME))
done

kubectl delete pod "workload-pod" -n "$K8S_NAMESPACE" --ignore-not-found --wait=true
