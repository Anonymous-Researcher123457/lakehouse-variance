#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
DRY_RUN="${DRY_RUN:-1}"

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "Usage: $0 <cluster_dir>" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "ERROR: unzip is required." >&2
  exit 1
fi

echo "Cluster root: $ROOT"
echo "Dry run: $DRY_RUN"
echo

single_top_dir() {
  local zip_path="$1"
  unzip -Z1 "$zip_path" \
    | awk -F/ 'NF{print $1}' \
    | sort -u \
    | awk 'NR==1{first=$0} NR>1{multi=1} END{ if(!multi && length(first)>0) print first; }'
}

find "$ROOT" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' type_dir; do
  type_name="$(basename "$type_dir")"

  mapfile -t zips < <(find "$type_dir" -maxdepth 1 -type f -name 'lakehouse_*.zip' | sort)

  [[ ${#zips[@]} -gt 0 ]] || continue

  echo "== $type_name =="

  for zip_path in "${zips[@]}"; do
    zip_name="$(basename "$zip_path")"
    echo "Unzipping -> $type_name/$zip_name"

    if [[ "$DRY_RUN" == "1" ]]; then
      echo "  DRY_RUN would unzip into: $type_dir"
      top="$(single_top_dir "$zip_path" || true)"
      if [[ -n "${top:-}" ]]; then
        echo "  DRY_RUN would flatten outer dir: $top/"
      else
        echo "  DRY_RUN: no single outer dir detected (no flatten needed)"
      fi
      echo
      continue
    fi

    unzip -o -q "$zip_path" -d "$type_dir"

    top="$(single_top_dir "$zip_path" || true)"
    if [[ -n "${top:-}" && -d "$type_dir/$top" ]]; then
      echo "  Flattening outer dir: $top/"
      shopt -s dotglob nullglob
      mv -f "$type_dir/$top"/* "$type_dir"/ 2>/dev/null || true
      shopt -u dotglob nullglob
      rmdir "$type_dir/$top" 2>/dev/null || true
    fi

    echo "  -> Done"
    echo
  done
done

echo "Done."
