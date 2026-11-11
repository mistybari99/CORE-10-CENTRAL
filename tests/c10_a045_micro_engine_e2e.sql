-- C10-A045 disposable E2E (PostgreSQL, c10_demo). Signed-session CLAIM SIMULATION only:
-- request.jwt.claim.sub set per transaction. This is NOT Supabase GoTrue / NOT live RLS certification.
-- Businesses 101 (Business A) and 102 (Business B) belong to tenant 1; 201 belongs to tenant 2.
\set ON_ERROR_STOP on
DROP TABLE IF EXISTS public.t045_baseline;
DROP FUNCTION IF EXISTS public.t045_fail(text,text);
CREATE FUNCTION public.t045_fail(q text,expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE q;
 RAISE EXCEPTION 'EXPECTED_FAILURE_DID_NOT_HAPPEN: %',q;
EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE 'EXPECTED_FAILURE_DID_NOT_HAPPEN%' THEN RAISE; END IF;
 IF expect IS NOT NULL AND SQLERRM NOT LIKE '%'||expect||'%' THEN
  RAISE EXCEPTION 'WRONG_FAILURE for [%]: got [%], wanted [%]',q,SQLERRM,expect; END IF;
END$$;
GRANT EXECUTE ON FUNCTION public.t045_fail(text,text) TO authenticated,anon;
CREATE TABLE public.t045_baseline AS
 SELECT (SELECT count(*) FROM c10_demo.stock_movements) mv,(SELECT count(*) FROM c10_demo.stock_summary) ss,
        (SELECT count(*) FROM c10_demo.items) it;

-- ===== 1. Master Owner: create, validate, preview, version, publish to A and B =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb; y jsonb; d jsonb:='{"field":"on_hand","op":"lt","threshold":12,"outcome":"warn","message":"Stock below advisory level"}';
BEGIN
 x:=c10_demo.save_engine_draft_v1(1,'stock_low_threshold_advisory','Stock Low Threshold Advisory','threshold_rule_v1',d,0,'req045_save_01','Create advisory threshold');
 IF x->>'status'<>'saved' OR x->>'version'<>'1' OR x->>'state'<>'DRAFT' OR (x->>'can_execute')<>'true' THEN RAISE EXCEPTION 'SAVE_FAILED %',x; END IF;
 y:=c10_demo.save_engine_draft_v1(1,'stock_low_threshold_advisory','Stock Low Threshold Advisory','threshold_rule_v1',d,0,'req045_save_01','Create advisory threshold');
 IF x<>y THEN RAISE EXCEPTION 'REPLAY_NOT_IDENTICAL'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'stock_low_threshold_advisory','Stock Low Threshold Advisory','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":99,"outcome":"warn"}',0,'req045_save_01','Tampered replay payload')$q$,'idempotency_conflict');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'bad_a','Bad A','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"warn","formula":"1+1"}',0,'req045_bad_a1','Unknown key must fail')$q$,'invalid_descriptor');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'bad_b','Bad B','threshold_rule_v1','{"field":"on_hand","op":"eval","threshold":1,"outcome":"warn"}',0,'req045_bad_b1','Bad operator')$q$,'invalid_descriptor');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'bad_c','Bad C','threshold_rule_v1','{"field":"secret_col","op":"lt","threshold":1,"outcome":"warn"}',0,'req045_bad_c1','Bad field')$q$,'invalid_descriptor');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'bad_d','Bad D','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":"12; DROP TABLE x","outcome":"warn"}',0,'req045_bad_d1','String threshold')$q$,'invalid_descriptor');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'bad_e','Bad E','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"post_stock"}',0,'req045_bad_e1','Bad outcome')$q$,'invalid_descriptor');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'Bad F','Bad F','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"warn"}',0,'req045_bad_f1','Bad key format')$q$,NULL);
 x:=c10_demo.preview_engine_draft_v1(1,'threshold_rule_v1',d,'{}','{"on_hand":8}');
 IF x->>'outcome'<>'warn' OR (x->>'matched')<>'true' OR (x->>'canAuthorizeOperation')<>'false' OR (x->>'mutates')<>'false' OR (x->>'advisory')<>'true' THEN RAISE EXCEPTION 'PREVIEW_8 %',x; END IF;
 x:=c10_demo.preview_engine_draft_v1(1,'threshold_rule_v1',d,'{}','{"on_hand":20}');
 IF x->>'outcome'<>'allow' OR (x->>'matched')<>'false' THEN RAISE EXCEPTION 'PREVIEW_20 %',x; END IF;
 x:=c10_demo.preview_engine_draft_v1(1,'threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":12,"outcome":"block"}','{}','{"on_hand":1}');
 IF (x->>'wouldBlock')<>'true' OR (x->>'canAuthorizeOperation')<>'false' THEN RAISE EXCEPTION 'ADVISORY_BLOCK %',x; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_engine_draft_v1(1,'threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":12,"outcome":"warn"}','{}','{"days_cover":8}')$q$,'invalid_input');
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_engine_draft_v1(1,'workflow_v1','{}','{}','{"on_hand":1}')$q$,'handler_not_executable');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,101,1,'PUBLISHED','{}','both','business_owner',0,'req045_pub_early','Publish before validate')$q$,'engine_version_not_validated');
 x:=c10_demo.validate_engine_version_v1(1,1,'req045_val_01','Validated threshold advisory');
 IF x->>'state'<>'VALIDATED' THEN RAISE EXCEPTION 'VALIDATE_FAILED'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.validate_engine_version_v1(1,1,'req045_val_02','Validate again')$q$,'engine_already_validated');
 x:=c10_demo.assign_engine_v1(1,101,1,'PUBLISHED','{"threshold":12}','both','business_owner',0,'req045_pub_a1','Publish to Business A');
 IF x->>'status'<>'applied' OR x->>'version'<>'1' THEN RAISE EXCEPTION 'PUBLISH_A %',x; END IF;
 x:=c10_demo.assign_engine_v1(1,102,1,'PUBLISHED','{"threshold":30}','business_only','central_only',0,'req045_pub_b1','Publish to Business B');
 IF x->>'version'<>'1' THEN RAISE EXCEPTION 'PUBLISH_B %',x; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,102,1,'PUBLISHED','{"threshold":30}','business_only','central_only',0,'req045_pub_b2','Stale expected version')$q$,'engine_stale_version');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,201,1,'PUBLISHED','{}','both','business_owner',0,'req045_pub_x01','Cross tenant business')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,102,1,'PAUSED','{}','hidden_from_menus','business_owner',1,'req045_bad_ph1','Hidden requires central edit')$q$,'invalid_engine_request');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,102,1,'PUBLISHED','{"formula":"x"}','both','business_owner',1,'req045_bad_pm1','Unknown param key')$q$,'invalid_engine_request');
 x:=c10_demo.read_business_engines_v1(101);
 IF x->'items'->0->'effective'->>'threshold'<>'12' OR x->'items'->0->>'placement'<>'both' OR x->'items'->0->>'control_id'<>'engine.stock_low_threshold_advisory' THEN RAISE EXCEPTION 'READ_A %',x; END IF;
 y:=c10_demo.read_business_engines_v1(102);
 IF y->'items'->0->'effective'->>'threshold'<>'30' OR y->'items'->0->>'placement'<>'business_only' THEN RAISE EXCEPTION 'READ_B %',y; END IF;
 x:=c10_demo.preview_business_engine_v1(1,101,'{"on_hand":20}');
 IF x->>'outcome'<>'allow' THEN RAISE EXCEPTION 'A_20 %',x; END IF;
 y:=c10_demo.preview_business_engine_v1(1,102,'{"on_hand":20}');
 IF y->>'outcome'<>'warn' OR y->>'business_id'<>'102' THEN RAISE EXCEPTION 'B_20 %',y; END IF;
 x:=c10_demo.save_engine_draft_v1(1,'order_flow_idea','Order Flow Idea','workflow_v1','{"note":"inert draft"}',0,'req045_save_wf','Draft only, not implemented');
 IF (x->>'can_execute')<>'false' THEN RAISE EXCEPTION 'WF_CAN_EXECUTE'; END IF;
 PERFORM public.t045_fail(format($q$SELECT c10_demo.validate_engine_version_v1(%s,1,'req045_val_wf','Cannot validate uncertified')$q$,x->>'engine_id'),'handler_not_certified');
 PERFORM public.t045_fail(format($q$SELECT c10_demo.assign_engine_v1(%s,101,1,'PUBLISHED','{}','both','business_owner',0,'req045_pub_wf','Cannot publish uncertified')$q$,x->>'engine_id'),'handler_not_certified');
 x:=c10_demo.read_engines_v1(1);
 IF jsonb_array_length(x->'engines')<>2 OR jsonb_array_length(x->'handlers')<>9 THEN RAISE EXCEPTION 'READ_ENGINES %',x; END IF;
