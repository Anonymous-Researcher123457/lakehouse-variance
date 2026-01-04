#!/bin/bash

SCRIPT="python3 /src/run_workload.py"

TRINO_HOST="${1:-}"
RESULTS_PATH="${2:-}"
RUN_NAME="${4:-"TRINO_RUN"}"
ATTEMPT="${5:-}"

if [ -z "$TRINO_HOST" ]; then
    echo "❌ No host IP provided"
    exit 1
fi
if [ -z "$RESULTS_PATH" ]; then
    echo "❌ No Filepath to record results was provided"
    exit 1
fi

if [ -z "$ATTEMPT" ]; then
    echo "❌ No attempt number provided"
    exit 1
fi


$SCRIPT --host "$TRINO_HOST" --results_path "$RESULTS_PATH" --run_name "$RUN_NAME" --attempt "$ATTEMPT"

echo "lakehouse workload completed for Run: ${RUN_NAME}, Attempt: ${ATTEMPT}."
