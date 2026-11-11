#!/usr/bin/env bash
# C10-A055 real parallel-session concurrency: separate psql backends race the same business. Disposable PostgreSQL only.
set -uo pipefail
cd "$(dirname "$0")/.."
DB=${A055_CONC_DB:-am_concurrency}
tests/c10_a055_load.sh "$DB" >/dev/null
export PGDATABASE=$DB
P="psql -X -q -At -v ON_ERROR_STOP=1"
BO=22222222-2222-4222-8222-222222222222; SUP=d1111111-1111-4111-8111-111111111111
FAILS=0; OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
fail(){ echo "FAIL: $*"; FAILS=$((FAILS+1)); }
# one transactional session acting as <uuid>; prints the RPC result or the error text
sess(){ local who=$1 sql=$2; $P -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$who',true); SELECT ($sql)::text; COMMIT;" 2>&1 | grep -v '^[0-9a-f-]\{36\}$' | grep -v -E '^(BEGIN|SET|COMMIT)$'; }
race(){ local n=$1 tag=$2 who=$3 tmpl=$4 same=$5; local pids=() i
 for i in $(seq 1 "$n"); do
  local key="cc-$tag-$i"; [ "$same" = same ] && key="cc-$tag-shared"
  ( sess "$who" "${tmpl//@K/\'$key\'}" >"$OUT/$tag.$i" ) & pids+=($!)
 done; wait "${pids[@]}"; }
ok_count(){ grep -l '"status": "applied"' "$OUT"/$1.* 2>/dev/null | wc -l; }
err_count(){ grep -l "$2" "$OUT"/$1.* 2>/dev/null | wc -l; }
SU(){ psql -X -q -At -c "$1"; }
SU "SELECT c10_demo.ami_ensure_business(101)" >/dev/null
CAT=$(SU "SELECT id FROM c10_demo.am_categories WHERE business_id=101 AND code='PROD-EQ'")

# 1. same request key from 8 sessions at once: ONE asset, identical receipts
race 8 asset $BO "c10_demo.am_create_asset_v1(101,@K,'{\"name\":\"Race asset\",\"category_id\":$CAT,\"site_id\":1001}'::jsonb,'race create')" same
[ "$(SU "SELECT count(*) FROM c10_demo.am_assets WHERE name='Race asset'")" = 1 ] || fail "idempotent create produced $(SU "SELECT count(*) FROM c10_demo.am_assets WHERE name='Race asset'") assets"
[ "$(cat "$OUT"/asset.* | sort -u | wc -l)" = 1 ] || fail "replayed receipts differ"
A=$(SU "SELECT id FROM c10_demo.am_assets WHERE name='Race asset'")
echo "ok 1 idempotent parallel create (1 asset, 8 identical receipts)"

# 2. optimistic concurrency: 8 distinct keys, same expected version -> exactly one winner
V=$(SU "SELECT version FROM c10_demo.am_assets WHERE id=$A")
race 8 upd $BO "c10_demo.am_update_asset_v1(101,@K,$A,$V,'{\"location_note\":\"Bay racer\"}'::jsonb,'race update')" diff
W=$(ok_count upd); S=$(err_count upd am_stale_version)
[ "$W" = 1 ] && [ "$S" = 7 ] || fail "optimistic lock: winners=$W stale=$S (want 1/7)"
[ "$(SU "SELECT version FROM c10_demo.am_assets WHERE id=$A")" = $((V+1)) ] || fail "version advanced more than once"
echo "ok 2 optimistic concurrency (1 winner, 7 am_stale_version)"

# 3. work-order transition race: 6 sessions submit the same draft
WO=$(sess $SUP "c10_demo.am_create_work_order_v1(101,'cc-wo-create-1',jsonb_build_object('asset_id',$A,'title','Race WO'))" | sed -n 's/.*"id": \([0-9]*\).*/\1/p' | head -1)
[ -n "$WO" ] || { echo "FAIL: could not create WO"; exit 1; }
WV=$(SU "SELECT version FROM c10_demo.am_work_orders WHERE id=$WO")
race 6 sub $SUP "c10_demo.am_wo_transition_v1(101,@K,$WO,$WV,'submit',NULL,NULL)" diff
W=$(ok_count sub)
[ "$W" = 1 ] || fail "submit race winners=$W"
[ "$(SU "SELECT status FROM c10_demo.am_work_orders WHERE id=$WO")" = SUBMITTED ] || fail "WO not SUBMITTED"
[ "$(SU "SELECT count(*) FROM c10_demo.am_wo_history WHERE work_order_id=$WO AND to_status='SUBMITTED'")" = 1 ] || fail "duplicate history rows"
echo "ok 3 work-order transition race (1 winner, 1 history row)"

# 4. plan generation race: 6 sessions generate from the same due target -> exactly one open PM work order
sess $SUP "c10_demo.am_save_plan_v1(101,'cc-plan-0001',NULL,NULL,jsonb_build_object('name','Race plan','plan_type','preventive','asset_id',$A,'frequency_kind','weekly','interval_n',1,'start_on',(current_date-14)::text),NULL)" >/dev/null
T=$(SU "SELECT t.id FROM c10_demo.am_plan_targets t JOIN c10_demo.am_plans p ON p.id=t.plan_id WHERE p.name='Race plan'")
race 6 gen $SUP "c10_demo.am_generate_work_orders_v1(101,@K,ARRAY[$T]::bigint[],NULL,7)" diff
N=$(SU "SELECT count(*) FROM c10_demo.am_work_orders WHERE plan_target_id=$T")
[ "$N" = 1 ] || fail "plan generation race created $N work orders"
echo "ok 4 parallel generation (exactly 1 work order for the target)"

# 5. breakdown race on one asset: one open downtime window
A2=$(sess $BO "c10_demo.am_create_asset_v1(101,'cc-asset-two1','{\"name\":\"Race asset 2\",\"category_id\":$CAT,\"site_id\":1001}'::jsonb,'second')" | sed -n 's/.*"asset_id": \([0-9]*\).*/\1/p' | head -1)
race 6 brk $BO "c10_demo.am_report_breakdown_v1(101,@K,$A2,'{\"description\":\"Jam\",\"priority\":\"high\"}'::jsonb)" diff
N=$(SU "SELECT count(*) FROM c10_demo.am_downtime WHERE asset_id=$A2 AND ended_at IS NULL")
[ "$N" = 1 ] || { fail "breakdown race left $N open downtime windows (A2=$A2)"; head -c 300 "$OUT"/brk.1; }
echo "ok 5 breakdown race (1 open downtime window)"

# 6. cross-check integrity after the storm
I=$(sess $BO "c10_demo.am_integrity_report_v1(101)")
echo "$I" | grep -q '"ok": true' || fail "integrity after concurrency: $I"
echo "ok 6 integrity report clean after concurrency"

[ "$FAILS" = 0 ] && echo "A055_CONCURRENCY_PASS" || { echo "A055_CONCURRENCY_FAILED ($FAILS)"; exit 1; }
