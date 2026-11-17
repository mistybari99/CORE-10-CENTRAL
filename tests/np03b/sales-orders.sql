\set ON_ERROR_STOP on
BEGIN;
\ir fixtures.sql
CREATE SCHEMA np03b_test;
GRANT USAGE ON SCHEMA np03b_test TO authenticated,anon;
CREATE FUNCTION np03b_test.ok(v boolean,m text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED:%',m; END IF; END $$;
CREATE FUNCTION np03b_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE e||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'WRONG_ERROR expected:% got:%',e,SQLERRM;
 END;
 RAISE EXCEPTION 'NO_ERROR:%',e;
END $$;
CREATE FUNCTION np03b_test.actor(v text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',v)::text,true),
 set_config('request.jwt.claim.sub',coalesce(v,''),true)
$$;
CREATE FUNCTION np03b_test.doc() RETURNS jsonb LANGUAGE sql AS $$ SELECT
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[
 {"item_id":8101,"variant_id":7301,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0},
 {"item_id":8102,"uom_id":7201,"quantity":1,"unit_price":420,"discount_percent":0,"tax_percent":0},
 {"item_id":8103,"uom_id":7201,"quantity":1,"unit_price":850,"discount_percent":0,"tax_percent":0},
 {"item_id":8104,"uom_id":7201,"quantity":1,"unit_price":1200,"discount_percent":0,"tax_percent":0},
 {"item_id":8105,"uom_id":7201,"quantity":1,"unit_price":250,"discount_percent":0,"tax_percent":0}]}'::jsonb $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np03b_test TO authenticated,anon;
SET LOCAL ROLE authenticated;
SELECT np03b_test.actor('11111111-1111-4111-8111-111111111111');
-- Exact mapped feature checks, before replay or mutation.
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'order_0001')$q$,'CONTROL_DISABLED:sales.order_draft');
SELECT np03b_test.expect($q$SELECT core10.transition_sales_order_v1(101,1001,1,'confirm',1,NULL,'confirm_0001')$q$,'CONTROL_DISABLED:sales.order_transition');
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic order test','sales_enable_draft');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,1::smallint,'{}',NULL,false,0,'Synthetic order test','sales_enable_transition');
DO $$ DECLARE r jsonb; x jsonb; o bigint; a bigint; a2 bigint; p jsonb;
BEGIN
 r:=core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'order_0001');o:=(r->>'order_id')::bigint;
 PERFORM np03b_test.ok(r->>'total'='3320.00' OR (r->>'total')::numeric=3320,'five products total');
 PERFORM np03b_test.ok(r=core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'order_0001'),'exact immutable receipt replay');
 PERFORM np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,quantity}','3'),'order_0001')$q$,'SALES_REPLAY_CONFLICT');
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',1,NULL,''confirm_0001'')',o),'SALES_APPROVAL_REQUIRED');
 r:=core10.save_sales_order_v1(101,1001,o,1,np03b_test.doc(),'amend_0001');
 PERFORM np03b_test.ok((r->>'version')::int=2,'amend bumps version');
 PERFORM np03b_test.expect(format('SELECT core10.save_sales_order_v1(101,1001,%s,1,np03b_test.doc(),''stale_0001'')',o),'SALES_STALE_VERSION');
 PERFORM core10.publish_approval_policy_v1(101,'sales','confirm',1440,'sales_policy_confirm');
 p:=jsonb_build_object('order_id',o,'site_id',1001,'version',2,'document',np03b_test.doc(),'total',3320.00,'action','confirm','required_stages',1);
 a:=core10.submit_typed_approval_v1(101,'sales','confirm','sales-order:'||o,2,p,'sales_approval_0001');
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',2,%s,''confirm_0001'')',o,a),'approval_not_effective');
 PERFORM np03b_test.expect(format('SELECT core10.decide_approval(%s,''approve'',''self_decide_0001'')',a),'approval_not_authorized');
 PERFORM np03b_test.actor('22222222-2222-4222-8222-222222222222');
 PERFORM core10.decide_approval(a,'approve','approve_sales_0001');
 PERFORM np03b_test.actor('11111111-1111-4111-8111-111111111111');
 -- A valid one-review receipt must not satisfy a current two-stage setting.
 PERFORM core10.control_set_v1(101,NULL,'sales.order_transition',true,2::smallint,'{}',NULL,false,1,'Two stage mismatch test','sales_two_stages');
 a2:=core10.submit_typed_approval_v1(101,'sales','confirm','sales-order:'||o,2,jsonb_set(p,'{required_stages}','2'),'sales_stage_receipt');
 PERFORM np03b_test.actor('22222222-2222-4222-8222-222222222222');
 PERFORM core10.decide_approval(a2,'approve','sales_approve_stage');
 PERFORM np03b_test.actor('11111111-1111-4111-8111-111111111111');
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',2,%s,''stage_mismatch_01'')',o,a2),'SALES_APPROVAL_STAGES');
 PERFORM core10.control_set_v1(101,NULL,'sales.order_transition',true,1::smallint,'{}',NULL,false,2,'Restore one stage test','sales_restore_stage');
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',2,%s,''hash_mismatch_01'')',o,a2),'approval_stale_or_payload_changed');
 -- An approved receipt cannot authorize another order/version/payload.
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',2,%s,''wrong_receipt_01'')',o,a+100000),'approval_not_effective');
 r:=core10.transition_sales_order_v1(101,1001,o,'confirm',2,a,'confirm_0001');
 PERFORM np03b_test.ok(r->>'status'='confirmed' AND r->>'financial_posted'='false' AND r->>'stock_posted'='false','approval confirms without fake posting');
 PERFORM np03b_test.ok(r=core10.transition_sales_order_v1(101,1001,o,'confirm',2,a,'confirm_0001'),'transition replay');
 PERFORM np03b_test.expect(format('SELECT core10.save_sales_order_v1(101,1001,%s,3,np03b_test.doc(),''immutable_0001'')',o),'SALES_INVALID_TRANSITION');
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''cancel'',3,NULL,''cancel_confirmed'')',o),'SALES_INVALID_TRANSITION');
 PERFORM np03b_test.ok(jsonb_array_length(core10.read_sales_orders_v1(101,1001,o)->'items')=1,'scoped read');
 PERFORM np03b_test.ok(jsonb_array_length(core10.read_sales_orders_v1(101,1002,o)->'items')=0,'same business other site isolated');
