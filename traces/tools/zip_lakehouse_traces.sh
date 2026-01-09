#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
DRY_RUN="${2:-1}"

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "Usage: $0 <cluster_dir>" >&2
  exit 1
fi

echo "Cluster root: $ROOT"
echo "Dry run: $DRY_RUN"
echo

LAKEHOUSE_RE='^lakehouse_([^_]+)_([0-9]+)$'

find "$ROOT" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' type_dir; do
  type_name="$(basename "$type_dir")"

  mapfile -d '' lh_dirs < <(
    find "$type_dir" -maxdepth 1 -type d -name 'lakehouse_*_*' -print0
  )
  [[ ${#lh_dirs[@]} -gt 0 ]] || continue

  echo "== $type_name =="

  declare -A TOKENS=()
  for d in "${lh_dirs[@]}"; do
    bn="$(basename "$d")"
    if [[ "$bn" =~ $LAKEHOUSE_RE ]]; then
      token="${BASH_REMATCH[1]}"
      TOKENS["$token"]=1
    fi
  done

  # Zip per TOKEN inside this TYPE dir
  for token in "${!TOKENS[@]}"; do
    mapfile -t token_dirs < <(
      find "$type_dir" -maxdepth 1 -type d -name "lakehouse_${token}_[0-9]*" | sort
    )
    [[ ${#token_dirs[@]} -gt 0 ]] || continue

    zip_name="lakehouse_${token}.zip"
    zip_path="$type_dir/$zip_name"

    echo "Zipping -> $type_name/$zip_name"
    for d in "${token_dirs[@]}"; do
      echo "  + $(basename "$d")"
    done

    if [[ "$DRY_RUN" == "1" ]]; then
      echo "  (dry run, not creating zip)"
      echo
      continue
    fi

    rm -f "$zip_path"
    (
      cd "$type_dir"
      zip -r "$zip_name" "${token_dirs[@]##*/}"
    )

    echo "  -> Created: $zip_path"
    echo
  done

  unset TOKENS
done

echo "Done."
