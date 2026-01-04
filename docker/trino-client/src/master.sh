#!/usr/bin/env bash
set -euo pipefail

TRINO_HOST=${1:-"0.0.0.0"}
RUN_NAME=${2:-"TRINO_RUN"}
ATTEMPT=${3:-}
PROVIDER=${4:?Usage: $0 [AWS|AZURE|GCP]}
WAREHOUSE_PATH="${5:-}"
RESULTS_PATH="${6:-}"
REGISTER_HIVE="${7:-true}"
SCHEMA="${8:-tpcds}"
TABLES_ARG="${9:-}"

CHECK_HIVE=true

echo "[INFO] Checking ENV vars exist"
/src/check_credentials.sh "$PROVIDER"

if [[ "$CHECK_HIVE" == "true" ]]; then
  echo "[INFO] Checking Hive metastore is available"
  /src/check_hive.sh
fi

if [[ "$REGISTER_HIVE" == "true" ]]; then
  echo "[INFO] Registering Hive schema=$SCHEMA at $TRINO_HOST with warehouse $WAREHOUSE_PATH"
  /src/register_hive.sh "$TRINO_HOST" "$WAREHOUSE_PATH" "$SCHEMA" "$TABLES_ARG"
fi

echo "[INFO] Running workload: run=$RUN_NAME attempt=$ATTEMPT"
/src/run_all.sh "$TRINO_HOST" "$RESULTS_PATH" "$RUN_NAME" "$ATTEMPT"