END$$;
COMMIT;

-- ===== 2. Business Owner of A: delegated scope only =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$
DECLARE x jsonb;
BEGIN
 x:=c10_demo.read_business_engines_v1(101);
 IF jsonb_array_length(x->'items')<>1 THEN RAISE EXCEPTION 'BO_READ_A'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.read_business_engines_v1(102)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.read_engines_v1(1)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.read_engine_audit_v1(1)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'sneaky','Sneaky Engine','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"warn"}',0,'req045_bo_save','Business owner creates engine')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,102,1,'REVOKED','{}','both','business_owner',1,'req045_bo_asg','Business owner publishes elsewhere')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,102,'{"threshold":1}',1,'req045_bo_cross','Cross business edit attempt')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_business_engine_v1(1,102,'{"on_hand":1}')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,101,'{"formula":"1"}',1,'req045_bo_bad','Invalid params')$q$,'invalid_engine_request');
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,101,'{"threshold":15}',9,'req045_bo_stale','Stale version')$q$,'engine_stale_version');
 PERFORM public.t045_fail($q$SELECT * FROM c10_demo.micro_engines_v1$q$,'permission denied');
 PERFORM public.t045_fail($q$INSERT INTO c10_demo.micro_engine_assignments_v1(engine_id,tenant_id,business_id,state,pinned_version,placement,local_edit_mode,changed_by) VALUES(1,1,101,'PUBLISHED',1,'both','business_owner',gen_random_uuid())$q$,'permission denied');
 PERFORM public.t045_fail($q$UPDATE c10_demo.micro_engine_assignments_v1 SET state='PUBLISHED'$q$,'permission denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.engine_audit_v1(1,1,101,'params_edited',NULL,NULL,'req045_forge')$q$,'permission denied');
 x:=c10_demo.edit_engine_params_v1(1,101,'{"threshold":15}',1,'req045_bo_edit1','Raise Business A advisory level');
 IF x->>'status'<>'applied' OR x->>'version'<>'2' THEN RAISE EXCEPTION 'BO_EDIT %',x; END IF;
END$$;
COMMIT;

-- ===== 3. Manager / Staff / Revoked / Other tenant / Anonymous: denied everywhere =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.read_business_engines_v1(101)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,101,'{"threshold":1}',2,'req045_mgr_ed1','Manager edit denied')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'mgr_engine','Manager Engine','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"warn"}',0,'req045_mgr_sv1','Manager create denied')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,101,1,'PAUSED','{}','both','business_owner',2,'req045_mgr_as1','Manager pause denied')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.decide_engine_request_v1(1,'approve')$q$,NULL);
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='44444444-4444-4444-8444-444444444444';
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.read_business_engines_v1(101)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_business_engine_v1(1,101,'{"on_hand":1}')$q$,'engine_denied');
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='66666666-6666-4666-8666-666666666666';
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.read_business_engines_v1(101)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,101,'{"threshold":1}',2,'req045_rev_ed1','Revoked edit denied')$q$,'engine_denied');
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='77777777-7777-4777-8777-777777777777';
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.read_engines_v1(1)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.read_business_engines_v1(101)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'x_tenant','Cross Tenant','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"warn"}',0,'req045_xt_sv1','Cross tenant create')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,201,1,'PUBLISHED','{}','both','business_owner',0,'req045_xt_as1','Cross tenant publish')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.rollback_engine_assignment_v1(1,101,1,2,'req045_xt_rb1','Cross tenant rollback')$q$,'engine_denied');
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated; -- authenticated role without any signed subject
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.read_engines_v1(1)$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'anon_eng','Anonymous Engine','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":1,"outcome":"warn"}',0,'req045_an_sv1','Anonymous create')$q$,'engine_denied');
END$$;
COMMIT;
BEGIN;
SET ROLE anon;
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.read_business_engines_v1(101)$q$,'permission denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'anon_eng','Anonymous Engine','threshold_rule_v1','{}',0,'req045_an_sv2','Anon role denied')$q$,'permission denied');
END$$;
COMMIT;

