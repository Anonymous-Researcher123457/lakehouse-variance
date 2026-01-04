#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-}"
CLUSTER="${GKE_CLUSTER_NAME:-}"
REGION="${GKE_REGION:-europe-west2}"
NS="${NAMESPACE:-}"

SLEEP="${SLEEP:-3}"
TIMEOUT_PER_OBJ="${TIMEOUT_PER_OBJ:-120}"   # seconds to wait for a single object
TIMEOUT_NS_DELETE="${TIMEOUT_NS_DELETE:-300}"

log(){ echo -e "$*"; }
warn(){ echo -e "$*" >&2; }
die(){ echo -e "$*" >&2; exit 1; }

log "Getting credentials for ${PROJECT}/${CLUSTER} (${REGION})"
gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT}" >/dev/null
log "Context: $(kubectl config current-context)"

# -------- helper: delete a single <kind>/<name> and wait until it's gone --------
_delete_and_wait_one() {
  local kind="$1" name="$2"
  kubectl delete "$kind" "$name" -n "$NS" --ignore-not-found --wait=false || true
  # wait for deletion by polling (works for all kinds)
  local end=$(( $(date +%s) + TIMEOUT_PER_OBJ ))
  while kubectl get "$kind" "$name" -n "$NS" >/dev/null 2>&1; do
    if (( $(date +%s) > end )); then
      warn "$kind/$name still exists, attempting to strip finalizers…"
      kubectl get "$kind" "$name" -n "$NS" -o json \
        | jq 'del(.metadata.finalizers)' \
        | kubectl replace -n "$NS" -f - >/dev/null 2>&1 || true
      # one last try
      kubectl delete "$kind" "$name" -n "$NS" --ignore-not-found --wait=false || true
      sleep "$SLEEP"
      if kubectl get "$kind" "$name" -n "$NS" >/dev/null 2>&1; then
        die "$kind/$name did not delete"
      fi
      break
    fi
    sleep "$SLEEP"
  done
}

# -------- 1) delete namespaced resources kind-by-kind, waiting for zero --------
# Order matters (traffic → workloads → storage → config)
KINDS_ORDERED=(
  "ingress.networking.k8s.io"
  "service"
  "job.batch"
  "cronjob.batch"
  "deployment.apps"
  "statefulset.apps"
  "daemonset.apps"
  "pod"
  "persistentvolumeclaim"
  "configmap"
  "secret"
  "rolebinding.rbac.authorization.k8s.io"
  "role.rbac.authorization.k8s.io"
  "serviceaccount"
)

# make sure jq is available
command -v jq >/dev/null || die "jq is required"

# Only process kinds that exist in this cluster and are namespaced
NAMESPACED_KINDS=$(kubectl api-resources --namespaced=true -o name)

for kind in "${KINDS_ORDERED[@]}"; do
  if ! grep -qx "$kind" <<<"$NAMESPACED_KINDS"; then
    continue
  fi
  # get concrete object names
  names=$(kubectl get "$kind" -n "$NS" --no-headers --ignore-not-found -o custom-columns=:metadata.name || true)
  [[ -z "$names" ]] && continue
  log "Deleting all $kind objects ($(wc -w <<<"$names" | tr -d ' ') found)"
  while read -r name; do
    [[ -z "$name" ]] && continue
    _delete_and_wait_one "$kind" "$name"
  done <<<"$names"
  # verify none remain
  remain=$(kubectl get "$kind" -n "$NS" --no-headers --ignore-not-found 2>/dev/null | wc -l | tr -d ' ')
  (( remain == 0 )) || die "Some $kind remain (${remain})"
done

# -------- 2) delete any OTHER namespaced kinds not in the list (CRDs, etc.) --------
while read -r kind; do
  # already handled?
  if printf '%s\n' "${KINDS_ORDERED[@]}" | grep -qx "$kind"; then
    continue
  fi
  # list and delete
  names=$(kubectl get "$kind" -n "$NS" --no-headers --ignore-not-found -o custom-columns=:metadata.name 2>/dev/null || true)
  [[ -z "$names" ]] && continue
  log "Deleting remaining kind $kind ($(wc -w <<<"$names" | tr -d ' ') found)"
  while read -r name; do
    [[ -z "$name" ]] && continue
    _delete_and_wait_one "$kind" "$name"
  done <<<"$names"
  remain=$(kubectl get "$kind" -n "$NS" --no-headers --ignore-not-found 2>/dev/null | wc -l | tr -d ' ')
  (( remain == 0 )) || die "Some $kind remain (${remain})"
done <<<"$NAMESPACED_KINDS"

# -------- 3) delete bound PVs that belong to this namespace (cluster-scoped) --------
pvs=$(kubectl get pv -o json \
  | jq -r --arg ns "$NS" '.items[] | select(.spec.claimRef.namespace==$ns) | .metadata.name' )
if [[ -n "$pvs" ]]; then
  log "Deleting PVs bound to namespace ($NS):"
  while read -r pv; do
    [[ -z "$pv" ]] && continue
    log "   - pv/$pv"
    # strip finalizers if needed, then delete and wait
    kubectl patch pv "$pv" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
    kubectl delete pv "$pv" --ignore-not-found --wait=false || true
    end=$(( $(date +%s) + TIMEOUT_PER_OBJ ))
    while kubectl get pv "$pv" >/dev/null 2>&1; do
      (( $(date +%s) > end )) && die "pv/$pv refused to delete"
      sleep "$SLEEP"
    done
  done <<<"$pvs"
fi

# -------- 4) delete the namespace and ensure it is GONE --------
if kubectl get ns "$NS" >/dev/null 2>&1; then
  log "Deleting namespace $NS"
  kubectl delete ns "$NS" --wait=false || true
fi

end=$(( $(date +%s) + TIMEOUT_NS_DELETE ))
while kubectl get ns "$NS" >/dev/null 2>&1; do
  phase=$(kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  log "... waiting for namespace ($phase)"
  (( $(date +%s) > end )) && break
  sleep "$SLEEP"
done

if kubectl get ns "$NS" >/dev/null 2>&1; then
  warn "Namespace stuck; force-finalizing…"
  kubectl get ns "$NS" -o json \
    | jq 'del(.spec.finalizers)' \
    | kubectl replace --raw "/api/v1/namespaces/${NS}/finalize" -f - || true
  # verify gone
  sleep "$SLEEP"
fi

if kubectl get ns "$NS" >/dev/null 2>&1; then
  kubectl get ns "$NS" -o json | jq '.metadata,.status' || true
  die "Namespace $NS still present after forced finalize"
fi

log "ALL resources deleted and namespace ${NS} is gone."
