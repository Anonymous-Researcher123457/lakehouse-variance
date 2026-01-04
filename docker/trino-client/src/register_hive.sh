#!/usr/bin/env bash
set -euo pipefail

TRINO_HOST="${1:?missing TRINO_HOST}"
WAREHOUSE_PATH="${2:?missing WAREHOUSE_PATH}"
SCHEMA="${3:-tpcds}"
TABLES_ARG="${4:-}"

SCRIPT="python3 /src/import_tables.py"

TABLES=(
  call_center
  catalog_page
  catalog_returns
  catalog_sales
  customer
  customer_address
  customer_demographics
  date_dim
  household_demographics
  income_band
  inventory
  item
  promotion
  reason
  ship_mode
  store
  store_returns
  store_sales
  time_dim
  warehouse
  web_page
  web_returns
  web_sales
  web_site
)

if [[ -n "$TABLES_ARG" ]]; then
  IFS=',' read -r -a TABLES <<< "$TABLES_ARG"
fi

echo "[INFO] Registering schema=$SCHEMA with ${#TABLES[@]} tables"
$SCRIPT --host "$TRINO_HOST" --warehouse "$WAREHOUSE_PATH" --schema "$SCHEMA" --tables "${TABLES[@]}"