-- ===== 4. Approval flow (request_approval): no silent write, no local approval =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb;
BEGIN
 -- a business-owner's request key replayed by the tenant owner is actor-bound -> conflict
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,101,'{"threshold":15}',1,'req045_bo_edit1','Raise Business A advisory level')$q$,'idempotency_conflict');
 x:=c10_demo.assign_engine_v1(1,101,1,'PUBLISHED','{"threshold":15}','both','request_approval',2,'req045_asg_ra1','Switch Business A to approval mode');
 IF x->>'version'<>'3' THEN RAISE EXCEPTION 'ASG_RA %',x; END IF;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$
DECLARE x jsonb;
BEGIN
 x:=c10_demo.edit_engine_params_v1(1,101,'{"threshold":18}',3,'req045_bo_req1','Request higher advisory level');
 IF x->>'status'<>'pending' OR x->>'version'<>'3' THEN RAISE EXCEPTION 'REQ_NOT_PENDING %',x; END IF;
 IF (c10_demo.read_business_engines_v1(101)->'items'->0->'effective'->>'threshold')<>'15' THEN RAISE EXCEPTION 'SILENT_WRITE'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.decide_engine_request_v1(1,'approve')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.read_engine_pending_v1(1)$q$,'engine_denied');
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb;
BEGIN
 IF jsonb_array_length(c10_demo.read_engine_pending_v1(1)->'items')<>1 THEN RAISE EXCEPTION 'PENDING_LIST'; END IF;
 x:=c10_demo.decide_engine_request_v1(1,'approve');
 IF x->>'status'<>'approved' THEN RAISE EXCEPTION 'APPROVE %',x; END IF;
 IF (c10_demo.decide_engine_request_v1(1,'approve'))->>'status'<>'approved' THEN RAISE EXCEPTION 'APPROVE_REPLAY'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.decide_engine_request_v1(1,'reject')$q$,'engine_decision_conflict');
 IF (c10_demo.read_business_engines_v1(101)->'items'->0->'effective'->>'threshold')<>'18' THEN RAISE EXCEPTION 'APPROVED_NOT_APPLIED'; END IF;
 IF (c10_demo.read_business_engines_v1(102)->'items'->0->'effective'->>'threshold')<>'30' THEN RAISE EXCEPTION 'B_CHANGED'; END IF;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$BEGIN PERFORM c10_demo.edit_engine_params_v1(1,101,'{"threshold":25}',4,'req045_bo_req2','Second request that will go stale'); END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb;
