\set ON_ERROR_STOP on
-- Security acceptance, NOT a baseline-green test. Until the blocked SQL fixes
-- are authorized this reports failures and exits nonzero. All probes roll back.
BEGIN;
\ir fixtures.sql
CREATE SCHEMA np03b_correction;
GRANT USAGE ON SCHEMA np03b_correction TO authenticated;
CREATE TABLE np03b_correction.results(label text PRIMARY KEY,secure boolean,observed text);
GRANT INSERT,SELECT ON np03b_correction.results TO authenticated;
CREATE FUNCTION np03b_correction.doc() RETURNS jsonb LANGUAGE sql AS $$ SELECT
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"variant_id":7301,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}'::jsonb $$;
CREATE FUNCTION np03b_correction.control(f text,s integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v integer; BEGIN
 SELECT (x->>'version')::integer INTO STRICT v FROM jsonb_array_elements(core10.control_read_v1(101)) x WHERE x->>'feature_key'=f;
 PERFORM core10.control_set_v1(101,NULL,f,true,s::smallint,'{}',NULL,false,v,'Synthetic security acceptance',replace(f,'.','_')||'_'||v);
END $$;
CREATE FUNCTION np03b_correction.order_id(k text,confirm boolean DEFAULT true) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE r jsonb; o bigint; BEGIN
 r:=core10.save_sales_order_v1(101,1001,NULL,0,np03b_correction.doc(),k||'_save');o:=(r->>'order_id')::bigint;
 IF confirm THEN PERFORM core10.transition_sales_order_v1(101,1001,o,'confirm',1,NULL,k||'_confirm'); END IF;
 RETURN o;
END $$;
-- Inner exception rolls back even accepted writes, including receipt/audit/override.
CREATE FUNCTION np03b_correction.denies(label text,q text,expected text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual text; BEGIN
 BEGIN EXECUTE q; RAISE EXCEPTION 'PROBE_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN actual:=SQLERRM; END;
 INSERT INTO np03b_correction.results VALUES(label,actual~expected,actual);
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np03b_correction TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT np03b_correction.control('sales.order_draft',0);
SELECT np03b_correction.control('sales.order_transition',0);
SELECT np03b_correction.control('sales.invoice_draft',0);
SELECT np03b_correction.control('sales.invoice_validate',0);
SELECT np03b_correction.order_id('correction_source') AS source \gset
SELECT np03b_correction.order_id('correction_other') AS other \gset
SELECT np03b_correction.order_id('correction_draft',false) AS draft \gset
SELECT np03b_correction.denies('P1-02 order zero-stage fabricated approval',
 format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',1,999999,''correction_inject_order'')',:draft),'SALES_.*APPROVAL');
RESET ROLE;
-- Privileged DML, without disabling triggers or using session_replication_role.
SELECT np03b_correction.denies('P1-01 confirmed header UPDATE',
 format('UPDATE core10.sales_orders_v1 SET customer_id=7002 WHERE id=%s',:source),'SALES_.*IMMUTABLE');
SELECT np03b_correction.denies('P1-01 confirmed line UPDATE',
 format('UPDATE core10.sales_order_lines_v1 SET quantity=3 WHERE order_id=%s',:source),'SALES_.*IMMUTABLE');
SELECT np03b_correction.denies('P1-01 confirmed line DELETE',
 format('DELETE FROM core10.sales_order_lines_v1 WHERE order_id=%s',:source),'SALES_.*IMMUTABLE');
SELECT np03b_correction.denies('P1-01 confirmed line INSERT',format(
 'INSERT INTO core10.sales_order_lines_v1 SELECT order_id,tenant_id,business_id,site_id,2,item_id,variant_id,uom_id,quantity,unit_price,discount_percent,tax_percent,line_total FROM core10.sales_order_lines_v1 WHERE order_id=%s',:source),'SALES_.*IMMUTABLE');
SELECT np03b_correction.denies('P2-02 referenced customer maintenance DELETE',
 'DELETE FROM core10.master_parties_v1 WHERE id=7001','foreign key constraint|SALES_.*REFERENCE');
-- The corrected source is now immutable at the actual mutation boundary.
-- Privileged DML is rejected BEFORE invoice creation; do not attempt to change
-- the source and then pretend the invoice was correctly denied after corruption.
SELECT np03b_correction.denies('P1-01 tampered source before invoice',
 format('UPDATE core10.sales_orders_v1 SET document=jsonb_set(document,%L,%L),total=300 WHERE id=%s',
 '{lines,0,quantity}','1',:source),'SALES_.*(SOURCE|AUDIT|IMMUTABLE)');
SELECT np03b_correction.denies('P1-01 mismatched real confirmation Audit',
 format('UPDATE core10.sales_order_commands_v1 SET audit_event_id=(SELECT audit_event_id FROM core10.sales_order_commands_v1 WHERE order_id=%s AND receipt->>%L=%L) WHERE order_id=%s AND receipt->>%L=%L',
 :other,'status','confirmed',:source,'status','confirmed'),'SALES_.*(SOURCE|AUDIT|IMMUTABLE)');

SET LOCAL ROLE authenticated;
SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,:source,2,NULL,'Synthetic','correction_invoice') AS invoice \gset
SELECT np03b_correction.denies('P1-02 invoice zero-stage fabricated approval',format(
 'SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,1,999999,''correction_inject_invoice'')',(:'invoice'::jsonb->>'invoice_id')::bigint),'SALES_.*APPROVAL');
