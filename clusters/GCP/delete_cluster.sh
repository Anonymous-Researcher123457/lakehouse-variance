#!/usr/bin/env bash
set -euo pipefail

# Delete entire cluster
gcloud container clusters delete "${GKE_CLUSTER_NAME}" \
  --project "${PROJECT_NAME}" \
  --region "${GKE_REGION}" \
  --quiet
