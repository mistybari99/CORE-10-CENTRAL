#!/usr/bin/env bash
# PACK01-only ephemeral integration: no git merge, no PACK02 file overwrite.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Two checkout paths required'; exit 2; }
dst=$(cd "$1" && pwd -P)
src=$(cd "$2" && pwd -P)
[[ "$dst" != "$src" ]] || { echo 'Separate checkouts required'; exit 2; }
[[ "$(git -C "$src" rev-parse HEAD)" == "5f2653c03b4ad9fa900988246fc6576d61ab4c77" ]] || { echo 'PR105 SHA mismatch'; exit 2; }
[[ -z "$(git -C "$dst" status --porcelain)" ]] || { echo 'Dirty PACK01 checkout'; exit 2; }
for f in \
 core10-pack02-workspace.js core10-pack02-workspace.css \
 core10-pack02-controls.js core10-pack02-signed.js core10-pack02-app.js \
 internal/enterprise-sql/c10_pack02_workspace_v1.sql \
 internal/enterprise-sql/c10_pack02_controls_v1.sql; do
  [[ -f "$src/$f" ]] || { echo "Owned path missing $f"; exit 2; }
  if [[ -e "$dst/$f" ]]; then
    # S0: PR105 is merged for real. Accept only a byte-identical copy of the pinned source.
    cmp -s "$src/$f" "$dst/$f" || { echo "Owned path differs from pinned PR105 source: $f"; exit 2; }
    merged=1
  else
    mkdir -p "$(dirname "$dst/$f")"
    cp "$src/$f" "$dst/$f"
  fi
done
[[ -d "$src/tests/pack02" ]] || { echo "Test path missing"; exit 2; }
if [[ -e "$dst/tests/pack02" ]]; then
  diff -rq "$src/tests/pack02" "$dst/tests/pack02" >/dev/null || { echo "tests/pack02 differs from pinned PR105 source"; exit 2; }
  merged=1
else
  cp -R "$src/tests/pack02" "$dst/tests/pack02"
fi
git -C "$dst" diff --quiet
git -C "$dst" diff --cached --quiet
if [[ "${merged:-0}" == 1 ]]; then echo 'PASS PR105-owned files already integrated and identical to the pinned source'
else echo 'PASS PR105-owned files staged temporarily; no tracked PACK01 changes, no merge'; fi
