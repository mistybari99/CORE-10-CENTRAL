#!/usr/bin/env bash
# PACK-02 parallel setup: identical retries, competing slugs and a revoked
# owner must leave exactly one consistent business. Called by run-sql.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_PACK02_DISPOSABLE_ACK:-}" == I_CONFIRM_PACK02_DISPOSABLE ]] || exit 2
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) exit 2;; esac
[[ "${PGDATABASE:-}" =~ ^core10_preview_pack02_[0-9]+$ ]] || exit 2
out=$(mktemp -d /tmp/core10-pack02-races.XXXXXX)
q(){ psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }
owner="SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);"
sites='[{"kind":"showroom","label":"R1"},{"kind":"factory","label":"R2"},{"kind":"warehouse","label":"R3"}]'
# 1. Eight identical retries: every caller succeeds with the SAME receipt+readback.
pids=()
for i in {1..8}; do
  q "$owner SELECT md5(core10.pack02_setup_business_v1(11,'pack02-race','paint_hardware','Race Demo','advanced','$sites','pack02-race-0001','#225577')::text);" >"$out/same-$i.log" 2>&1 & pids+=("$!")
done
failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
[[ "$failed" == 0 ]] || { echo "FAIL identical retry errored; see $out" >&2; cat "$out"/same-*.log >&2; exit 1; }
[[ "$(cat "$out"/same-*.log | grep -E '^[0-9a-f]{32}$' | sort -u | wc -l)" == 1 ]] || { echo 'FAIL retries returned different results' >&2; exit 1; }
[[ "$(q "SELECT count(*) FROM core10.businesses WHERE slug='pack02-race'")" == 1 ]]
b=$(q "SELECT id FROM core10.businesses WHERE slug='pack02-race'")
[[ "$(q "SELECT count(*) FROM core10.sites WHERE business_id=$b")" == 3 ]]
[[ "$(q "SELECT count(*) FROM core10.stock_locations WHERE business_id=$b")" == 3 ]]
[[ "$(q "SELECT count(*) FROM core10.business_setup_runs_v1 WHERE business_id=$b")" == 1 ]]
# 2. Eight DIFFERENT request keys racing for one slug: exactly one wins, losers leave nothing.
pids=()
for i in {1..8}; do
  q "$owner SELECT core10.pack02_setup_business_v1(11,'pack02-slug-race','paint_hardware','Slug Race $i','quick','[]','pack02-slugrace-000$i','#225577') IS NOT NULL;" >"$out/slug-$i.log" 2>&1 & pids+=("$!")
done
won=0; for pid in "${pids[@]}"; do if wait "$pid"; then won=$((won+1)); fi; done
[[ "$won" == 1 ]] || { echo "FAIL slug race winners=$won" >&2; exit 1; }
[[ "$(q "SELECT count(*) FROM core10.businesses WHERE slug='pack02-slug-race'")" == 1 ]]
s=$(q "SELECT id FROM core10.businesses WHERE slug='pack02-slug-race'")
[[ "$(q "SELECT count(*) FROM core10.business_setup_runs_v1 WHERE request_key LIKE '%pack02-slugrace-%'")" == 1 ]]
[[ "$(q "SELECT count(*) FROM core10.sites WHERE business_id=$s")" == 1 ]]
[[ "$(q "$owner SELECT core10.pack02_setup_readback_v1($s)->>'integrity_ok'" | tail -1)" == true ]]
# 3. No orphan rows anywhere after the races.
[[ "$(q "SELECT count(*) FROM core10.sites x WHERE NOT EXISTS(SELECT 1 FROM core10.businesses b WHERE b.id=x.business_id)")" == 0 ]]
[[ "$(q "SELECT count(*) FROM core10.business_configuration_v1 c WHERE NOT EXISTS(SELECT 1 FROM core10.business_setup_runs_v1 r WHERE r.business_id=c.business_id)")" == 0 ]]
# 4. Owner revoked while 8 setups are queued: none may create a business.
q "UPDATE core10.tenant_members SET active=false WHERE user_id='11111111-1111-4111-8111-111111111111'"
pids=()
for i in {1..8}; do
  q "$owner SELECT core10.pack02_setup_business_v1(11,'pack02-revoked-$i','paint_hardware','Revoked $i','quick','[]','pack02-revoked-000$i','#225577');" >"$out/rev-$i.log" 2>&1 & pids+=("$!")
done
ok=0; for pid in "${pids[@]}"; do if wait "$pid"; then ok=$((ok+1)); fi; done
[[ "$ok" == 0 ]] || { echo "FAIL revoked owner created $ok businesses" >&2; exit 1; }
grep -q 'BUILD01_SETUP_DENIED' "$out/rev-1.log"
[[ "$(q "SELECT count(*) FROM core10.businesses WHERE slug LIKE 'pack02-revoked-%'")" == 0 ]]
rm -rf "$out"
echo 'PASS PACK-02 concurrency: 8 identical retries one result; 8-way slug race one winner no orphan; revoked owner denied'
