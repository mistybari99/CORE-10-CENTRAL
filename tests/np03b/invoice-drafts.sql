\set ON_ERROR_STOP on
-- Disposable PG17 only. Canonical fixture Master, Auth, Control, Approval and
-- Sales RPCs are exercised; no synthetic replacement engine or fake status.
BEGIN;
\ir fixtures.sql
CREATE SCHEMA np03b_invoice_test;
GRANT USAGE ON SCHEMA np03b_invoice_test TO authenticated,anon;
CREATE FUNCTION np03b_invoice_test.ok(v boolean,m text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS NOT TRUE THEN RAISE EXCEPTION 'INVOICE_TEST_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION np03b_invoice_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE e||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'INVOICE_TEST_WRONG_ERROR expected:% got:%',e,SQLERRM;
 END;
 RAISE EXCEPTION 'INVOICE_TEST_NO_ERROR:%',e;
END $$;
CREATE FUNCTION np03b_invoice_test.actor(u text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',u)::text,true),
        set_config('request.jwt.claim.sub',coalesce(u,''),true)
$$;
CREATE FUNCTION np03b_invoice_test.doc() RETURNS jsonb LANGUAGE sql AS $$ SELECT
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[
 {"item_id":8101,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0},
 {"item_id":8102,"uom_id":7201,"quantity":1,"unit_price":420,"discount_percent":0,"tax_percent":0}]}'::jsonb $$;
CREATE FUNCTION np03b_invoice_test.control(feature text,en boolean,stages smallint,params jsonb,k text)
RETURNS void LANGUAGE plpgsql AS $$ DECLARE v integer; BEGIN
 SELECT (x->>'version')::integer INTO STRICT v FROM jsonb_array_elements(core10.control_read_v1(101)) x WHERE x->>'feature_key'=feature;
 PERFORM core10.control_set_v1(101,NULL,feature,en,stages,params,NULL,false,v,'Disposable synthetic invoice test',k);
END $$;
CREATE FUNCTION np03b_invoice_test.confirmed(k text,d jsonb DEFAULT np03b_invoice_test.doc())
RETURNS bigint LANGUAGE plpgsql AS $$ DECLARE r jsonb; o bigint; BEGIN
 r:=core10.save_sales_order_v1(101,1001,NULL,0,d,k||'_save');o:=(r->>'order_id')::bigint;
 PERFORM core10.transition_sales_order_v1(101,1001,o,'confirm',1,NULL,k||'_confirm');RETURN o;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np03b_invoice_test TO authenticated,anon;
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.actor('11111111-1111-4111-8111-111111111111');
SELECT np03b_invoice_test.control('sales.order_draft',true,0::smallint,'{}','inv_orders_enabled');
SELECT np03b_invoice_test.control('sales.order_transition',true,0::smallint,'{}','inv_order_transition');
SELECT np03b_invoice_test.confirmed('inv_source_main') AS source_order \gset
SELECT set_config('np03b_inv.order',:'source_order',true);
-- Neither feature may bypass its disabled setting, even with a valid source.
SELECT np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,''Synthetic full draft'',''invoice_main_save'')',:'source_order'),'CONTROL_DISABLED:sales.invoice_draft');
SELECT np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{}','invoice_draft_enabled');
DO $$ DECLARE o bigint:=current_setting('np03b_inv.order')::bigint; r jsonb; invoice bigint; replay jsonb;
BEGIN
 r:=core10.save_sales_invoice_draft_v1(101,1001,NULL,0,o,2,NULL,'Synthetic full draft','invoice_main_save');invoice:=(r->>'invoice_id')::bigint;
 PERFORM set_config('np03b_inv.invoice',invoice::text,true);
 PERFORM np03b_invoice_test.ok(r->>'status'='draft' AND (r->>'version')::integer=1 AND r->>'validated'='false','create is an unvalidated draft');
 PERFORM np03b_invoice_test.ok((r->>'total')::numeric=1020 AND (r->>'source_order_id')::bigint=o AND (r->>'source_order_version')::bigint=2,'exact confirmed source and total');
 PERFORM np03b_invoice_test.ok(r->>'issued'='false' AND r->>'stock_posted'='false' AND r->>'financial_posted'='false','no issue, stock or accounting success');
 replay:=core10.save_sales_invoice_draft_v1(101,1001,NULL,0,o,2,NULL,'Synthetic full draft','invoice_main_save');
 PERFORM np03b_invoice_test.ok(replay=r,'exact create replay returns original receipt');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,''changed memo'',''invoice_main_save'')',o),'SALES_INVOICE_REPLAY_CONFLICT');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,''Duplicate source'',''invoice_duplicate_source'')',o),'SALES_INVOICE_DUPLICATE_ORDER');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,1,NULL,''invoice_validate_off'')',invoice),'CONTROL_DISABLED:sales.invoice_validate');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,NULL,''Update requires explicit quantities'',''invoice_null_update'')',invoice,o),'SALES_INVOICE_LINES_INVALID');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,0,%s,2,''[{"order_line_no":1,"quantity":2},{"order_line_no":2,"quantity":1}]'',''Stale editor'',''invoice_stale_update'')',invoice,o),'SALES_INVOICE_COMMAND_INVALID');
