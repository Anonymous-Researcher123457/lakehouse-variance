#!/usr/bin/env bash
set -euo pipefail

# General Cluster Configs
CLUSTER_REGION_ZONE="a"
CLUSTER_TIER="standard"
CLUSTER_RELEASE_CHANNEL="regular"
CLUSTER_METADATA="disable-legacy-endpoints=true"

# Admin Node Pool Configs
CLUSTER_ADMIN_NODE_POOL_NUM_NODES="2"
CLUSTER_ADMIN_NODE_POOL_LABELS="pool=admin"
CLUSTER_ADMIN_NODE_POOL_MACHINE_TYPE="e2-standard-2"
CLUSTER_ADMIN_NODE_POOL_DISK_TYPE="pd-balanced"
CLUSTER_ADMIN_NODE_POOL_DISK_SIZE="50"

DEPLOY_CLUSTER=true

if [ "$DEPLOY_CLUSTER" = "true" ]; then
  # Command to launch on gcloud (Assuming logged in)
  gcloud beta container --project "${PROJECT_NAME}" clusters create "${GKE_CLUSTER_NAME}" \
   --region "${CLUSTER_REGION}" --tier "${CLUSTER_TIER}" --no-enable-basic-auth \
   --release-channel "${CLUSTER_RELEASE_CHANNEL}" --machine-type "${CLUSTER_ADMIN_NODE_POOL_MACHINE_TYPE}" \
   --workload-metadata=GKE_METADATA --image-type "COS_CONTAINERD" --disk-type "${CLUSTER_ADMIN_NODE_POOL_DISK_TYPE}" --disk-size "${CLUSTER_ADMIN_NODE_POOL_DISK_SIZE}" \
   --node-labels "${CLUSTER_ADMIN_NODE_POOL_LABELS}" --metadata "${CLUSTER_METADATA}" --num-nodes "${CLUSTER_ADMIN_NODE_POOL_NUM_NODES}" \
   --logging=NONE --enable-ip-alias --network "projects/${PROJECT_NAME}/global/networks/default" \
   --subnetwork "projects/${PROJECT_NAME}/regions/europe-west2/subnetworks/default" \
   --no-enable-intra-node-visibility --default-max-pods-per-node "110" --enable-dns-access \
   --enable-ip-access --security-posture=standard --workload-vulnerability-scanning=disabled \
   --no-enable-google-cloud-access --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
   --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 \
   --binauthz-evaluation-mode=DISABLED --no-enable-managed-prometheus --enable-shielded-nodes \
   --shielded-integrity-monitoring --no-shielded-secure-boot --node-locations "${CLUSTER_REGION}-${CLUSTER_REGION_ZONE}" \
   --workload-pool=${PROJECT_NAME}.svc.id.goog  --enable-private-nodes --quiet

  gcloud container clusters update trino-cluster \
  --location=europe-west2 \
  --update-addons=GcsFuseCsiDriver=ENABLED

  gcloud compute routers create trino-router \
  --network=default \
  --region="${CLUSTER_REGION}"

fi

# NAT for all subnets (auto allocates 1+ external IPs for NAT only)
gcloud compute routers nats create trino-nat \
  --router=trino-router \
  --region="${CLUSTER_REGION}" \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges


# Launch additional node pools for the Trino instances
./launch_nodes.sh "$CLUSTER_REGION_ZONE"