RESET ROLE;
SELECT np03b_correction.denies('P1-01 changed source line before validation',
 format('UPDATE core10.sales_order_lines_v1 SET quantity=3 WHERE order_id=%s',:source),
 'SALES_.*(SOURCE|AUDIT|IMMUTABLE)');
SET LOCAL ROLE authenticated;
-- A legitimate, unchanged confirmed Sales snapshot still validates.
SELECT core10.validate_sales_invoice_draft_v1(
 101,1001,(:'invoice'::jsonb->>'invoice_id')::bigint,1,NULL,
 'correction_valid_original');

SET LOCAL ROLE authenticated;
SELECT core10.publish_approval_policy_v1(101,'sales','confirm',1440,'correction_confirm_policy');
SELECT core10.submit_typed_approval_v1(101,'sales','confirm','sales-order:'||:draft,1,
 jsonb_build_object('order_id',:draft,'site_id',1001,'version',1,'document',np03b_correction.doc(),'total',600,'action','confirm','required_stages',1),
 'correction_confirm_request') AS approval \gset
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
SELECT core10.decide_approval(:approval,'approve','correction_confirm_decision');
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT set_config('np03b.correction.draft',:'draft',true),set_config('np03b.correction.approval',:'approval',true);
DO $$ DECLARE s integer; o bigint:=current_setting('np03b.correction.draft')::bigint;
 a bigint:=current_setting('np03b.correction.approval')::bigint;
BEGIN
 FOR s IN 1..5 LOOP
  PERFORM np03b_correction.control('sales.order_transition',s);
  PERFORM np03b_correction.denies('P2-01 cancellation stage '||s||' missing approval',
   format('SELECT core10.transition_sales_order_v1(101,1001,%s,''cancel'',1,NULL,''correction_cancel_missing_%s'')',o,s),'SALES_APPROVAL_REQUIRED|SALES_.*CANCEL');
  PERFORM np03b_correction.denies('P2-01 cancellation stage '||s||' confirmation approval',
   format('SELECT core10.transition_sales_order_v1(101,1001,%s,''cancel'',1,%s,''correction_cancel_wrong_%s'')',o,a,s),'approval_stale_or_payload_changed|SALES_.*CANCEL');
 END LOOP;
END $$;
SELECT np03b_correction.control('sales.order_transition',0);
-- Zero-stage cancellation of an uncommitted draft remains a legitimate action.
SELECT np03b_correction.denies('P2-01 stage zero draft cancellation accepted',format(
 'SELECT core10.transition_sales_order_v1(101,1001,%s,''cancel'',1,NULL,''correction_cancel_zero'')',:draft),'^PROBE_ACCEPTED$');
RESET ROLE;
-- A canonical Audit integrity PASS alone does not prove source semantic binding.
SELECT core10.verify_canonical_audit_v1(101);
DO $$ BEGIN
 IF EXISTS(SELECT FROM core10.sales_order_commands_v1 WHERE request_key='correction_inject_order')
 OR EXISTS(SELECT FROM core10.sales_invoice_commands_v1 WHERE request_key IN('correction_inject_invoice','correction_tampered_create','correction_wrong_audit','correction_line_validate'))
 OR EXISTS(SELECT FROM core10.canonical_audit_events_v1 WHERE request_key IN('sales:correction_inject_order','sales-invoice:correction_inject_invoice'))
 THEN RAISE EXCEPTION 'PROBE_ROLLBACK_LEAK'; END IF;
END $$;
TABLE np03b_correction.results;
DO $$ DECLARE n integer; BEGIN
 SELECT count(*) INTO n FROM np03b_correction.results WHERE NOT secure;
 IF n>0 THEN RAISE EXCEPTION 'SALES_CORRECTION_ACCEPTANCE_FAIL: % unresolved security cases; this is NOT a passing security result',n; END IF;
END $$;
ROLLBACK;