END $$;
DO $$ DECLARE r jsonb; i jsonb; o bigint:=current_setting('np03b_inv.order')::bigint;
BEGIN
 r:=core10.read_sales_invoice_drafts_v1(101,1001,current_setting('np03b_inv.invoice')::bigint);
 PERFORM np03b_invoice_test.ok(jsonb_array_length(r->'invoices')=1,'scoped invoice read');i:=r->'invoices'->0;
 PERFORM np03b_invoice_test.ok(i->'source_snapshot'->'document'=np03b_invoice_test.doc() AND i->'document'=np03b_invoice_test.doc(),'full immutable source snapshot and initial document');
 PERFORM np03b_invoice_test.ok((i->'source_snapshot'->>'order_id')::bigint=o AND jsonb_array_length(i->'lines')=2,'snapshot source and materialized lines');
 PERFORM np03b_invoice_test.ok(i->>'source_sha256'=encode(sha256(convert_to((i->'source_snapshot')::text,'UTF8')),'hex'),'source snapshot hash');
 PERFORM np03b_invoice_test.ok(r->'connections'->>'money'='NOT_CONNECTED' AND r->'connections'->>'stock'='NOT_CONNECTED' AND r->'connections'->>'issuance'='NOT_CONNECTED','honest disconnected postings and issuance');
 PERFORM np03b_invoice_test.ok(jsonb_array_length(core10.read_sales_invoice_drafts_v1(101,1002)->'invoices')=0,'other site does not expose invoice');
 PERFORM np03b_invoice_test.ok(jsonb_array_length(core10.read_sales_invoice_drafts_v1(102,1003)->'invoices')=0,'other business does not expose invoice');
 PERFORM np03b_invoice_test.expect('SELECT * FROM core10.sales_invoice_drafts_v1','permission denied');
 PERFORM np03b_invoice_test.expect('DELETE FROM core10.sales_invoice_draft_lines_v1','permission denied');
 PERFORM np03b_invoice_test.expect('DELETE FROM core10.sales_invoice_commands_v1','permission denied');
 PERFORM np03b_invoice_test.expect($q$SELECT core10._sales_invoice_document_v1('{}','[]','{}')$q$,'permission denied');
