#!/usr/bin/env bash
# PACK01-only ephemeral integration: no git merge, no PACK02 file overwrite.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Two checkout paths required'; exit 2; }
dst=$(cd "$1" && pwd -P)
src=$(cd "$2" && pwd -P)
[[ "$dst" != "$src" ]] || { echo 'Separate checkouts required'; exit 2; }
[[ "$(git -C "$src" rev-parse HEAD)" == "7afe9ea9106286bea6391a58bbf7c52e9def67f9" ]] || { echo 'PR105 SHA mismatch'; exit 2; }
[[ -z "$(git -C "$dst" status --porcelain)" ]] || { echo 'Dirty PACK01 checkout'; exit 2; }
for f in \
 core10-pack02-workspace.js core10-pack02-workspace.css \
 core10-pack02-controls.js core10-pack02-signed.js core10-pack02-app.js \
 internal/enterprise-sql/c10_pack02_workspace_v1.sql \
 internal/enterprise-sql/c10_pack02_controls_v1.sql; do
  [[ -f "$src/$f" && ! -e "$dst/$f" ]] || { echo "Owned path collision/missing $f"; exit 2; }
  mkdir -p "$(dirname "$dst/$f")"
  cp "$src/$f" "$dst/$f"
done
[[ -d "$src/tests/pack02" && ! -e "$dst/tests/pack02" ]] || { echo "Test path collision"; exit 2; }
cp -R "$src/tests/pack02" "$dst/tests/pack02"
git -C "$dst" diff --quiet
git -C "$dst" diff --cached --quiet
echo 'PASS PR105-owned files staged temporarily; no tracked PACK01 changes, no merge'
