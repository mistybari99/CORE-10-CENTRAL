#!/usr/bin/env bash
# Independent PG17 sessions, isolated fixture; never a hosted URL/database.
set -euo pipefail
[[ ${PGDATABASE:-} =~ ^core10_np03b_(ci|local) ]] || { echo NP03B_DISPOSABLE_ONLY; exit 1; }
cd "$(dirname "$0")/../.."
invoice_race_db="${PGDATABASE}_invoice_race"
createdb "$invoice_race_db"
export PGDATABASE="$invoice_race_db"
invoice_tmp=$(mktemp -d)
trap 'rm -rf "$invoice_tmp"; dropdb "$invoice_race_db"' EXIT
internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 -f tests/np03b/fixtures.sql >/dev/null
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic invoice race','inv_race_order_on');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,0,'Synthetic invoice race','inv_race_confirm_on');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic invoice race','inv_race_draft_on');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_validate',true,0::smallint,'{}',NULL,false,0,'Synthetic invoice race','inv_race_validate_on');
CREATE TABLE core10.np03b_invoice_race_sources(n integer PRIMARY KEY,order_id bigint,version bigint);
DO $$ DECLARE r jsonb; x integer; BEGIN
 FOR x IN 1..2 LOOP
  r:=core10.save_sales_order_v1(101,1001,NULL,0,'{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}','inv_race_source_'||x);
  r:=core10.transition_sales_order_v1(101,1001,(r->>'order_id')::bigint,'confirm',1,NULL,'inv_race_confirm_'||x);
  INSERT INTO core10.np03b_invoice_race_sources VALUES(x,(r->>'order_id')::bigint,(r->>'version')::bigint);
 END LOOP;
END $$;
CREATE FUNCTION core10.np03b_invoice_race(op text,k text,expected bigint,source integer DEFAULT 1,
 who text DEFAULT '11111111-1111-4111-8111-111111111111') RETURNS text LANGUAGE plpgsql AS $$
DECLARE o core10.np03b_invoice_race_sources%ROWTYPE; i bigint;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',who,true);
 SELECT * INTO STRICT o FROM core10.np03b_invoice_race_sources WHERE n=source;
 SELECT id INTO i FROM core10.sales_invoice_drafts_v1 WHERE source_order_id=o.order_id;
 IF op='create' THEN
  PERFORM core10.save_sales_invoice_draft_v1(101,1001,NULL,0,o.order_id,o.version,NULL,'race memo',k);
 ELSIF op='edit' THEN
  PERFORM core10.save_sales_invoice_draft_v1(101,1001,i,expected,o.order_id,o.version,'[{"order_line_no":1,"quantity":2}]',k,k);
 ELSIF op='validate' THEN PERFORM core10.validate_sales_invoice_draft_v1(101,1001,i,expected,NULL,k);
 END IF;
 RETURN 'ok';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM;