END $$;
-- Source lifecycle and immutable snapshot boundaries are actual API behaviour.
DO $$ DECLARE r jsonb; draft_order bigint; cancelled_order bigint; o bigint:=current_setting('np03b_inv.order')::bigint;
BEGIN
 r:=core10.save_sales_order_v1(101,1001,NULL,0,np03b_invoice_test.doc(),'invoice_source_draft');draft_order:=(r->>'order_id')::bigint;
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,1,NULL,'''',''invoice_unconfirmed'')',draft_order),'SALES_INVOICE_ORDER_NOT_CONFIRMED');
 r:=core10.save_sales_order_v1(101,1001,NULL,0,np03b_invoice_test.doc(),'invoice_source_cancelled');cancelled_order:=(r->>'order_id')::bigint;
 PERFORM core10.transition_sales_order_v1(101,1001,cancelled_order,'cancel',1,NULL,'invoice_cancel_source');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,'''',''invoice_cancelled_source'')',cancelled_order),'SALES_INVOICE_ORDER_NOT_CONFIRMED');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,1,NULL,'''',''invoice_old_source'')',o),'SALES_INVOICE_SOURCE_STALE');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1002,NULL,0,%s,2,NULL,'''',''invoice_wrong_source_site'')',o),'SALES_INVOICE_ORDER_NOT_FOUND');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(102,1003,NULL,0,%s,2,NULL,'''',''invoice_wrong_source_business'')',o),'SALES_INVOICE_ORDER_NOT_FOUND');
END $$;
-- Editing cannot inject prices, references, duplicate source lines or quantities
-- beyond the original confirmed order. Partial billing is explicitly Owner-set.
DO $$ DECLARE invoice bigint:=current_setting('np03b_inv.invoice')::bigint; o bigint:=current_setting('np03b_inv.order')::bigint; r jsonb;
BEGIN
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":1}]'','''',''invoice_partial_disabled'')',invoice,o),'SALES_INVOICE_PARTIAL_DISABLED');
 PERFORM np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{"allow_partial_quantities":true}','invoice_partial_enabled');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":3}]'','''',''invoice_over_source'')',invoice,o),'SALES_INVOICE_QUANTITY');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":0}]'','''',''invoice_zero_quantity'')',invoice,o),'SALES_INVOICE_QUANTITY');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":-1}]'','''',''invoice_negative_quantity'')',invoice,o),'SALES_INVOICE_QUANTITY');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":99,"quantity":1}]'','''',''invoice_unknown_source_line'')',invoice,o),'SALES_INVOICE_QUANTITY');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":1},{"order_line_no":1,"quantity":1}]'','''',''invoice_duplicate_lines'')',invoice,o),'SALES_INVOICE_QUANTITY');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":1,"unit_price":1}]'','''',''invoice_price_injection'')',invoice,o),'SALES_INVOICE_LINES_INVALID');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":"NaN"}]'','''',''invoice_nonfinite_quantity'')',invoice,o),'SALES_INVOICE_LINES_INVALID');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[]'','''',''invoice_empty_selection'')',invoice,o),'SALES_INVOICE_LINES_INVALID');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":1.5}]'','''',''invoice_uom_precision'')',invoice,o),'SALES_UOM_PRECISION');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":1}]'',repeat(''x'',501),''invoice_memo_limit'')',invoice,o),'SALES_INVOICE_MEMO_LIMIT');
 r:=core10.save_sales_invoice_draft_v1(101,1001,invoice,1,o,2,'[{"order_line_no":1,"quantity":1}]','Synthetic partial draft','invoice_partial_save');
 PERFORM np03b_invoice_test.ok((r->>'version')::integer=2 AND (r->>'total')::numeric=300 AND r->>'validated'='false','partial update uses fixed source unit price');
 PERFORM set_config('np03b_inv.version',r->>'version',true);
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,1,%s,2,''[{"order_line_no":1,"quantity":1}]'','''',''invoice_cas_stale'')',invoice,o),'SALES_INVOICE_STALE_VERSION');
END $$;
-- Validation remains a draft; Owner-required approval cannot be bypassed.
SELECT np03b_invoice_test.control('sales.invoice_validate',true,1::smallint,'{}','invoice_validation_enabled');
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,2,NULL,''invoice_approval_required'')',current_setting('np03b_inv.invoice')),'SALES_INVOICE_APPROVAL_REQUIRED');
SELECT np03b_invoice_test.control('sales.invoice_validate',true,0::smallint,'{}','invoice_validation_zero_stage');
DO $$ DECLARE invoice bigint:=current_setting('np03b_inv.invoice')::bigint; r jsonb;
BEGIN
 r:=core10.validate_sales_invoice_draft_v1(101,1001,invoice,2,NULL,'invoice_validate_zero');
 PERFORM np03b_invoice_test.ok((r->>'version')::integer=3 AND r->>'status'='draft' AND r->>'validated'='true','validated draft version advances');
 PERFORM np03b_invoice_test.ok(r->>'issued'='false' AND r->>'stock_posted'='false' AND r->>'financial_posted'='false','validation never issues or posts');
 PERFORM np03b_invoice_test.ok(r=core10.validate_sales_invoice_draft_v1(101,1001,invoice,2,NULL,'invoice_validate_zero'),'validation exact replay');
 PERFORM set_config('np03b_inv.version',r->>'version',true);
END $$;
-- Actual canonical one-stage approval is tied to the exact live invoice revision,
-- source hash, document, memo, amount and current Owner stage count.
DO $$ DECLARE invoice bigint:=current_setting('np03b_inv.invoice')::bigint; o bigint:=current_setting('np03b_inv.order')::bigint;
 r jsonb; p jsonb; a bigint; wrong bigint; stage_mismatch bigint;
BEGIN
 r:=core10.save_sales_invoice_draft_v1(101,1001,invoice,3,o,2,'[{"order_line_no":1,"quantity":1}]','New revision requires approval','invoice_edit_after_validation');
 PERFORM np03b_invoice_test.ok(r->>'validated'='false' AND (r->>'version')::integer=4,'editing clears old validation');
 PERFORM np03b_invoice_test.control('sales.invoice_validate',true,1::smallint,'{}','invoice_real_approval_stage');
 PERFORM core10.publish_approval_policy_v1(101,'sales','invoice_validate',1440,'invoice_approval_policy');
 r:=core10.read_sales_invoice_drafts_v1(101,1001,invoice);p:=r->'invoices'->0->'approval_payload';
 PERFORM np03b_invoice_test.ok((r->'validation_control'->>'stages')::integer=1 AND (p->>'version')::integer=4,'read provides exact current approval payload');
 a:=core10.submit_typed_approval_v1(101,'sales','invoice_validate','sales-invoice-draft:'||invoice,4,p,'invoice_approval_request');
 wrong:=core10.submit_typed_approval_v1(101,'sales','invoice_validate','sales-invoice-draft:wrong',4,p,'invoice_wrong_source_request');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,4,%s,''invoice_pending_approval'')',invoice,a),'approval_not_effective');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.decide_approval(%s,''approve'',''invoice_self_approval'')',a),'approval_not_authorized');
 PERFORM np03b_invoice_test.actor('22222222-2222-4222-8222-222222222222');
 PERFORM core10.decide_approval(a,'approve','invoice_checker_approval');
 PERFORM core10.decide_approval(wrong,'approve','invoice_wrong_checker_approval');
 PERFORM np03b_invoice_test.actor('11111111-1111-4111-8111-111111111111');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,4,%s,''invoice_wrong_approved_source'')',invoice,wrong),'approval_stale_or_payload_changed');
 PERFORM np03b_invoice_test.control('sales.invoice_validate',true,2::smallint,'{}','invoice_two_stage_requirement');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,4,%s,''invoice_changed_stage_hash'')',invoice,a),'approval_stale_or_payload_changed');
 r:=core10.read_sales_invoice_drafts_v1(101,1001,invoice);p:=r->'invoices'->0->'approval_payload';
 stage_mismatch:=core10.submit_typed_approval_v1(101,'sales','invoice_validate','sales-invoice-draft:'||invoice,4,p,'invoice_stage_mismatch_request');
 PERFORM np03b_invoice_test.actor('22222222-2222-4222-8222-222222222222');
 PERFORM core10.decide_approval(stage_mismatch,'approve','invoice_short_route_approval');
 PERFORM np03b_invoice_test.actor('11111111-1111-4111-8111-111111111111');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,4,%s,''invoice_short_route_denied'')',invoice,stage_mismatch),'SALES_INVOICE_APPROVAL_STAGES');
 PERFORM np03b_invoice_test.control('sales.invoice_validate',true,1::smallint,'{}','invoice_restore_one_stage');
 r:=core10.validate_sales_invoice_draft_v1(101,1001,invoice,4,a,'invoice_real_approval_validate');
 PERFORM np03b_invoice_test.ok(r->>'validated'='true' AND r->>'issued'='false' AND (r->>'version')::integer=5,'real source-bound approval validates without issuing');
 PERFORM set_config('np03b_inv.version',r->>'version',true);
 PERFORM np03b_invoice_test.control('sales.invoice_validate',true,0::smallint,'{}','invoice_restore_zero_stage');
END $$;
-- Current Master must still approve the source snapshot; a changed price or
-- currency cannot be silently treated as zero or accepted as a historical post.
RESET ROLE;
UPDATE core10.master_price_list_items_v1 SET unit_price=301 WHERE price_list_id=7101 AND item_id=8101 AND variant_id IS NULL;
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,%s,NULL,''invoice_master_changed'')',current_setting('np03b_inv.invoice'),current_setting('np03b_inv.version')),'SALES_MASTER_REJECTED');
RESET ROLE;
UPDATE core10.master_price_list_items_v1 SET unit_price=300 WHERE price_list_id=7101 AND item_id=8101 AND variant_id IS NULL;
UPDATE core10.master_price_lists_v1 SET currency='USD' WHERE id=7101;
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,%s,NULL,''invoice_currency_changed'')',current_setting('np03b_inv.invoice'),current_setting('np03b_inv.version')),'SALES_CURRENCY_MISMATCH');
RESET ROLE;
UPDATE core10.master_price_lists_v1 SET currency='BDT' WHERE id=7101;
SET LOCAL ROLE authenticated;
-- A current disabled Control denies even successful historical request retries.
SELECT np03b_invoice_test.control('sales.invoice_validate',false,0::smallint,'{}','invoice_validation_paused');
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,2,NULL,''invoice_validate_zero'')',current_setting('np03b_inv.invoice')),'CONTROL_DISABLED:sales.invoice_validate');
SELECT np03b_invoice_test.control('sales.invoice_validate',true,0::smallint,'{}','invoice_validation_resumed');
SELECT np03b_invoice_test.control('sales.invoice_draft',false,0::smallint,'{}','invoice_draft_paused');
SELECT np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,''Synthetic full draft'',''invoice_main_save'')',current_setting('np03b_inv.order')),'CONTROL_DISABLED:sales.invoice_draft');
SELECT np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{"allow_partial_quantities":true}','invoice_draft_resumed');
-- Invoice rounding is a recorded source contract, not an opportunistic reprice.
SELECT np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{"allow_partial_quantities":true,"money_scale":3}','invoice_rounding_changed');
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,5,NULL,''invoice_changed_rounding'')',current_setting('np03b_inv.invoice')),'SALES_INVOICE_ROUNDING_CHANGED');
SELECT np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{"allow_partial_quantities":true}','invoice_rounding_restored');
RESET ROLE;
-- Even a maintenance principal cannot rewrite the original source snapshot or
-- fixed currency. The trigger rejects, rather than recomputing a history hash.
SELECT np03b_invoice_test.expect(format('UPDATE core10.sales_invoice_drafts_v1 SET currency=''USD'' WHERE id=%s',current_setting('np03b_inv.invoice')),'SALES_INVOICE_SOURCE_IMMUTABLE');
SELECT np03b_invoice_test.expect(format('UPDATE core10.sales_invoice_drafts_v1 SET source_snapshot=jsonb_set(source_snapshot,''{total}'',''0'') WHERE id=%s',current_setting('np03b_inv.invoice')),'SALES_INVOICE_SOURCE_IMMUTABLE');
UPDATE core10.master_price_list_items_v1 SET unit_price=300.1234 WHERE price_list_id=7101 AND item_id=8101 AND variant_id IS NULL;
SET LOCAL ROLE authenticated;
DO $$ DECLARE o bigint; r jsonb; d jsonb;
BEGIN
 d:=jsonb_set(np03b_invoice_test.doc(),'{lines,0,unit_price}','300.1234');
 o:=np03b_invoice_test.confirmed('invoice_fractional_source',d);
 PERFORM np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{"money_scale":0}','invoice_wrong_source_rounding');
 PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,'''',''invoice_inexact_rounding'')',o),'SALES_INVOICE_SOURCE_ROUNDING');
 PERFORM np03b_invoice_test.control('sales.invoice_draft',true,0::smallint,'{"allow_partial_quantities":true}','invoice_source_rounding_restored');
 r:=core10.save_sales_invoice_draft_v1(101,1001,NULL,0,o,2,NULL,'Four-place Master price','invoice_four_place_price');
 PERFORM np03b_invoice_test.ok((r->>'total')::numeric=1020.25,'four-place source price has two-place line rounding');
