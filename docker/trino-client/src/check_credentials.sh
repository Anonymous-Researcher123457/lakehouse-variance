#!/usr/bin/env bash
set -euo pipefail

PROVIDER=${1:?Usage: $0 [AWS|AZURE|GCP]}


case "$PROVIDER" in
  AWS)
    : "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set for AWS}"
    : "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set for AWS}"
    : "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION must be set for AWS}"
    echo "[INFO] AWS credentials OK"
    ;;
  AZURE)
    : "${AZURE_STORAGE_CONNECTION_STRING:?AZURE_STORAGE_CONNECTION_STRING must be set for AZURE}"
    if [[ -n "${AZURE_STORAGE_ACCOUNT_NAME:-}" ]]; then
      echo "[ERROR] AZURE_STORAGE_ACCOUNT_NAME is set, but this workload expects AZURE_STORAGE_CONNECTION_STRING only." >&2
      exit 1
    fi
    echo "[INFO] Azure credentials OK"
    ;;
  GCP)
    echo "[WARN] GCP authentication uses assumed credentials. Ensure the pod's Kubernetes ServiceAccount is correctly bound to a Google IAM ServiceAccount with access to the specified GS bucket."

    ;;
  *)
    echo "[ERROR] Unknown provider: $PROVIDER (use AWS|AZURE|GCP|LOCAL)" >&2
    exit 1
    ;;
esac