BEGIN
 x:=c10_demo.edit_engine_params_v1(1,101,'{"threshold":19}',4,'req045_own_edit','Owner direct edit bumps version');
 IF x->>'version'<>'5' THEN RAISE EXCEPTION 'OWNER_EDIT %',x; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.decide_engine_request_v1(2,'approve')$q$,'engine_request_stale');
 x:=c10_demo.decide_engine_request_v1(2,'reject');
 IF x->>'status'<>'rejected' THEN RAISE EXCEPTION 'REJECT'; END IF;
END$$;
COMMIT;

-- ===== 5. Independence: pause/revoke A, B untouched; stale write rejected =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb;
BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,101,1,'PAUSED','{"threshold":19}','both','request_approval',2,'req045_pa_st1','Stale pause')$q$,'engine_stale_version');
 x:=c10_demo.assign_engine_v1(1,101,1,'PAUSED','{"threshold":19}','both','request_approval',5,'req045_pa_01','Pause Business A');
 IF x->>'state'<>'PAUSED' OR x->>'version'<>'6' THEN RAISE EXCEPTION 'PAUSE %',x; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_business_engine_v1(1,101,'{"on_hand":1}')$q$,'engine_not_published');
 PERFORM public.t045_fail($q$SELECT c10_demo.edit_engine_params_v1(1,101,'{"threshold":3}',6,'req045_pa_ed1','Edit while paused')$q$,'engine_not_published');
 IF c10_demo.preview_business_engine_v1(1,102,'{"on_hand":20}')->>'outcome'<>'warn' THEN RAISE EXCEPTION 'B_AFFECTED_BY_PAUSE'; END IF;
 x:=c10_demo.assign_engine_v1(1,101,1,'REVOKED','{"threshold":19}','both','request_approval',6,'req045_rv_01','Revoke Business A');
 IF x->>'state'<>'REVOKED' THEN RAISE EXCEPTION 'REVOKE'; END IF;
 IF c10_demo.preview_business_engine_v1(1,102,'{"on_hand":20}')->>'outcome'<>'warn' THEN RAISE EXCEPTION 'B_AFFECTED_BY_REVOKE'; END IF;
 IF (c10_demo.read_business_engines_v1(102)->'items'->0->>'version')<>'1' THEN RAISE EXCEPTION 'B_VERSION_MOVED'; END IF;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$BEGIN
 IF jsonb_array_length(c10_demo.read_business_engines_v1(101)->'items')<>0 THEN RAISE EXCEPTION 'REVOKED_STILL_VISIBLE_TO_BO'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_business_engine_v1(1,101,'{"on_hand":1}')$q$,'engine_denied');