END $$;
RESET ROLE;
UPDATE core10.master_price_list_items_v1 SET unit_price=300 WHERE price_list_id=7101 AND item_id=8101 AND variant_id IS NULL;
-- An invoice audit append failure rolls back header, lines, command receipt and
-- any validation version increment atomically, preserving the canonical chain.
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.confirmed('invoice_atomic_source') AS atomic_source \gset
RESET ROLE;
CREATE FUNCTION np03b_invoice_test.reject_invoice_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.source_domain='sales_invoice' THEN RAISE EXCEPTION 'TEST_INVOICE_AUDIT_FAILURE'; END IF; RETURN NEW; END $$;
CREATE TRIGGER np03b_invoice_test_audit_failure BEFORE INSERT ON core10.canonical_audit_events_v1
 FOR EACH ROW EXECUTE FUNCTION np03b_invoice_test.reject_invoice_audit();
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,'''',''invoice_audit_save_failure'')',:'atomic_source'),'TEST_INVOICE_AUDIT_FAILURE');
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,5,NULL,''invoice_audit_validate_failure'')',current_setting('np03b_inv.invoice')),'TEST_INVOICE_AUDIT_FAILURE');
RESET ROLE;
DROP TRIGGER np03b_invoice_test_audit_failure ON core10.canonical_audit_events_v1;
SELECT np03b_invoice_test.ok(NOT EXISTS(SELECT FROM core10.sales_invoice_drafts_v1 WHERE source_order_id=:'atomic_source'),'failed create has no header');
SELECT np03b_invoice_test.ok(NOT EXISTS(SELECT FROM core10.sales_invoice_draft_lines_v1 WHERE source_order_id=:'atomic_source'),'failed create has no lines');
SELECT np03b_invoice_test.ok(NOT EXISTS(SELECT FROM core10.sales_invoice_commands_v1 WHERE request_key IN('invoice_audit_save_failure','invoice_audit_validate_failure','invoice_master_changed','invoice_currency_changed')),'failed writes have no receipt');
SELECT np03b_invoice_test.ok((SELECT version=5 FROM core10.sales_invoice_drafts_v1 WHERE id=current_setting('np03b_inv.invoice')::bigint),'failed validation preserves prior version');
SELECT np03b_invoice_test.ok((SELECT count(*)=count(DISTINCT source_order_id) FROM core10.sales_invoice_drafts_v1),'at most one draft per source');
SELECT np03b_invoice_test.ok((SELECT count(*)=5 FROM core10.canonical_audit_events_v1 a JOIN core10.sales_invoice_commands_v1 c ON c.audit_event_id=a.id WHERE c.invoice_id=current_setting('np03b_inv.invoice')::bigint),'one canonical audit per successful command, no duplicate replay event');
SELECT np03b_invoice_test.ok((core10.verify_canonical_audit_v1(101)->>'ok')::boolean,'audit chain survives invoice append rollback');
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,%s,5,%s,2,''[{"order_line_no":1,"quantity":1}]'',''Cannot replace original order'',''invoice_source_substitution'')',current_setting('np03b_inv.invoice'),:'atomic_source'),'SALES_INVOICE_SOURCE_IMMUTABLE');
-- Every nonowner A046 alias is denied, including another tenant's owner and
-- staff with stock permissions. No client role label grants invoice authority.
DO $$ DECLARE u text; BEGIN
 FOREACH u IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444',
 '55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777',
 '88888888-8888-4888-8888-888888888888','99999999-9999-4999-8999-999999999999','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','ffffffff-ffff-4fff-8fff-ffffffffffff','90909090-9090-4090-8090-909090909090'] LOOP
  PERFORM np03b_invoice_test.actor(u);
  PERFORM np03b_invoice_test.expect($q$SELECT core10.read_sales_invoice_drafts_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
  PERFORM np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,'''',''invoice_persona_denied'')',current_setting('np03b_inv.order')),'SALES_SCOPE_DENIED');
  PERFORM np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,3,NULL,''invoice_persona_validate'')',current_setting('np03b_inv.invoice')),'SALES_SCOPE_DENIED');
 END LOOP;
