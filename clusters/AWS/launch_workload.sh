#!/usr/bin/env bash
set -euo pipefail

# --- Inputs / Defaults ---
TRINO_HOST=${1:-}
RUN_NAME=${2:-}
ATTEMPT=${3:-}

kubectl run workload-pod \
  -n ${K8S_NAMESPACE} \
  --image=${TRINO_CLIENT_IMAGE} \
  --restart=Never \
  --overrides="$(cat <<EOF
{
  "spec": {
    "nodeSelector": { "pool": "admin" },
    "serviceAccountName": "trino",
    "containers": [{
      "name": "workload",
      "image": ${TRINO_CLIENT_IMAGE},
      "securityContext": {
        "capabilities": { "drop": ["MKNOD"] }
      },
     "command": ["./master.sh"],
      "args": [
        "${TRINO_HOST}",
        "${RUN_NAME}",
        "${ATTEMPT}",
        "${PROVIDER}",
        "${WAREHOUSE_PATH}",
        "${RESULTS_PATH}"
      ],
      "env": [
        { "name": "PROVIDER", "value": "${PROVIDER}" },
        { "name": "AWS_ACCESS_KEY_ID",     "value": "${AWS_ACCESS_KEY_ID}" },
        { "name": "AWS_SECRET_ACCESS_KEY", "value": "${AWS_SECRET_ACCESS_KEY}" },
        { "name": "REGION",    "value": "${REGION}" }

      ],
      "resources": {
        "requests": { "cpu": "1", "memory": "512Mi" },
        "limits":   { "cpu": "1", "memory": "512Mi" }
      }
    }]
  }
}
EOF
)"