-- C10-A053 e2e: persona registry, staff identity link, Owner Portfolio -> Workforce adapter. Run AFTER tests/c10_a054_policy_e2e.sql on the full stack
-- (business 102 has a frozen October 2026 run with recorded external payments). Signed-claim SIMULATION, NOT GoTrue.
\set ON_ERROR_STOP on
\ir c10_a053_a054_helpers.sql
-- ===== registry: 16 A046 personas + fixture-only aliases, append-only, fail-closed =====
DO $$ BEGIN
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.a053_persona_registry WHERE source='A046_REGISTRY'$s$),'16','all 16 A046 personas registered');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.a053_persona_registry WHERE source='A051_FIXTURE_ONLY'$s$),'9','A051-only fixture identities are separate aliases');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.a053_a051_alias_map$s$),'18','every A051 short name mapped');
 PERFORM c10_test.eq(c10_test.q($s$SELECT uid::text FROM c10_demo.a053_persona_registry WHERE alias_key='TENANT_OWNER_A'$s$),'11111111-1111-4111-8111-111111111111','TENANT_OWNER_A meaning unchanged');
 PERFORM c10_test.denied($q$UPDATE c10_demo.a053_persona_registry SET uid='00000000-0000-4000-8000-000000000001' WHERE alias_key='MANAGER_A'$q$,'a053_append_only_registry');
 PERFORM c10_test.denied($q$DELETE FROM c10_demo.a053_persona_registry$q$,'a053_append_only_registry');
 PERFORM c10_test.denied($q$UPDATE c10_demo.a053_a051_alias_map SET alias_key='TENANT_OWNER_B' WHERE a051_name='owner'$q$,'a053_append_only_registry');
 PERFORM c10_test.denied($q$INSERT INTO c10_demo.a053_persona_registry VALUES('DUP_UID','11111111-1111-4111-8111-111111111111','A051_FIXTURE_ONLY',NULL,1,'{}',true,true)$q$,'duplicate key');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053i_alias('NOT_A_PERSONA')$q$,'a053_alias_unmapped');