END $$;
SELECT np03b_invoice_test.actor(NULL);
SELECT np03b_invoice_test.expect($q$SELECT core10.read_sales_invoice_drafts_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
SET LOCAL ROLE anon;
SELECT np03b_invoice_test.expect($q$SELECT core10.read_sales_invoice_drafts_v1(101,1001)$q$,'permission denied');
SELECT np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,'''',''invoice_anon_create'')',current_setting('np03b_inv.order')),'permission denied');
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,5,NULL,''invoice_anon_validate'')',current_setting('np03b_inv.invoice')),'permission denied');
RESET ROLE;
-- Expired/revoked owner membership and an explicit site deny remain effective
-- after the invoice was created and even against a historically successful key.
UPDATE core10.business_members SET valid_until=now()-interval '1 day' WHERE user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.actor('22222222-2222-4222-8222-222222222222');
SELECT np03b_invoice_test.expect($q$SELECT core10.read_sales_invoice_drafts_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
RESET ROLE;
UPDATE core10.business_members SET valid_until=NULL,active=false WHERE user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,5,NULL,''invoice_revoked_validate'')',current_setting('np03b_inv.invoice')),'SALES_SCOPE_DENIED');
RESET ROLE;
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions)
VALUES(1,101,1001,'11111111-1111-4111-8111-111111111111','{}',ARRAY['stock.read']);
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.actor('11111111-1111-4111-8111-111111111111');
SELECT np03b_invoice_test.expect(format('SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,%s,2,NULL,''Synthetic full draft'',''invoice_main_save'')',current_setting('np03b_inv.order')),'SALES_SCOPE_DENIED');
RESET ROLE;
DELETE FROM core10.site_grants WHERE user_id='11111111-1111-4111-8111-111111111111';
-- Grant SELECT only inside this rollback-only test to prove default-deny RLS,
-- independently of the production API's lack of table privileges.
GRANT SELECT ON core10.sales_invoice_drafts_v1,core10.sales_invoice_draft_lines_v1,core10.sales_invoice_commands_v1 TO authenticated;
SET LOCAL ROLE authenticated;
SELECT np03b_invoice_test.ok((SELECT count(*)=0 FROM core10.sales_invoice_drafts_v1),'invoice header RLS');
SELECT np03b_invoice_test.ok((SELECT count(*)=0 FROM core10.sales_invoice_draft_lines_v1),'invoice line RLS');
SELECT np03b_invoice_test.ok((SELECT count(*)=0 FROM core10.sales_invoice_commands_v1),'invoice command RLS');
RESET ROLE;
SELECT np03b_invoice_test.ok((core10.verify_canonical_audit_v1(101)->>'ok')::boolean,'canonical audit chain intact');
SELECT np03b_invoice_test.ok((SELECT count(*)=0 FROM core10.stock_movements),'no stock movements');
SELECT np03b_invoice_test.ok((SELECT count(*)=0 FROM core10.finance_journals_v1),'no Money journals');
SELECT np03b_invoice_test.ok((SELECT count(*)=0 FROM core10.finance_journal_lines_v1),'no Money journal lines');
ROLLBACK;
\echo NP03B_INVOICE_DRAFT_TESTS_OK
