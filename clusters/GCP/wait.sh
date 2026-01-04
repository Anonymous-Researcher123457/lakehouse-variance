#!/usr/bin/env bash
set -euo pipefail

POD_NAME="workload-pod"
TIMER=0
SLEEP_TIME=10

echo "Monitoring pod $POD_NAME in namespace $NAMESPACE"

while true; do
  # Get pod phase (Pending, Running, Succeeded, Failed, Unknown)
  PHASE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

  if [[ "$PHASE" == "Succeeded" ]]; then
    echo "Workload finished successfully!"
    break
  elif [[ "$PHASE" == "Terminating" ]]; then
    echo "Workload finished successfully!"
    break
  elif [[ "$PHASE" == "Failed" ]]; then
    echo "Workload failed!"
    kubectl logs "$POD_NAME" -n "$NAMESPACE" || true
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true
    exit 1
  elif [[ "$PHASE" == "NotFound" ]]; then
    echo "Pod not found (yet)..."
  else
    echo "... Pod is $PHASE after ${TIMER}s"
  fi

  sleep "$SLEEP_TIME"
  TIMER=$((TIMER + SLEEP_TIME))
done

kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true