END$$;
COMMIT;

-- ===== 6. Version integrity: v2 does not disturb B pinned to v1 =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb;
BEGIN
 x:=c10_demo.save_engine_draft_v1(1,'stock_low_threshold_advisory','Stock Low Threshold Advisory','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":20,"outcome":"block","message":"v2"}',1,'req045_save_v2','Draft v2 with block outcome');
 IF x->>'version'<>'2' THEN RAISE EXCEPTION 'V2 %',x; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'stock_low_threshold_advisory','Stock Low Threshold Advisory','threshold_rule_v1','{"field":"on_hand","op":"lt","threshold":21,"outcome":"warn"}',1,'req045_save_v2b','Stale engine version')$q$,'engine_stale_version');
 PERFORM public.t045_fail($q$SELECT c10_demo.save_engine_draft_v1(1,'stock_low_threshold_advisory','Stock Low Threshold Advisory','workflow_v1','{}',2,'req045_save_hc','Handler change denied')$q$,'handler_change_denied');
 IF c10_demo.preview_business_engine_v1(1,102,'{"on_hand":15}')->>'outcome'<>'warn' THEN RAISE EXCEPTION 'B_USES_V2_EARLY'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.assign_engine_v1(1,102,2,'PUBLISHED','{"threshold":30}','business_only','central_only',1,'req045_b_v2_early','v2 not validated')$q$,'engine_version_not_validated');
 PERFORM c10_demo.validate_engine_version_v1(1,2,'req045_val_v2','Validate v2');
 x:=c10_demo.assign_engine_v1(1,102,2,'PUBLISHED','{"threshold":30}','business_only','central_only',1,'req045_b_v2','Move Business B to v2');
 IF x->>'version'<>'2' THEN RAISE EXCEPTION 'B_V2 %',x; END IF;
 x:=c10_demo.preview_business_engine_v1(1,102,'{"on_hand":15}');
 IF x->>'outcome'<>'block' OR x->>'wouldBlock'<>'true' OR x->>'canAuthorizeOperation'<>'false' THEN RAISE EXCEPTION 'B_V2_EVAL %',x; END IF;
END$$;
COMMIT;

-- ===== 7. Configuration-only rollback =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb; aid bigint; other bigint;
BEGIN
 SELECT (i->>'audit_id')::bigint INTO aid FROM jsonb_array_elements(c10_demo.read_engine_audit_v1(1)->'items') i
  WHERE i->>'event'='assignment_changed' AND i->>'business_id'='102' AND i->'after'->>'pinned_version'='2';
 SELECT (i->>'audit_id')::bigint INTO other FROM jsonb_array_elements(c10_demo.read_engine_audit_v1(1)->'items') i
  WHERE i->>'event'='assignment_changed' AND i->>'business_id'='101' LIMIT 1;
 IF aid IS NULL OR other IS NULL THEN RAISE EXCEPTION 'AUDIT_LOOKUP'; END IF;
 PERFORM public.t045_fail(format($q$SELECT c10_demo.rollback_engine_assignment_v1(1,102,%s,2,'req045_rb_wrong','Wrong business audit row')$q$,other),'engine_rollback_target_invalid');
 PERFORM public.t045_fail(format($q$SELECT c10_demo.rollback_engine_assignment_v1(1,102,%s,1,'req045_rb_stale','Stale rollback')$q$,aid),'engine_stale_version');
 x:=c10_demo.rollback_engine_assignment_v1(1,102,aid,2,'req045_rb_ok01','Roll Business B back to v1 configuration');
 IF x->>'status'<>'rolled_back' OR x->>'state'<>'PUBLISHED' OR x->>'version'<>'3' OR (x->>'config_only')<>'true' THEN RAISE EXCEPTION 'ROLLBACK %',x; END IF;
 x:=c10_demo.preview_business_engine_v1(1,102,'{"on_hand":15}');
 IF x->>'outcome'<>'warn' OR x->>'version'<>'1' THEN RAISE EXCEPTION 'ROLLBACK_EVAL %',x; END IF;
 IF c10_demo.rollback_engine_assignment_v1(1,102,aid,2,'req045_rb_ok01','Roll Business B back to v1 configuration')->>'version'<>'3' THEN RAISE EXCEPTION 'RB_REPLAY'; END IF;
 IF jsonb_array_length(c10_demo.read_engine_audit_v1(1)->'items')<12 THEN RAISE EXCEPTION 'AUDIT_TOO_SMALL'; END IF;