END $$;
-- ===== link / unlink identity =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; b2 bigint:=c10_test.eid(102,'B2'); b1 bigint:=c10_test.eid(102,'B1'); BEGIN
 PERFORM c10_test.as_user('mgrB'); PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-01',%s,'UNASSIGNED_USER','manager tries')$q$,b2),'a053_owner_required');
 PERFORM c10_test.as_user('branch'); PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-02',%s,'UNASSIGNED_USER','staff tries')$q$,b2),'a053_owner_required');
 PERFORM c10_test.as_user('ownerB'); PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-03',%s,'UNASSIGNED_USER','other tenant')$q$,b2),'wf_denied');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-04',%s,'GHOST_ALIAS','unknown')$q$,b2),'a053_alias_unmapped');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-05',%s,'PLATFORM_OPERATOR','operator')$q$,b2),'a053_alias_not_linkable');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-06',%s,'REVOKED_MANAGER_A','revoked')$q$,b2),'a053_alias_not_linkable');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-07',%s,'INVESTOR_A','investor')$q$,b2),'a053_alias_not_linkable');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-08',%s,'TENANT_OWNER_B','cross tenant')$q$,b2),'a053_alias_cross_tenant');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-09',%s,'COUNTER_STAFF_A','other business scope')$q$,b2),'a053_alias_scope_mismatch');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-10',%s,'BRANCH_STAFF_B','already linked person')$q$,b1),'a053_employee_already_linked');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-11',%s,'BRANCH_STAFF_B','same login twice')$q$,b2),'wf_user_already_linked');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-neg-12',999999,'UNASSIGNED_USER','no employee')$q$,'wf_employee_not_found');
 -- before the link the unassigned user has no workforce access at all
 PERFORM c10_test.as_user('unassigned'); PERFORM c10_test.denied($q$SELECT c10_demo.wf_my_payslips_v1(102)$q$,'wf_denied');
 PERFORM c10_test.as_user('boB');
 r:=c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-000001',b2,'UNASSIGNED_USER','link B2 login');
 PERFORM c10_test.eq(r->>'grants_workforce_access','self_service_only','link grants self-service only');
 PERFORM c10_test.eq(c10_demo.a053_link_staff_identity_v1(102,'a053-lnk-000001',b2,'UNASSIGNED_USER','link B2 login')::text,r::text,'replay');
 PERFORM c10_test.as_user('unassigned');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_payslips_v1(102)->'items')::text,'1','linked staff sees own payslip only');
 PERFORM c10_test.eq(c10_demo.a053_my_assignments_v1()->'items'->0->>'employee_no','B2','my assignment');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_get_payroll_run_v1(102,1)$q$,'wf_payroll_access_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'a054_liability_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_staff_overview_v1(102)$q$,'a053_manager_required');
 -- overview: owner sees aliases; manager sees masked names and no alias
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.eq((SELECT x->>'identity_alias' FROM jsonb_array_elements(c10_demo.a053_staff_overview_v1(102)->'items') x WHERE x->>'employee_no'='B2'),'UNASSIGNED_USER','owner sees alias');
 PERFORM c10_test.as_user('mgrB');
 PERFORM c10_test.eq((SELECT x->>'full_name' FROM jsonb_array_elements(c10_demo.a053_staff_overview_v1(102)->'items') x WHERE x->>'employee_no'='B1'),'Bela B.','manager sees masked name');
 PERFORM c10_test.eq((SELECT x->>'identity_alias' FROM jsonb_array_elements(c10_demo.a053_staff_overview_v1(102)->'items') x WHERE x->>'employee_no'='B1'),NULL,'manager sees no alias');
 PERFORM c10_test.eq((SELECT x->>'identity_linked' FROM jsonb_array_elements(c10_demo.a053_staff_overview_v1(102)->'items') x WHERE x->>'employee_no'='B1'),'true','manager sees link flag only');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a053_unlink_staff_identity_v1(102,'a053-unl-000001',b2,'login revoked by owner');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a053_unlink_staff_identity_v1(102,'a053-unl-000002',%s,'again')$q$,b2),'a053_employee_not_linked');
 PERFORM c10_test.as_user('unassigned'); PERFORM c10_test.denied($q$SELECT c10_demo.wf_my_payslips_v1(102)$q$,'wf_denied'); -- unlink is immediate
 PERFORM c10_test.as_user('owner'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.a053_persona_catalog_v1()->'items')::text,'21','tenant owner A sees tenant-1 + tenant-less aliases (not tenant 2)');
 PERFORM c10_test.as_user('mgrB'); PERFORM c10_test.denied($q$SELECT c10_demo.a053_persona_catalog_v1()$q$,'a053_owner_required');
