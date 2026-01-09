#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
DRY_RUN="${2:-1}"

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "Usage: $0 <cluster_or_type_dir> [dry_run_flag 0|1]" >&2
  exit 1
fi

if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
  echo "ERROR: DRY_RUN must be 0 or 1 (got: $DRY_RUN)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 1
fi

# Convert Trino duration strings to seconds
dur_to_s='
def dur_to_seconds($d):
  if ($d == null) then null
  elif ($d|type) == "number" then $d
  else
    ($d|tostring) as $s
    | if ($s|test("^[0-9]+(\\.[0-9]+)?$")) then ($s|tonumber)
      elif ($s|test("^[0-9]+(\\.[0-9]+)?s$")) then ($s|sub("s$";"")|tonumber)
      elif ($s|test("^[0-9]+(\\.[0-9]+)?ms$")) then (($s|sub("ms$";"")|tonumber)/1000)
      elif ($s|test("^[0-9]+(\\.[0-9]+)?(us|µs)$")) then (($s|sub("(us|µs)$";"")|tonumber)/1000000)
      elif ($s|test("^[0-9]+(\\.[0-9]+)?ns$")) then (($s|sub("ns$";"")|tonumber)/1000000000)
      elif ($s|test("^[0-9]+(\\.[0-9]+)?m$")) then (($s|sub("m$";"")|tonumber)*60)
      elif ($s|test("^[0-9]+(\\.[0-9]+)?h$")) then (($s|sub("h$";"")|tonumber)*3600)
      else null
      end
  end;
'

LAKEHOUSE_RE='^lakehouse_([^_]+)_([0-9]+)$'

shopt -s nullglob

process_type_dir() {
  local type_dir="$1"
  local type_name
  type_name="$(basename "$type_dir")"

  local lakehouse_dirs=()
  while IFS= read -r -d '' d; do lakehouse_dirs+=("$d"); done < <(
    find "$type_dir" -maxdepth 1 -type d -name 'lakehouse_*_*' -print0
  )

  [[ ${#lakehouse_dirs[@]} -gt 0 ]] || return 0

  for lakehouse_dir in "${lakehouse_dirs[@]}"; do
    [[ -d "$lakehouse_dir" ]] || continue

    local dir_name
    dir_name="$(basename "$lakehouse_dir")"
    if [[ ! "$dir_name" =~ $LAKEHOUSE_RE ]]; then
      continue
    fi

    local TOKEN RUN
    TOKEN="${BASH_REMATCH[1]}"
    RUN="${BASH_REMATCH[2]}"

    local out_file="$type_dir/Workload_log_${TOKEN}_${RUN}.ndjson"
    echo "Building $out_file from $type_name/$dir_name ..."

    mapfile -t qfiles < <(find "$lakehouse_dir" -maxdepth 1 -type f -name 'q*.json' | sort -V)

    if [[ "$DRY_RUN" == "1" ]]; then
      echo "  DRY_RUN: would write -> $out_file"
      echo "  DRY_RUN: would process $((${#qfiles[@]})) q*.json files"
      continue
    fi

    : > "$out_file"

    for qfile in "${qfiles[@]}"; do
      [[ -f "$qfile" ]] || continue
      local qbase qid
      qbase="$(basename "$qfile")"
      qid="${qbase%.json}"

      jq -c --arg qid "$qid" '
        '"$dur_to_s"'
        .queryStats as $qs
        | (dur_to_seconds($qs.elapsedTime)) as $elapsed_s
        | (dur_to_seconds($qs.executionTime)) as $execution_s
        | (dur_to_seconds($qs.analysisTime)) as $planning_s
        | (dur_to_seconds($qs.resourceWaitingTime)) as $waiting_s
        | {
            query_id: $qid,
            "Runtime (s)": (if $elapsed_s == null then -1 else $elapsed_s end),
            elapsed_s:          (if $elapsed_s == null then -1 else $elapsed_s end),
            execution_s:        (if $execution_s == null then -1 else $execution_s end),
            planning_s:         (if $planning_s == null then -1 else $planning_s end),
            resource_waiting_s: (if $waiting_s == null then -1 else $waiting_s end)
          }
      ' "$qfile" >> "$out_file"
    done

    echo "  -> wrote $(wc -l < "$out_file") lines"
  done
}

if compgen -G "$ROOT/lakehouse_*_*" > /dev/null; then
  process_type_dir "$ROOT"
else
  for type_dir in "$ROOT"/*; do
    [[ -d "$type_dir" ]] || continue
    process_type_dir "$type_dir"
  done
fi

echo "Done."