END$$;
COMMIT;

-- ===== 7b. Site-level overrides (A: sites 1001/1002; B: site 1003) =====
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb;
BEGIN
 -- Business A was revoked in section 5; republish it (config version continues) for the override tests
 x:=c10_demo.assign_engine_v1(1,101,1,'PUBLISHED','{"threshold":12}','both','business_owner',(SELECT (i->>'version')::bigint FROM jsonb_array_elements(c10_demo.read_engines_v1(1)->'engines'->0->'assignments') i WHERE i->>'business_id'='101'),'req045_site_pub','Republish A for site overrides');
 x:=c10_demo.set_engine_site_override_v1(1,101,1001,'{"threshold":40}',0,'req045_site_01','Showroom needs a higher level');
 IF x->>'status'<>'applied' OR x->>'version'<>'1' THEN RAISE EXCEPTION 'SITE_SET %',x; END IF;
 IF c10_demo.set_engine_site_override_v1(1,101,1001,'{"threshold":40}',0,'req045_site_01','Showroom needs a higher level')<>x THEN RAISE EXCEPTION 'SITE_REPLAY'; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.set_engine_site_override_v1(1,101,1001,'{"threshold":41}',0,'req045_site_st','Stale site override')$q$,'engine_stale_version');
 PERFORM public.t045_fail($q$SELECT c10_demo.set_engine_site_override_v1(1,101,1003,'{"threshold":41}',0,'req045_site_xs','Site of another business')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.set_engine_site_override_v1(1,101,2001,'{"threshold":41}',0,'req045_site_xt','Site of another tenant')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.set_engine_site_override_v1(1,101,1001,'{"formula":"x"}',1,'req045_site_bad','Invalid override param')$q$,'invalid_engine_request');
 -- showroom 1001 uses 40, factory 1002 falls back to the business value, other business unaffected
 x:=c10_demo.preview_site_engine_v1(1,101,1001,'{"on_hand":30}');
 IF x->>'outcome'<>'warn' OR (x->'effective'->>'threshold')<>'40' OR (x->>'site_override')<>'true' THEN RAISE EXCEPTION 'SITE_EVAL_1001 %',x; END IF;
 x:=c10_demo.preview_site_engine_v1(1,101,1002,'{"on_hand":30}');
 IF x->>'outcome'<>'allow' OR (x->>'site_override')<>'false' THEN RAISE EXCEPTION 'SITE_EVAL_1002 %',x; END IF;
 IF (c10_demo.read_business_engines_v1(101)->'items'->0->'site_overrides'->0->>'site_id')<>'1001' THEN RAISE EXCEPTION 'SITE_PROJECTION'; END IF;
 IF jsonb_array_length(c10_demo.read_business_engines_v1(102)->'items'->0->'site_overrides')<>0 THEN RAISE EXCEPTION 'B_SITE_LEAK'; END IF;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$
