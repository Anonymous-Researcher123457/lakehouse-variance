#!/usr/bin/env bash

# -------- Config --------
export PROVIDER="GCP"

# GLOBAL GKE CONFIGS
export PROJECT_NAME="YOUR_GCP_PROJECT_NAME"
export NAMESPACE="YOUR_K8_NAMESPACE"
export GKE_CLUSTER_NAME="YOUR_CLUSTER_NAME"
export GKE_REGION="europe-west2"

# Workload Run Configs
export TRINO_CLIENT_IMAGE="YOUR_CLIENT_IMAGE:TAG" # Trino image created from docker/trino-client
export RUN_NAME="TPCDS_Run"
export RESULTS_PATH="gs://<BUCKET>/Time_Workload/Results" # Directory in GS bucket where results are written to
export WAREHOUSE_PATH="gs://<BUCKET>/warehouse/<SCHEMA>" # Directory in GS bucket where table data resides

DEPLOY_CLUSTER=true
DEPLOY_TRINO=true
RUN_SYN_WORKLOAD=false
RUN_WORK_LOAD=true
DELETE_TRINO=true
DELETE_CLUSTER=true

ATTEMPTS=5

# Launch script which creates the Kubernetes Cluster and node pools
echo "|=============== Launching Kubernetes Cluster and Node Pools ===============|"
if [ "$DEPLOY_CLUSTER" = "true" ]; then
  ./launch_cluster.sh
fi

for i in $(seq 1 $ATTEMPTS); do

  if [ "$DEPLOY_TRINO" = "true" ]; then
    echo "|=============== Launching Trino Instance ${i} ===============|"
    ./launch_trino.sh || { echo "Launch failed"; exit 1; }
  fi
  source .trino.env

  if [ "$RUN_SYN_WORKLOAD" = "true" ]; then
    echo "|=============== Launching Synthetic Workload ===============|"
    kubectl apply -f ./YAML/syn_workload.yaml -n $NAMESPACE
  fi

  if [ "$RUN_WORK_LOAD" = "true" ]; then
    echo "|=============== Launching Query Workload ===============|"
    ./launch_workload.sh "$TRINO_HOST" "$RUN_NAME" "$i"
    ./wait.sh
  fi

  if [ "$DELETE_TRINO" = "true" ]; then
    echo "|=============== Deleting Trino Instance ${i} ===============|"
    ./delete_trino.sh
  fi
done

if [ "$DELETE_CLUSTER" = "true" ]; then
  ./delete_cluster.sh
fi