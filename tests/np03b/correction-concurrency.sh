#!/usr/bin/env bash
# Disposable-only independent sessions. Security failures stay nonzero.
set -euo pipefail
[[ ${PGDATABASE:-} =~ ^core10_np03b_(ci|local) ]] || { echo NP03B_DISPOSABLE_ONLY; exit 2; }
cd "$(dirname "$0")/../.."
correction_db="${PGDATABASE}_correction_race"
createdb "$correction_db"
export PGDATABASE="$correction_db"
correction_tmp=$(mktemp -d)
trap 'rm -rf "$correction_tmp"; dropdb "$correction_db"' EXIT
internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 -f tests/np03b/fixtures.sql >/dev/null
psql -X -q -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic correction race','correction_race_draft');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,0,'Synthetic correction race','correction_race_transition');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic correction race','correction_race_invoice');
CREATE TABLE core10.np03b_correction_sources(n integer,o bigint);
DO $$ DECLARE r jsonb; n integer; BEGIN FOR n IN 1..3 LOOP
 r:=core10.save_sales_order_v1(101,1001,NULL,0,'{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}','correction_race_save_'||n);
 INSERT INTO core10.np03b_correction_sources VALUES(n,(r->>'order_id')::bigint);
 IF n=3 THEN PERFORM core10.transition_sales_order_v1(101,1001,(r->>'order_id')::bigint,'confirm',1,NULL,'correction_race_confirm_3'); END IF;
 END LOOP; END $$;
CREATE SCHEMA np03b_correction_race;
GRANT USAGE ON SCHEMA np03b_correction_race TO authenticated;
CREATE FUNCTION np03b_correction_race.attempt(q text) RETURNS text LANGUAGE plpgsql AS $$ BEGIN
 EXECUTE q; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;
GRANT EXECUTE ON FUNCTION np03b_correction_race.attempt(text) TO authenticated;
SQL
wait_for(){
 local query="$1" expected="$2"
 for _ in $(seq 1 100); do
  [[ $(psql -X -At -c "$query") = "$expected" ]] && return
  sleep .05
 done
 echo CORRECTION_BARRIER_TIMEOUT >&2; exit 1
}
race(){
 local held="$1" left="$2" right="${3:-}" count=1
 mkfifo "$correction_tmp/release"
 { printf '%s\n' "BEGIN; SET application_name='np03b_correction_holder'; $held;"; read -r < "$correction_tmp/release"; printf 'COMMIT;\n'; } |
  psql -X -q -v ON_ERROR_STOP=1 >"$correction_tmp/holder" & local holder=$!
 wait_for "SELECT count(*) FROM pg_stat_activity WHERE application_name='np03b_correction_holder' AND state='idle in transaction'" 1
 PGAPPNAME=np03b_correction_left psql -X -qAt -v ON_ERROR_STOP=1 -c "SET ROLE authenticated; DO \$\$ BEGIN PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false); END \$\$; $left" >"$correction_tmp/left" & local a=$!
 if [[ -n "$right" ]]; then
  count=2
  PGAPPNAME=np03b_correction_right psql -X -qAt -v ON_ERROR_STOP=1 -c "SET ROLE authenticated; DO \$\$ BEGIN PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false); END \$\$; $right" >"$correction_tmp/right" & local b=$!
 fi
 wait_for "SELECT count(*) FROM pg_stat_activity WHERE application_name IN('np03b_correction_left','np03b_correction_right') AND wait_event_type='Lock'" "$count"
 printf 'release\n' > "$correction_tmp/release"
 wait "$holder"; wait "$a"; if [[ -n "$right" ]]; then wait "$b"; fi
 rm "$correction_tmp/release"
}
o1=$(psql -X -At -c 'SELECT o FROM core10.np03b_correction_sources WHERE n=1')
o2=$(psql -X -At -c 'SELECT o FROM core10.np03b_correction_sources WHERE n=2')
o3=$(psql -X -At -c 'SELECT o FROM core10.np03b_correction_sources WHERE n=3')
correction_doc='{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}'
race "SELECT id FROM core10.sales_orders_v1 WHERE id=$o1 FOR UPDATE" \
 "SELECT np03b_correction_race.attempt(\$q\$SELECT core10.transition_sales_order_v1(101,1001,$o1,'confirm',1,NULL,'correction_confirm_a')\$q\$)" \
 "SELECT np03b_correction_race.attempt(\$q\$SELECT core10.transition_sales_order_v1(101,1001,$o1,'confirm',1,NULL,'correction_confirm_b')\$q\$)"
[[ $(cat "$correction_tmp/left" "$correction_tmp/right" | LC_ALL=C sort | tr '\n' ' ') = 'SALES_STALE_VERSION ok ' ]]
echo CORRECTION_COMPETING_CONFIRMATION_CAS_PASS
race "SELECT id FROM core10.sales_orders_v1 WHERE id=$o2 FOR UPDATE" \
 "SELECT np03b_correction_race.attempt(\$q\$SELECT core10.transition_sales_order_v1(101,1001,$o2,'confirm',1,NULL,'correction_confirm_edit')\$q\$)" \
 "SELECT np03b_correction_race.attempt(\$q\$SELECT core10.save_sales_order_v1(101,1001,$o2,1,'$correction_doc'::jsonb,'correction_edit_confirm')\$q\$)"
[[ $(cat "$correction_tmp/left" "$correction_tmp/right" | LC_ALL=C sort | tr '\n' ' ') = 'SALES_STALE_VERSION ok ' ]]
echo CORRECTION_AMENDMENT_VS_CONFIRMATION_CAS_PASS
race "SELECT id FROM core10.sales_orders_v1 WHERE id=$o3 FOR UPDATE; UPDATE core10.sales_orders_v1 SET document=jsonb_set(document,'{lines,0,quantity}','1'),total=300 WHERE id=$o3; UPDATE core10.sales_order_lines_v1 SET quantity=1,line_total=300 WHERE order_id=$o3" \
 "SELECT np03b_correction_race.attempt(\$q\$SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,$o3,2,NULL,'','correction_tamper_wait')\$q\$)"
result=$(cat "$correction_tmp/left")
if [[ "$result" = ok ]]; then
 echo CORRECTION_SOURCE_TAMPER_VS_INVOICE_FAIL_ACCEPTED >&2; exit 1
fi
[[ "$result" =~ SALES_.*(SOURCE|AUDIT|IMMUTABLE) ]]
echo CORRECTION_SOURCE_TAMPER_VS_INVOICE_DENIED_PASS
