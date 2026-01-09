#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"      # cluster dir (e.g., AWS, Azure, GCP, Self_Hosted)
DRY_RUN="${2:-1}"       # 1 = dry run, 0 = actually scrub
FILTER="${3:-scrub.jq}"

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: jq filter not found: $FILTER" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
  echo "ERROR: root dir not found: $ROOT_DIR" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 1
fi

echo "Using jq filter: $FILTER"
echo "Root (cluster): $ROOT_DIR"
echo "Dry run: $DRY_RUN"
echo

# Matches: lakehouse_<TOKEN>_<RUNNUM>
LAKEHOUSE_DIR_GLOB='lakehouse_*_[0-9]*'

# Iterate over TYPE directories inside the cluster
find "$ROOT_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' type_dir; do
  type_name="$(basename "$type_dir")"

  # Find lakehouse dirs inside this TYPE dir
  mapfile -d '' lakehouse_dirs < <(
    find "$type_dir" -maxdepth 1 -type d -name "$LAKEHOUSE_DIR_GLOB" -print0
  )

  if [[ ${#lakehouse_dirs[@]} -eq 0 ]]; then
    continue
  fi

  echo "== Processing $type_name =="

  for lh_dir in "${lakehouse_dirs[@]}"; do
    echo "  -> $(basename "$lh_dir")"

    # Find JSON files in this lakehouse dir
    mapfile -d '' json_files < <(
      find "$lh_dir" -maxdepth 1 -type f -name '*.json' \
        ! -name '*.scrubbed.json' \
        ! -name '*.ndjson' \
        -print0
    )

    if [[ ${#json_files[@]} -eq 0 ]]; then
      echo "     (no json files)"
      continue
    fi

    for f in "${json_files[@]}"; do
      if [[ "$DRY_RUN" == "1" ]]; then
        echo "     DRY_RUN would scrub: $f"
        continue
      fi

      tmp="${f}.tmp.$$"
      jq -f "$FILTER" "$f" > "$tmp"
      mv -f "$tmp" "$f"
      echo "     scrubbed: $(basename "$f")"
    done
  done

  echo
done

echo "Done."
