#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
PORT="${2:-9083}"
TIMEOUT_SEC="${3:-300}"
SLEEP_SEC="${4:-2}"

start_ts=$(date +%s)

echo "[WAIT] Waiting for Hive Metastore at ${HOST}:${PORT} (timeout=${TIMEOUT_SEC}s)…"

check_tcp() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$HOST" "$PORT"
  elif command -v timeout >/dev/null 2>&1; then
    timeout 2 bash -c ">/dev/tcp/${HOST}/${PORT}" 2>/dev/null
  else
    bash -c ">/dev/tcp/${HOST}/${PORT}" 2>/dev/null
  fi
}

while true; do
  if check_tcp; then
    echo "[WAIT] Hive Metastore is reachable."
    break
  fi
  now=$(date +%s)
  elapsed=$(( now - start_ts ))
  if (( elapsed >= TIMEOUT_SEC )); then
    echo "[WAIT][ERROR] Timed out after ${TIMEOUT_SEC}s waiting for ${HOST}:${PORT}" >&2
    exit 1
  fi
  sleep "$SLEEP_SEC"
done