END $$;
-- Values and canonical Master rejection, not only frontend validation.
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,quantity}','-1'),'negative_0001')$q$,'SALES_VALUE_INVALID');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,unit_price}','-1'),'negative_price')$q$,'SALES_VALUE_INVALID');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,quantity}','null'),'null_qty_0001')$q$,'SALES_NUMBER_INVALID');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,unit_price}','301'),'wrong_price_0001')$q$,'SALES_MASTER_REJECTED');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,uom_id}','9999'),'wrong_uom_0001')$q$,'SALES_MASTER_REJECTED');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{customer_id}','7999'),'wrong_customer')$q$,'SALES_MASTER_REJECTED');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,item_id}','9999'),'wrong_item_0001')$q$,'SALES_MASTER_REJECTED');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,discount_percent}','1'),'discount_0001')$q$,'SALES_VALUE_INVALID');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,tax_percent}','1'),'tax_case_0001')$q$,'SALES_TAX_DISABLED');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,2001,NULL,0,np03b_test.doc(),'wrong_site_0001')$q$,'SALES_SCOPE_DENIED');
SELECT np03b_test.expect($q$SELECT * FROM core10.sales_orders_v1$q$,'permission denied');
SELECT np03b_test.expect($q$DELETE FROM core10.sales_order_lines_v1$q$,'permission denied');
SELECT np03b_test.expect($q$SELECT core10._sales_validate_v1(101,1001,np03b_test.doc(),'{}')$q$,'permission denied');
-- All remaining A046 aliases lack owner Sales authority for business 101.
DO $$ DECLARE u text; BEGIN
 FOREACH u IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444',
 '55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777',
 '88888888-8888-4888-8888-888888888888','99999999-9999-4999-8999-999999999999','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','ffffffff-ffff-4fff-8fff-ffffffffffff','90909090-9090-4090-8090-909090909090'] LOOP
  PERFORM np03b_test.actor(u);
  PERFORM np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'persona_denied')$q$,'SALES_SCOPE_DENIED');
  PERFORM np03b_test.expect($q$SELECT core10.read_sales_orders_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
 END LOOP;
END $$;
SELECT np03b_test.actor(NULL);
SELECT np03b_test.expect($q$SELECT core10.read_sales_orders_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
SET LOCAL ROLE anon;
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'anon_denied_01')$q$,'permission denied');
RESET ROLE;
SELECT np03b_test.actor('11111111-1111-4111-8111-111111111111');
SELECT np03b_test.ok((core10.verify_canonical_audit_v1(101)->>'ok')::boolean,'canonical audit integrity');
SELECT np03b_test.ok((SELECT count(*)=3 FROM core10.canonical_audit_events_v1 WHERE source_domain='sales'),'one audit per successful command, replay has none');
SELECT np03b_test.ok((SELECT count(*)=5 FROM core10.sales_order_lines_v1),'five scoped lines');
SELECT np03b_test.ok((SELECT count(*)=0 FROM core10.stock_movements),'no stock posting');
-- A disabled switch blocks a previously successful retry, not only new writes.
SET LOCAL ROLE authenticated;
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',false,0::smallint,'{}',NULL,false,1,'Pause all order drafts','sales_pause_draft');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'order_0001')$q$,'CONTROL_DISABLED:sales.order_draft');
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{"max_discount_percent":5}',NULL,false,2,'Synthetic discount allowance','sales_resume_draft');
DO $$ DECLARE r jsonb; d jsonb; o bigint; BEGIN
 d:=jsonb_set(np03b_test.doc(),'{lines,0,discount_percent}','5');
 r:=core10.save_sales_order_v1(101,1001,NULL,0,d,'discount_valid_01');
 PERFORM np03b_test.ok((r->>'total')::numeric=3290,'configured discount total');
 PERFORM np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_test.doc(),'{lines,0,discount_percent}','5.01'),'discount_over_01')$q$,'SALES_VALUE_INVALID');
 -- Explicit zero-stage cancellation is still owner-configured and audited.
 PERFORM core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,3,'Synthetic zero stage cancellation','sales_zero_stages');
 o:=(r->>'order_id')::bigint;
 r:=core10.transition_sales_order_v1(101,1001,o,'cancel',1,NULL,'cancel_draft_01');
 PERFORM np03b_test.ok(r->>'status'='cancelled','draft cancellation');
 PERFORM np03b_test.expect(format('SELECT core10.transition_sales_order_v1(101,1001,%s,''confirm'',2,NULL,''confirm_cancelled'')',o),'SALES_INVALID_TRANSITION');
 -- Separate wholesale price scenario, actual authoritative test adapter check.
 d:=jsonb_set(np03b_test.doc(),'{price_list_id}','7102');
 SELECT jsonb_set(d,'{lines}',jsonb_agg(jsonb_set(l,'{unit_price}',to_jsonb((l->>'unit_price')::numeric*.9)))) INTO d
 FROM jsonb_array_elements(d->'lines') l;
 r:=core10.save_sales_order_v1(101,1001,NULL,0,d,'wholesale_valid_01');
 PERFORM np03b_test.ok((r->>'total')::numeric=2988,'wholesale price list');
