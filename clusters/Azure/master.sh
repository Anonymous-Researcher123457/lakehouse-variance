#!/usr/bin/env bash

# -------- Config --------
export PROVIDER="AZURE"

# GLOBAL AKS CONFIGS
export RESOURCE_GROUP="YOUR_RESOURCE_GROUP"
export AKS_CLUSTER_NAME="YOUR_CLUSTER_NAME"
export LOCATION="uksouth"
export NAMESPACE="pgr24james"

# Authentication Config
export SUBSCRIPTION_ID="YOUR_SUBSCRIPTION_ID" # Your Azure subscription ID
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=<STORAGE_ACCOUNT>;AccountKey=<ACCOUNT_KEY>;EndpointSuffix=core.windows.net"

# Workload Run Configs
export RUN_NAME="SF_1000"
export WAREHOUSE_PATH="abfss://<CONTAINER>@<STORAGE_ACCOUNT>.dfs.core.windows.net/warehouse/<SCHEMA>/" # Directory in blob storage where results are written to
export RESULTS_PATH="abfss://<CONTAINER>@<STORAGE_ACCOUNT>.dfs.core.windows.net/Results/" # Directory in blob storage where table data resides
export TRINO_CLIENT_IMAGE="YOUR_CLIENT_IMAGE:TAG" # Trino image created from docker/trino-client

DEPLOY_CLUSTER=true
DEPLOY_NODES=true

ATTEMPTS=5

echo "|=============== Launching Kubernetes Cluster ===============|"
if [ "$DEPLOY_CLUSTER" = "true" ]; then
  ./launch_cluster.sh
fi
echo "|=============== Launching Launching Trino Node Pools ===============|"
if [ "$DEPLOY_NODES" = "true" ]; then
  ./launch_nodes.sh
fi

for i in $(seq 1 $ATTEMPTS); do

  echo "|=============== Launching Trino Instance ${i} ===============|"
  ./launch_trino.sh
  source .trino.env

  if [[ -z "${TRINO_HOST:-}" ]]; then
        echo "Error: TRINO_INGRESS_ADDR is not set by launch_trino.sh" >&2
        exit 1
  fi

  ./launch_workload.sh "$TRINO_HOST" "$RUN_NAME" "$i"

  ./wait.sh

  ./delete_trino.sh

done

./delete_cluster.sh