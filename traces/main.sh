#!/usr/bin/env bash
set -euo pipefail

# If no step flags are provided, defaults to: --scrub --summary --zip

BASE_DIR="."
DRY="1"

STEPS=()

print_usage() {
  cat <<EOF
Usage: $0 [--base <dir>] [--dry <0|1>] [--zip] [--unzip] [--scrub] [--summary]

Options:
  --base <dir>     Base directory containing study_*/<cluster> dirs (default: .)
  --dry <0|1>      Dry run flag to pass to tools (default: 1)
  --zip            Run zip step
  --unzip          Run unzip step
  --scrub          Run scrub step
  --summary        Run workload-log generation step
  -h, --help       Show this help

Order:
  Steps are executed in the SAME ORDER you list them on the command line.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE_DIR="${2:-}"
      shift 2
      ;;
    --dry)
      DRY="${2:-}"
      shift 2
      ;;
    --zip)
      STEPS+=("zip")
      shift
      ;;
    --unzip)
      STEPS+=("unzip")
      shift
      ;;
    --scrub)
      STEPS+=("scrub")
      shift
      ;;
    --summary)
      STEPS+=("summary")
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#STEPS[@]} -eq 0 ]]; then
  STEPS=("scrub" "summary" "zip")
fi

if [[ ! -d "$BASE_DIR" ]]; then
  echo "ERROR: base dir not found: $BASE_DIR" >&2
  exit 1
fi

TOOLS_DIR="./tools"
SCRUB_FILTER="$TOOLS_DIR/scrub.jq"

SCRUB_SH="$TOOLS_DIR/scrub_lakehouse_traces.sh"
MAKELOG_SH="$TOOLS_DIR/make_lakehouse_workload_logs.sh"
ZIP_SH="$TOOLS_DIR/zip_lakehouse_traces.sh"
UNZIP_SH="$TOOLS_DIR/unzip_lakehouse_traces.sh"

require_file() {
  local f="$1"
  if [[ ! -e "$f" ]]; then
    echo "ERROR: missing required file: $f" >&2
    exit 1
  fi
}

# Validate required tool files based on requested steps
for step in "${STEPS[@]}"; do
  case "$step" in
    scrub)   require_file "$SCRUB_SH"; require_file "$SCRUB_FILTER" ;;
    summary) require_file "$MAKELOG_SH" ;;
    zip)     require_file "$ZIP_SH" ;;
    unzip)   require_file "$UNZIP_SH" ;;
    *) echo "ERROR: invalid internal step: $step" >&2; exit 1 ;;
  esac
done

IGNORE=(

)

is_ignored() {
  local rel="$1"
  for ig in "${IGNORE[@]}"; do
    [[ "$rel" == "$ig" ]] && return 0
  done
  return 1
}

echo "Base: $BASE_DIR"
echo "Tools: $TOOLS_DIR"
echo "Dry run: $DRY"
echo "Steps (in CLI order): ${STEPS[*]}"
echo "Ignore: ${IGNORE[*]:-(none)}"
echo

run_steps_for_cluster() {
  local cluster_dir="$1"
  local rel="$2"

  echo "== Processing: $rel =="

  export DRY_RUN="$DRY"

  local idx=1
  for step in "${STEPS[@]}"; do
    case "$step" in
      unzip)
        echo "-- $idx) Unzip"
        bash "$UNZIP_SH" "$cluster_dir" "$DRY"
        ;;
      scrub)
        echo "-- $idx) Scrub"
        bash "$SCRUB_SH" "$cluster_dir" "$DRY" "$SCRUB_FILTER"
        ;;
      summary)
        echo "-- $idx) Summary (workload logs)"
        bash "$MAKELOG_SH" "$cluster_dir" "$DRY"
        ;;
      zip)
        echo "-- $idx) Zip"
        bash "$ZIP_SH" "$cluster_dir" "$DRY"
        ;;
    esac
    idx=$((idx + 1))
  done

  echo
}

find "$BASE_DIR" -maxdepth 2 -mindepth 2 -type d -print0 \
  | while IFS= read -r -d '' cluster_dir; do
      rel="${cluster_dir#"$BASE_DIR"/}"

      [[ "$rel" == study_*/* ]] || continue
      [[ "$rel" != */*/* ]] || continue

      if is_ignored "$rel"; then
        echo "== Skipping (ignored): $rel =="
        echo
        continue
      fi

      run_steps_for_cluster "$cluster_dir" "$rel"
    done

echo "All done."