DECLARE x jsonb;
BEGIN
 x:=c10_demo.set_engine_site_override_v1(1,101,1002,'{"threshold":25}',0,'req045_site_bo','Business owner sets factory level');
 IF x->>'status'<>'applied' THEN RAISE EXCEPTION 'SITE_BO %',x; END IF;
 PERFORM public.t045_fail($q$SELECT c10_demo.set_engine_site_override_v1(1,102,1003,'{"threshold":1}',0,'req045_site_bo2','Cross business site override')$q$,'engine_denied');
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$BEGIN
 PERFORM public.t045_fail($q$SELECT c10_demo.set_engine_site_override_v1(1,101,1001,'{"threshold":1}',1,'req045_site_mg','Manager override denied')$q$,'engine_denied');
 PERFORM public.t045_fail($q$SELECT c10_demo.preview_site_engine_v1(1,101,1001,'{"on_hand":1}')$q$,'engine_denied');
END$$;
COMMIT;
-- ===== 8. Immutability, integrity and "no operational side effects" (superuser tamper attempts) =====
RESET ROLE;
DO $$
DECLARE b public.t045_baseline%ROWTYPE;
BEGIN
 BEGIN UPDATE c10_demo.micro_engine_versions_v1 SET descriptor='{"field":"on_hand","op":"lt","threshold":1,"outcome":"allow"}',descriptor_hash=md5('{"field":"on_hand","op":"lt","threshold":1,"outcome":"allow"}'::jsonb::text) WHERE engine_id=1 AND version=1;
  RAISE EXCEPTION 'VERSION_TAMPER_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='VERSION_TAMPER_ALLOWED' THEN RAISE; END IF; END;
 BEGIN DELETE FROM c10_demo.micro_engine_versions_v1 WHERE engine_id=1 AND version=1;
  RAISE EXCEPTION 'VERSION_DELETE_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='VERSION_DELETE_ALLOWED' THEN RAISE; END IF; END;
 BEGIN UPDATE c10_demo.micro_engine_audit_v1 SET event='engine_created';
  RAISE EXCEPTION 'AUDIT_UPDATE_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='AUDIT_UPDATE_ALLOWED' THEN RAISE; END IF; END;
 BEGIN DELETE FROM c10_demo.micro_engine_audit_v1;
  RAISE EXCEPTION 'AUDIT_DELETE_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='AUDIT_DELETE_ALLOWED' THEN RAISE; END IF; END;
 BEGIN TRUNCATE c10_demo.micro_engine_audit_v1;
  RAISE EXCEPTION 'AUDIT_TRUNCATE_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='AUDIT_TRUNCATE_ALLOWED' THEN RAISE; END IF; END;
 BEGIN TRUNCATE c10_demo.micro_engine_versions_v1 CASCADE;
  RAISE EXCEPTION 'VERSION_TRUNCATE_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='VERSION_TRUNCATE_ALLOWED' THEN RAISE; END IF; END;
 BEGIN INSERT INTO c10_demo.micro_engine_versions_v1(engine_id,tenant_id,version,descriptor,descriptor_hash,created_by)
   VALUES(1,1,99,'{"a":1}','not-the-hash',gen_random_uuid());
  RAISE EXCEPTION 'HASH_MISMATCH_ALLOWED'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='HASH_MISMATCH_ALLOWED' THEN RAISE; END IF; END;
 IF (SELECT descriptor_hash FROM c10_demo.micro_engine_versions_v1 WHERE engine_id=1 AND version=1)<>
    md5('{"field":"on_hand","op":"lt","message":"Stock below advisory level","outcome":"warn","threshold":12}'::jsonb::text)
 THEN RAISE EXCEPTION 'V1_CHANGED'; END IF;
 SELECT * INTO b FROM public.t045_baseline;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>b.mv OR (SELECT count(*) FROM c10_demo.stock_summary)<>b.ss OR (SELECT count(*) FROM c10_demo.items)<>b.it
 THEN RAISE EXCEPTION 'OPERATIONAL_TABLES_TOUCHED'; END IF;
 IF NOT has_function_privilege('authenticated','c10_demo.read_business_engines_v1(bigint)','EXECUTE')
    OR has_function_privilege('anon','c10_demo.read_business_engines_v1(bigint)','EXECUTE')
    OR has_function_privilege('authenticated','c10_demo.engine_owner_lock_v1(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'GRANT_SURFACE_WRONG'; END IF;
 IF has_table_privilege('authenticated','c10_demo.micro_engines_v1','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('authenticated','c10_demo.micro_engine_audit_v1','INSERT') THEN RAISE EXCEPTION 'TABLE_GRANT_LEAK'; END IF;
END$$;
SELECT 'C10_A045_SQL_E2E_PASS' AS result;
