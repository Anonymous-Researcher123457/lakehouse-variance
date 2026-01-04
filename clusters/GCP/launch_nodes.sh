#!/usr/bin/env bash
set -euo pipefail

GENERAL_NODE_POOL_IMAGE_TYPE="COS_CONTAINERD"
GENERAL_NODE_POOL_DISK_TYPE="pd-balanced"
GENERAL_NODE_POOL_TAINTS="node=trino:NoSchedule"
GENERAL_NODE_POOL_METADATA="disable-legacy-endpoints=true"

# --- Trino Coordinator pool ---
COORD_NODE_NAME="coord"
COORD_MACHINE_TYPE="e2-standard-4"
COORD_NUM_NODES="2"
COORD_DISK_SIZE="100"
COORD_LABELS="pod=coord"

DEPLOY_HIVE_NODE=true
DEPLOY_COORD_NODE=true
DEPLOY_WORKER_NODES=true

if [ "$DEPLOY_COORD_NODE" = "true" ]; then
  gcloud beta container node-pools create "${COORD_NODE_NAME}" \
  --project "${PROJECT_NAME}" \
  --cluster "${CLUSTER_NAME}" \
  --region "${CLUSTER_REGION}" \
  --machine-type "${COORD_MACHINE_TYPE}" \
  --image-type "${GENERAL_NODE_POOL_IMAGE_TYPE}"  \
  --disk-type "${GENERAL_NODE_POOL_DISK_TYPE}" \
  --disk-size "${COORD_DISK_SIZE}" \
  --node-labels "${COORD_LABELS}" \
  --node-taints "${GENERAL_NODE_POOL_TAINTS}" \
  --metadata "${GENERAL_NODE_POOL_METADATA}" \
  --num-nodes "${COORD_NUM_NODES}" \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 \
  --shielded-integrity-monitoring \
  --no-shielded-secure-boot \
  --node-locations "${CLUSTER_REGION}-${CLUSTER_REGION_ZONE}" \
  --workload-metadata=GKE_METADATA \
  --quiet
fi

# --- Hive Metastore pool ---
HIVE_NODE_NAME="hive"
HIVE_MACHINE_TYPE="e2-custom-2-4096"
HIVE_NUM_NODES="2"
HIVE_DISK_SIZE="100"
HIVE_LABELS="pod=hive"

if [ "$DEPLOY_HIVE_NODE" = "true" ]; then
  gcloud beta container node-pools create "${HIVE_NODE_NAME}" \
    --project "${PROJECT_NAME}" \
    --cluster "${CLUSTER_NAME}" \
    --region "${CLUSTER_REGION}" \
    --machine-type "${HIVE_MACHINE_TYPE}" \
    --image-type "${GENERAL_NODE_POOL_IMAGE_TYPE}" \
    --disk-type "${GENERAL_NODE_POOL_DISK_TYPE}" \
    --disk-size "${HIVE_DISK_SIZE}" \
    --node-labels "${HIVE_LABELS}" \
    --node-taints "${GENERAL_NODE_POOL_TAINTS}" \
    --metadata "${GENERAL_NODE_POOL_METADATA}" \
    --num-nodes "${HIVE_NUM_NODES}" \
    --enable-autoupgrade \
    --enable-autorepair \
    --max-surge-upgrade 1 \
    --max-unavailable-upgrade 0 \
    --shielded-integrity-monitoring \
    --no-shielded-secure-boot \
    --node-locations "${CLUSTER_REGION}-${CLUSTER_REGION_ZONE}" \
    --workload-metadata=GKE_METADATA \
    --quiet
fi

# --- Trino Worker pool ---
WORKER_NODE_NAME="worker"
WORKER_MACHINE_TYPE="e2-highmem-8"
WORKER_NUM_NODES="2"
WORKER_DISK_SIZE="100"
WORKER_LABELS="pod=worker"

if [ "$DEPLOY_WORKER_NODES" = "true" ]; then
  gcloud beta container node-pools create "${WORKER_NODE_NAME}" \
    --project "${PROJECT_NAME}" \
    --cluster "${CLUSTER_NAME}" \
    --region "${CLUSTER_REGION}" \
    --machine-type "${WORKER_MACHINE_TYPE}" \
    --image-type "${GENERAL_NODE_POOL_IMAGE_TYPE}" \
    --disk-type "${GENERAL_NODE_POOL_DISK_TYPE}" \
    --disk-size "${WORKER_DISK_SIZE}" \
    --node-labels "${WORKER_LABELS}" \
    --node-taints "${GENERAL_NODE_POOL_TAINTS}" \
    --metadata "${GENERAL_NODE_POOL_METADATA}" \
    --num-nodes "${WORKER_NUM_NODES}" \
    --enable-autoupgrade \
    --enable-autorepair \
    --max-surge-upgrade 1 \
    --max-unavailable-upgrade 0 \
    --shielded-integrity-monitoring \
    --no-shielded-secure-boot \
    --node-locations "${CLUSTER_REGION}-${CLUSTER_REGION_ZONE}" \
    --workload-metadata=GKE_METADATA \
    --quiet
fi