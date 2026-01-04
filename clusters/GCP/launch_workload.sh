#!/usr/bin/env bash
set -euo pipefail

# --- Inputs / Defaults ---
TRINO_HOST=${1:-}
RUN_NAME=${2:-}
ATTEMPT=${3:-}

kubectl run workload-pod \
  -n pgr24james \
  --image=$TRINO_CLIENT_IMAGE \
  --restart=Never \
  --overrides="$(cat <<EOF
{
  "spec": {
    "nodeSelector": { "pool": "admin" },
    "serviceAccountName": "trino-sa",
    "tolerations": [
      { "key": "node", "operator": "Equal", "value": "trino", "effect": "NoSchedule" }
    ],
    "containers": [{
      "name": "workload",
      "image": "${TRINO_CLIENT_IMAGE}",
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
        { "name": "PROVIDER", "value": "${PROVIDER}" }
      ]
    }]
  }
}
EOF
)"