END $$;
RESET ROLE;
-- Failed audit append rolls back the entire domain aggregate and idempotency.
CREATE FUNCTION np03b_test.reject_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.source_domain='sales' THEN RAISE EXCEPTION 'TEST_AUDIT_FAILURE'; END IF; RETURN NEW; END $$;
CREATE TRIGGER np03b_test_audit_failure BEFORE INSERT ON core10.canonical_audit_events_v1
 FOR EACH ROW EXECUTE FUNCTION np03b_test.reject_audit();
SET LOCAL ROLE authenticated;
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'audit_fail_01')$q$,'TEST_AUDIT_FAILURE');
RESET ROLE;
DROP TRIGGER np03b_test_audit_failure ON core10.canonical_audit_events_v1;
SELECT np03b_test.ok((SELECT count(*)=3 FROM core10.sales_orders_v1),'audit failure rolled header back');
SELECT np03b_test.ok(NOT EXISTS(SELECT 1 FROM core10.sales_order_commands_v1 WHERE request_key='audit_fail_01'),'audit failure has no receipt');
SELECT np03b_test.ok((core10.verify_canonical_audit_v1(101)->>'ok')::boolean,'audit integrity after rollback');
-- Revoke/expiry/site DENY and default-deny RLS even if read granted to prove policies.
UPDATE core10.business_members SET valid_until=now()-interval '1 day' WHERE user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT np03b_test.actor('22222222-2222-4222-8222-222222222222');
SELECT np03b_test.expect($q$SELECT core10.read_sales_orders_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
RESET ROLE;
UPDATE core10.business_members SET valid_until=NULL,active=false WHERE user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'revoked_write_01')$q$,'SALES_SCOPE_DENIED');
RESET ROLE;
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions)
 VALUES(1,101,1001,'11111111-1111-4111-8111-111111111111','{}',ARRAY['stock.read']);
SET LOCAL ROLE authenticated;
SELECT np03b_test.actor('11111111-1111-4111-8111-111111111111');
SELECT np03b_test.expect($q$SELECT core10.read_sales_orders_v1(101,1001)$q$,'SALES_SCOPE_DENIED');
RESET ROLE;
DELETE FROM core10.site_grants WHERE user_id='11111111-1111-4111-8111-111111111111';
GRANT SELECT ON core10.sales_orders_v1,core10.sales_order_lines_v1,core10.sales_order_commands_v1 TO authenticated;
SET LOCAL ROLE authenticated;
SELECT np03b_test.ok((SELECT count(*)=0 FROM core10.sales_orders_v1),'RLS header deny');
SELECT np03b_test.ok((SELECT count(*)=0 FROM core10.sales_order_lines_v1),'RLS lines deny');
SELECT np03b_test.ok((SELECT count(*)=0 FROM core10.sales_order_commands_v1),'RLS commands deny');
RESET ROLE;
-- Test the production missing-port boundary, not a speculative implementation.
ALTER FUNCTION core10.master_validate_sales_order_v1(bigint,bigint,jsonb) RENAME TO np03b_test_absent_port;
SET LOCAL ROLE authenticated;
SELECT np03b_test.actor('11111111-1111-4111-8111-111111111111');
SELECT np03b_test.expect($q$SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_test.doc(),'missing_master')$q$,'NOT_CONNECTED:MASTER_SALES_VALIDATION');
ROLLBACK;
\echo NP03B_SALES_ORDER_TESTS_OK_CANONICAL_MASTER_SYNTHETIC_DATA
