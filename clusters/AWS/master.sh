#!/usr/bin/env bash

# -------- Config --------
export PROVIDER="AWS"

# GLOBAL EKS CONFIGS
export CLUSTER_NAME="Trino_Cluster"
export AVAILABILITY_ZONE="eu-west-2a"
export REGION="eu-west-2"
export K8S_VERSION="1.31"                      # NOTE: Check for latest EKS support window.

# Authentication Config
export AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"    # Required to create IAM policy for ALB controller
export AWS_ACCESS_KEY_ID="YOUR_AWS_ACCESS_KEY_ID" # AWS access key ID for CLI authentication
export AWS_SECRET_ACCESS_KEY="YOUR_AWS_SECRET_ACCESS_KEY" # AWS secret access key for CLI authentication
export K8S_NAMESPACE="YOUR_NAMESPACE"
export SERVICE_ACCOUNT="YOUR_SERVICE_ACCOUNT" # Used by Trino pods (annotated for Pod Identity) to access S3 buckets
export TRINO_POD_ROLE_ARN="arn:aws:iam::<YOUR_IDENTITY_ROLE>" # AWS IAM role ARN associated with the Trino ServiceAccount for Pod Identity

# Workload Run Configs
export RUN_NAME="SF_1000"
export RESULTS_PATH="s3://<BUCKET>/Results/" # Directory in S3 bucket where results are written to
export WAREHOUSE_PATH="s3://<BUCKET>/warehouse/<SCHEMA>/" # Directory in S3 bucket where table data resides
export TRINO_CLIENT_IMAGE="YOUR_CLIENT_IMAGE:TAG" # Trino image created from docker/trino-client

DEPLOY_CLUSTER=true

ATTEMPTS=5

# Launch script which creates the Kubernetes Cluster and node pools
echo "|=============== Launching Kubernetes Cluster and Node Pools ===============|"
if [ "$DEPLOY_CLUSTER" = "true" ]; then
  ./launch_cluster.sh
fi

for i in $(seq 1 $ATTEMPTS); do

  # Launch Trino pod cluster and return the trino ingress IP
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
