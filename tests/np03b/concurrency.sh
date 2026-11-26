#!/usr/bin/env bash
# Two independent PG sessions; disposable DB only, never a hosted URL.
set -euo pipefail
[[ ${PGDATABASE:-} =~ ^core10_np03b_(ci|local) ]] || { echo NP03B_DISPOSABLE_ONLY; exit 1; }
cd "$(dirname "$0")/../.."
race_db="${PGDATABASE}_race"
createdb "$race_db"
trap 'dropdb "$race_db"' EXIT
export PGDATABASE="$race_db"
bash internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 -f tests/np03b/fixtures.sql >/dev/null
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic race test','sales_race_enable');
CREATE FUNCTION core10.np03b_race_doc() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":1,"unit_price":300,"discount_percent":0,"tax_percent":0}]}'::jsonb $$;
CREATE FUNCTION core10.np03b_race_save(k text, amendment boolean) RETURNS text LANGUAGE plpgsql AS $$
DECLARE o bigint; BEGIN
 PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
 IF amendment THEN SELECT id INTO STRICT o FROM core10.sales_orders_v1; END IF;
 PERFORM core10.save_sales_order_v1(101,1001,o,CASE WHEN amendment THEN 1 ELSE 0 END,core10.np03b_race_doc(),k);
 RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;
SQL
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"; dropdb "$race_db"' EXIT
psql -X -At -v ON_ERROR_STOP=1 -c "select core10.np03b_race_save('race_create_01',false)" >"$task_tmp/a" & first=$!
psql -X -At -v ON_ERROR_STOP=1 -c "select core10.np03b_race_save('race_create_01',false)" >"$task_tmp/b" & second=$!
wait "$first"; wait "$second"
[[ $(cat "$task_tmp/a") = ok && $(cat "$task_tmp/b") = ok ]]
[[ $(psql -X -At -c 'select count(*) from core10.sales_orders_v1') = 1 ]]
[[ $(psql -X -At -c "select count(*) from core10.canonical_audit_events_v1 where source_domain='sales'") = 1 ]]
psql -X -At -v ON_ERROR_STOP=1 -c "select core10.np03b_race_save('race_amend_a',true)" >"$task_tmp/a" & first=$!
psql -X -At -v ON_ERROR_STOP=1 -c "select core10.np03b_race_save('race_amend_b',true)" >"$task_tmp/b" & second=$!
wait "$first"; wait "$second"
[[ $(cat "$task_tmp/a" "$task_tmp/b" | LC_ALL=C sort | tr '\n' ' ') = 'SALES_STALE_VERSION ok ' ]]
[[ $(psql -X -At -c 'select version from core10.sales_orders_v1') = 2 ]]
[[ $(psql -X -At -c 'select count(*) from core10.sales_order_commands_v1') = 2 ]]
# Hold the request lock while disabling Control in an uncommitted transaction.
# The blocked writer initially sees enabled, then must recheck after lock release.
psql -X -q -v ON_ERROR_STOP=1 >"$task_tmp/holder" <<'SQL' &
BEGIN;
SET application_name='np03b_disabled_lock_holder';
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT pg_advisory_xact_lock(hashtextextended('sales-key:101:race_disabled_01',0));
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',false,0::smallint,'{}',NULL,false,1,'Disable while writer waits','sales_disable_wait');
SELECT pg_sleep(3);
COMMIT;
SQL
holder=$!
ready=0
for _ in $(seq 1 50); do
 if [[ $(psql -X -At -c "select count(*) from pg_locks l join pg_stat_activity a on a.pid=l.pid where a.application_name='np03b_disabled_lock_holder' and l.locktype='advisory' and l.granted") -ge 1 ]]; then ready=1; break; fi
 sleep .05
done
[[ "$ready" = 1 ]]
psql -X -At -v ON_ERROR_STOP=1 -c "select core10.np03b_race_save('race_disabled_01',false)" >"$task_tmp/disabled"
wait "$holder"
[[ $(cat "$task_tmp/disabled") = 'CONTROL_DISABLED:sales.order_draft' ]]
[[ $(psql -X -At -c 'select count(*) from core10.sales_orders_v1') = 1 ]]
echo NP03B_TWO_SESSION_REPLAY_AMENDMENT_AND_WAIT_DISABLED_OK
