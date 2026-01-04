#!/usr/bin/env bash
set -euo pipefail

ZONES="1"
ADD_HIVE=true
ADD_COORD=true
ADD_WORKERS=true

# ---------- Hive Metastore pool ----------
HIVE_POOL_NAME="hive"
HIVE_VM_SIZE="Standard_D2als_v6"
HIVE_NODE_COUNT=1
HIVE_OSDISK_GB=30
HIVE_LABELS=(pod=hive role=metastore)

# ---------- Trino Coordinator pool ----------
COORD_POOL_NAME="coord"
COORD_VM_SIZE="Standard_D4as_v6"
COORD_NODE_COUNT=1
COORD_OSDISK_GB=30
COORD_LABELS=(pod=coord role=coordinator)

# ---------- Trino Worker pool ----------
WORKER_POOL_NAME="worker"
WORKER_VM_SIZE="Standard_E8s_v6"
WORKER_NODE_COUNT=4
WORKER_OSDISK_GB=30
WORKER_LABELS=(pod=worker role=worker)  # <-- array

add_pool () {
  local NAME="$1" SIZE="$2" COUNT="$3" DISK="$4"
  shift 4
  local LABEL_ARR=("$@")

  echo "Adding node pool '${NAME}' (${SIZE}, ${COUNT} nodes, ${DISK}GiB OS disk)…"
  az aks nodepool add \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${AKS_CLUSTER_NAME}" \
    --name "${NAME}" \
    --mode User \
    --node-vm-size "${SIZE}" \
    --node-count "${COUNT}" \
    --node-osdisk-size "${DISK}" \
    --labels "${LABEL_ARR[@]}" \
    --zones ${ZONES}
}

if [ "$ADD_HIVE" = "true" ]; then
  add_pool "${HIVE_POOL_NAME}"   "${HIVE_VM_SIZE}"   "${HIVE_NODE_COUNT}"   "${HIVE_OSDISK_GB}"   "${HIVE_LABELS[@]}"
fi

if [ "$ADD_COORD" = "true" ]; then
  add_pool "${COORD_POOL_NAME}"  "${COORD_VM_SIZE}"  "${COORD_NODE_COUNT}"  "${COORD_OSDISK_GB}"  "${COORD_LABELS[@]}"
fi

if [ "$ADD_WORKERS" = "true" ]; then
  add_pool "${WORKER_POOL_NAME}" "${WORKER_VM_SIZE}" "${WORKER_NODE_COUNT}" "${WORKER_OSDISK_GB}" "${WORKER_LABELS[@]}"
fi

echo "Done. Current node pools:"
az aks nodepool list -g "${RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER_NAME}" -o table