END $$; COMMIT;
-- ===== Owner Portfolio -> Workforce adapter =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; e jsonb; BEGIN
 PERFORM c10_test.as_user('owner');
 r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(r->>'state','CONNECTED','connected'); PERFORM c10_test.eq(r->'contracts'->>'A051_workforce','CONNECTED','A051'); PERFORM c10_test.eq(r->'contracts'->>'A050_portfolio','CONNECTED','A050');
 PERFORM c10_test.eq(r->>'paid','false','paid false'); PERFORM c10_test.eq(r->>'ledger_posted','false','ledger false'); PERFORM c10_test.eq(r->>'money_movement','false','money false');
 PERFORM c10_test.eq(jsonb_array_length(r->'businesses')::text,'2','tenant 1 owner sees exactly tenant-1 businesses');
 e:=(SELECT x FROM jsonb_array_elements(r->'businesses') x WHERE (x->>'business_id')='102');
 PERFORM c10_test.eq(e->>'state','OK','102 ok'); PERFORM c10_test.eq(e->'workforce'->>'active_headcount','2','headcount'); PERFORM c10_test.eq(e->'workforce'->'headcount_by_site'->0->>'n','2','by site');
 PERFORM c10_test.eq(e->'liability'->>'state','approved_not_paid','A051 guard state'); PERFORM c10_test.eq(e->'liability'->>'net_approved_preview','60426.04','approved net');
 PERFORM c10_test.eq(e->'liability'->>'paid','false','paid false per business');
 PERFORM c10_test.eq(e->'liability'->'approved_unpaid'->>'total_outstanding','48926.04','outstanding shown separately from approved total');
 PERFORM c10_test.eq(e->'liability'->'approved_unpaid'->>'paid_recorded_amount','11500.00','recorded external payments shown separately');
 e:=(SELECT x FROM jsonb_array_elements(r->'businesses') x WHERE (x->>'business_id')='101');
 PERFORM c10_test.eq(e->>'state','OK','101 ok without runs'); PERFORM c10_test.eq(e->'liability'->>'state','no_approved_run','no run');
 PERFORM c10_test.eq(c10_demo.a053_read_portfolio_workforce_v1(NULL)->>'period',date_trunc('month',now() AT TIME ZONE 'Asia/Dhaka')::date::text,'default current month');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_read_portfolio_workforce_v1('2026-10-15')$q$,'a053_invalid_period');
 PERFORM c10_test.as_user('boB');
 r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(jsonb_array_length(r->'businesses')::text,'1','business owner sees only own business'); PERFORM c10_test.eq(r->'businesses'->0->>'state','OK','own business ok');
 PERFORM c10_test.as_user('mgrB');
 r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(r->'businesses'->0->>'state','OWNER_ONLY','manager gets owner-only');
 PERFORM c10_test.eq((r::text ~ '(60426|48926|33854|headcount_by_site)')::text,'false','no salary or headcount figures leak to manager');
 PERFORM c10_test.as_user('counter'); r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(r->'businesses'->0->>'state','OWNER_ONLY','site staff owner-only');
 PERFORM c10_test.eq((r::text ~ '(60426|workforce":\{)')::text,'false','no figures to staff');
 PERFORM c10_test.as_user('investor'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.a053_read_portfolio_workforce_v1('2026-10-01')->'businesses')::text,'0','investor sees nothing');
 PERFORM c10_test.as_user('revoked'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.a053_read_portfolio_workforce_v1('2026-10-01')->'businesses')::text,'0','revoked sees nothing');
 PERFORM c10_test.as_user('operator'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.a053_read_portfolio_workforce_v1('2026-10-01')->'businesses')::text,'0','operator sees nothing');
 PERFORM c10_test.as_user('ownerB'); r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(jsonb_array_length(r->'businesses')::text,'1','tenant B owner sees only own business'); PERFORM c10_test.eq(r->'businesses'->0->>'business_id','201','business 201');
 PERFORM c10_test.eq((r::text ~ '(60426|"business_id": ?(101|102))')::text,'false','no cross-tenant figures');
 PERFORM c10_test.as_user('unassigned'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.a053_read_portfolio_workforce_v1('2026-10-01')->'businesses')::text,'0','unassigned sees nothing');
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_read_portfolio_workforce_v1(NULL)$q$,'a053_signed_user_required');
END $$; COMMIT;
-- ===== contract violation: a guard answering for the wrong business / a month / money flag is rejected, never displayed =====
BEGIN;
CREATE OR REPLACE FUNCTION c10_demo.read_workforce_business_summary_v1(p_business bigint,p_period date) RETURNS jsonb LANGUAGE sql AS
$$ SELECT jsonb_build_object('business_id',p_business+1,'period',p_period,'active_headcount',1,'headcount_by_site','[{"site_id":1,"n":1}]'::jsonb,'paid',false,'ledger_posted',false,'money_movement',false) $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('boB');
 r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(r->'businesses'->0->>'state','CONTRACT_VIOLATION','wrong business id rejected');
 PERFORM c10_test.eq(r->'businesses'->0->>'violation','business_mismatch','reason'); PERFORM c10_test.eq(r->'businesses'->0->>'workforce',NULL,'no figures');
END $$; ROLLBACK;
BEGIN;
CREATE OR REPLACE FUNCTION c10_demo.read_payroll_liability_preview_v1(p_business bigint,p_period date) RETURNS jsonb LANGUAGE sql AS
$$ SELECT jsonb_build_object('business_id',p_business,'period',p_period,'state','approved_not_paid','paid',true,'ledger_posted',false,'money_movement',false) $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('boB');
 r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(r->'businesses'->0->>'violation','money_flags','paid:true from a guard is rejected'); END $$; ROLLBACK;
SELECT 'A053_SQL_E2E_PASS' AS result;