END $$;
SQL
wait_holder(){
 for _ in $(seq 1 80); do
  if [[ $(psql -X -At -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid WHERE a.application_name='np03b_invoice_holder' AND l.locktype='advisory' AND l.granted") -ge 1 ]]; then return; fi
  sleep .05
 done
 echo INVOICE_HOLDER_NOT_READY >&2; exit 1
}
pair(){
 local left_query="$1" right_query="$2"
 psql -X -q -v ON_ERROR_STOP=1 >"$invoice_tmp/holder" <<'SQL' &
BEGIN;
SET application_name='np03b_invoice_holder';
SELECT pg_advisory_xact_lock(6840304);
SELECT pg_sleep(2);
COMMIT;
SQL
 local holder=$!
 wait_holder
 psql -X -At -v ON_ERROR_STOP=1 -c "BEGIN; SELECT pg_advisory_xact_lock_shared(6840304); $left_query; COMMIT;" >"$invoice_tmp/a" & local left=$!
 psql -X -At -v ON_ERROR_STOP=1 -c "BEGIN; SELECT pg_advisory_xact_lock_shared(6840304); $right_query; COMMIT;" >"$invoice_tmp/b" & local right=$!
 wait "$holder"; wait "$left"; wait "$right"
 # Remove transaction tags and the void shared-lock result, preserving errors.
 sed -i '/^BEGIN$/d;/^COMMIT$/d;/^$/d' "$invoice_tmp/a" "$invoice_tmp/b"
}
pair "SELECT core10.np03b_invoice_race('create','inv_same_key',0)" "SELECT core10.np03b_invoice_race('create','inv_same_key',0)"
[[ $(cat "$invoice_tmp/a") = ok && $(cat "$invoice_tmp/b") = ok ]]
[[ $(psql -X -At -c "SELECT count(*) FROM core10.sales_invoice_commands_v1") = 1 ]]
[[ $(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE source_domain='sales_invoice'") = 1 ]]
pair "SELECT core10.np03b_invoice_race('create','inv_unique_key_a',0,2)" "SELECT core10.np03b_invoice_race('create','inv_unique_key_b',0,2)"
[[ $(cat "$invoice_tmp/a" "$invoice_tmp/b" | LC_ALL=C sort | tr '\n' ' ') = 'SALES_INVOICE_DUPLICATE_ORDER ok ' ]]
pair "SELECT core10.np03b_invoice_race('edit','inv_edit_a',1)" "SELECT core10.np03b_invoice_race('edit','inv_edit_b',1)"
[[ $(cat "$invoice_tmp/a" "$invoice_tmp/b" | LC_ALL=C sort | tr '\n' ' ') = 'SALES_INVOICE_STALE_VERSION ok ' ]]
pair "SELECT core10.np03b_invoice_race('validate','inv_validate_a',2)" "SELECT core10.np03b_invoice_race('validate','inv_validate_b',2)"
[[ $(cat "$invoice_tmp/a" "$invoice_tmp/b" | LC_ALL=C sort | tr '\n' ' ') = 'SALES_INVOICE_STALE_VERSION ok ' ]]
# A scope-mismatched ID must be refused BEFORE touching the held source/invoice.
locked_order=$(psql -X -At -c 'SELECT order_id FROM core10.np03b_invoice_race_sources WHERE n=1')
locked_invoice=$(psql -X -At -c "SELECT id FROM core10.sales_invoice_drafts_v1 WHERE source_order_id=$locked_order")
psql -X -q -v ON_ERROR_STOP=1 >"$invoice_tmp/holder" <<SQL &
BEGIN;
SET application_name='np03b_invoice_holder';
SELECT pg_advisory_xact_lock(6840304);
SELECT id FROM core10.sales_orders_v1 WHERE id=$locked_order FOR UPDATE;
SELECT id FROM core10.sales_invoice_drafts_v1 WHERE id=$locked_invoice FOR UPDATE;
SELECT pg_sleep(2);
COMMIT;
SQL
holder=$!
wait_holder
for _ in $(seq 1 80); do
 [[ $(psql -X -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='np03b_invoice_holder' AND wait_event='PgSleep'") = 1 ]] && break
 sleep .025
done
[[ $(psql -X -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='np03b_invoice_holder' AND wait_event='PgSleep'") = 1 ]]
psql -X -q -v ON_ERROR_STOP=1 >"$invoice_tmp/foreign" <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL lock_timeout='300ms';
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO \$\$ BEGIN
 BEGIN PERFORM core10.save_sales_invoice_draft_v1(102,1003,NULL,0,$locked_order,2,NULL,'','inv_foreign_locked_order');
 RAISE EXCEPTION 'FOREIGN_LOCKED_SOURCE_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='SALES_INVOICE_ORDER_NOT_FOUND' THEN NULL; ELSE RAISE; END IF; END;
 BEGIN PERFORM core10.validate_sales_invoice_draft_v1(102,1003,$locked_invoice,3,NULL,'inv_foreign_locked_invoice');
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='SALES_INVOICE_NOT_FOUND' THEN RETURN; ELSE RAISE; END IF; END;
 RAISE EXCEPTION 'FOREIGN_LOCKED_INVOICE_ALLOWED';
END \$\$;
COMMIT;
SQL
wait "$holder"
# Live Control changes commit while each writer is blocked after initial Auth.
for op in edit validate; do
 feature=sales.invoice_draft
 [[ "$op" != validate ]] || feature=sales.invoice_validate
 key="inv_wait_${op}"
 psql -X -q -v ON_ERROR_STOP=1 >"$invoice_tmp/holder" <<SQL &
BEGIN;
SET application_name='np03b_invoice_holder';
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT pg_advisory_xact_lock(hashtextextended('sales-invoice-key:101:$key',0));
SELECT core10.control_set_v1(101,NULL,'$feature',false,0::smallint,'{}',NULL,false,1,'Disable during invoice wait','${key}_off');
SELECT pg_sleep(2);
COMMIT;
SQL
 holder=$!
 wait_holder
 psql -X -At -v ON_ERROR_STOP=1 -c "SELECT core10.np03b_invoice_race('$op','$key',3)" >"$invoice_tmp/disabled"
 wait "$holder"
 [[ $(cat "$invoice_tmp/disabled") = "CONTROL_DISABLED:$feature" ]]
 psql -X -q -v ON_ERROR_STOP=1 -c "SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false); SELECT core10.control_set_v1(101,NULL,'$feature',true,0::smallint,'{}',NULL,false,2,'Restore synthetic invoice race','${key}_restore');" >/dev/null
done
# Membership revocation after the same wait must refuse mutation before replay.
psql -X -q -v ON_ERROR_STOP=1 >"$invoice_tmp/holder" <<'SQL' &
BEGIN;
SET application_name='np03b_invoice_holder';
SELECT pg_advisory_xact_lock(hashtextextended('sales-invoice-key:101:inv_wait_revoked',0));
UPDATE core10.business_members SET active=false WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222';
SELECT pg_sleep(2);
COMMIT;
SQL
holder=$!
wait_holder
psql -X -At -v ON_ERROR_STOP=1 -c "SELECT core10.np03b_invoice_race('edit','inv_wait_revoked',3,1,'22222222-2222-4222-8222-222222222222')" >"$invoice_tmp/revoked"
wait "$holder"
[[ $(cat "$invoice_tmp/revoked") = SALES_SCOPE_DENIED ]]
[[ $(psql -X -At -c 'SELECT count(*) FROM core10.sales_invoice_commands_v1') = 4 ]]
[[ $(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE source_domain='sales_invoice'") = 4 ]]
# Exact pack rollback, atomic failure: higher0401 must not hide the0304 guard.
if psql -X -1 -v ON_ERROR_STOP=1 -f internal/migrations/0304_np03b_draft_invoices.down.sql >"$invoice_tmp/rollback" 2>&1; then
 echo INVOICE_HISTORY_ROLLBACK_ALLOWED >&2; exit 1
fi
grep -F 'SALES_INVOICE_ROLLBACK_HAS_HISTORY' "$invoice_tmp/rollback" >/dev/null
[[ $(psql -X -At -c 'SELECT count(*) FROM core10.sales_invoice_drafts_v1') = 2 ]]
[[ $(psql -X -At -c "SELECT count(*) FROM core10.schema_migrations WHERE version=304") = 1 ]]
echo NP03B_INVOICE_TWO_SESSION_REPLAY_SOURCE_UNIQUENESS_CAS_VALIDATION_LIVE_CONTROL_REVOKE_ROLLBACK_OK
