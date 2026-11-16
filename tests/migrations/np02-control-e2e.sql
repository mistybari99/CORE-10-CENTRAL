-- NP02 / B-010: Owner Control port end-to-end security and behaviour test (DEC-08).
-- Synthetic tenants, identities and settings only. One transaction, rolled back at the end.
-- Personas: OWN tenant owner A, BO business owner, MGR manager, INV investor (no operational access), STF site-granted staff,
-- OUT tenant owner B (foreign), NON signed-in user with no access, EXP business owner whose access expired.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (901,'np02-a'),(902,'np02-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9001,901,'Demo A'),(9002,902,'Demo B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9101,901,9001,'np02-sweets','sweets_bakery','seed-np02-a'),
        (9102,902,9002,'np02-other','restaurant','seed-np02-b');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 VALUES (9201,901,9101,'showroom','Showroom','seed-np02-s1'),
        (9202,901,9101,'factory','Factory','seed-np02-s2'),
        (9203,902,9102,'showroom','Other showroom','seed-np02-s3');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (901,'91111111-1111-4111-8111-111111111111','tenant_owner'),
 (902,'96666666-6666-4666-8666-666666666666','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (901,9101,'92222222-2222-4222-8222-222222222222','business_owner'),
 (901,9101,'93333333-3333-4333-8333-333333333333','manager'),
 (901,9101,'94444444-4444-4444-8444-444444444444','investor');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,valid_until)
 VALUES (901,9101,'98888888-8888-4888-8888-888888888888','business_owner',now()-interval '1 day');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions)
 VALUES (901,9101,9201,'95555555-5555-4555-8555-555555555555',ARRAY['stock.read']);

CREATE SCHEMA t_c10;
GRANT USAGE ON SCHEMA t_c10 TO authenticated, anon;
CREATE FUNCTION t_c10.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims', json_build_object('sub',p)::text, true),
        set_config('request.jwt.claim.sub', p, true) $$;
CREATE FUNCTION t_c10.as_anon() RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims','{}',true), set_config('request.jwt.claim.sub','',true) $$;
CREATE FUNCTION t_c10.expect(p_sql text, p_err text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql;
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE p_err || '%' THEN RETURN; END IF;
  RAISE EXCEPTION 'WRONG_ERROR expected [%] got [%] for %', p_err, SQLERRM, left(p_sql,90);
 END;
 RAISE EXCEPTION 'NO_ERROR expected [%] for %', p_err, left(p_sql,90);
END $$;
CREATE FUNCTION t_c10.ok(p boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED: %', p_msg; END IF; END $$;
CREATE FUNCTION t_c10.cset(p_business bigint,p_site bigint,p_feature text,p_enabled boolean,p_stages int,
 p_params jsonb,p_eff timestamptz,p_inherit boolean,p_exp int,p_reason text,p_key text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT core10.control_set_v1(p_business,p_site,p_feature,p_enabled,p_stages::smallint,
 p_params,p_eff,p_inherit,p_exp,p_reason,p_key) $$;
CREATE FUNCTION t_c10.eff(p_business bigint,p_feature text,p_site bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE sql AS $$ SELECT x FROM jsonb_array_elements(core10.control_read_v1(p_business,p_site)) x
 WHERE x->>'feature_key'=p_feature $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t_c10 TO authenticated, anon;
-- A stand-in feature RPC: any real pack RPC calls control_check_v1 exactly like this.
CREATE FUNCTION core10._t_controlled_action(p_business bigint,p_site bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN RETURN core10.control_check_v1(p_business,'gov002.review',p_site); END $$;
GRANT EXECUTE ON FUNCTION core10._t_controlled_action(bigint,bigint) TO authenticated, anon;

SET LOCAL ROLE authenticated;

-- 1. Owner reads the catalog and sets controls -------------------------------------------------
SELECT t_c10.as_user('91111111-1111-4111-8111-111111111111');
DO $t$
DECLARE r jsonb; v jsonb;
BEGIN
 r := core10.control_read_v1(9101);
 PERFORM t_c10.ok(jsonb_array_length(r)=9, 'catalog has 9 features');
 PERFORM t_c10.ok((SELECT bool_and((x->>'source')='default') FROM jsonb_array_elements(r) x), 'all default at start');
 PERFORM t_c10.ok((t_c10.eff(9101,'audit.immutability')->>'enabled')::boolean, 'invariant on');
 PERFORM t_c10.ok(NOT (t_c10.eff(9101,'gov003.review_export')->>'enabled')::boolean, 'export default off');
 PERFORM t_c10.ok((t_c10.eff(9101,'gov002.review')->>'stages')::int=1, 'review default 1 stage');

 v := t_c10.cset(9101,NULL,'gov002.review',false,1,'{}',NULL,false,0,'Owner pauses review','np02_key_0001');
 PERFORM t_c10.ok((v->>'version')::int=1 AND NOT (v->>'replayed')::boolean, 'first version');
 PERFORM t_c10.ok(NOT (t_c10.eff(9101,'gov002.review')->>'enabled')::boolean
   AND t_c10.eff(9101,'gov002.review')->>'source'='business', 'business setting effective');
 v := t_c10.cset(9101,NULL,'gov002.review',false,1,'{}',NULL,false,0,'Owner pauses review','np02_key_0001');
 PERFORM t_c10.ok((v->>'replayed')::boolean AND (v->>'version')::int=1, 'exact replay returns same version');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,2,'{}',NULL,false,0,'different payload','np02_key_0001')$q$,'CONTROL_REPLAY_CONFLICT');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,2,'{}',NULL,false,0,'stale expected version','np02_key_0002')$q$,'CONTROL_STALE_VERSION:1');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,2,'{}',NULL,false,1,'x','np02_key_0003')$q$,'CONTROL_BAD_REASON');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,2,'{}',NULL,false,1,'valid reason','short')$q$,'CONTROL_BAD_KEY');
END $t$;

-- 2. Parameter, stage, scope and date validation ---------------------------------------------------
DO $t$
BEGIN
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{"max_rows":20000}',NULL,false,0,'too many rows','np02_key_0010')$q$,'CONTROL_PARAM_RANGE:max_rows');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{"max_rows":"many"}',NULL,false,0,'wrong type text','np02_key_0011')$q$,'CONTROL_PARAM_TYPE:max_rows');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{"max_rows":10.5}',NULL,false,0,'fraction for int','np02_key_0012')$q$,'CONTROL_PARAM_TYPE:max_rows');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{"zzz":1}',NULL,false,0,'unknown parameter','np02_key_0013')$q$,'CONTROL_PARAM_UNKNOWN:zzz');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{"metadata_only":"yes"}',NULL,false,0,'wrong bool type','np02_key_0014')$q$,'CONTROL_PARAM_TYPE:metadata_only');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'[1]',NULL,false,0,'params not an object','np02_key_0015')$q$,'CONTROL_PARAMS_SHAPE');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.approval_policy',true,1,'{}',NULL,false,0,'more stages than allowed','np02_key_0016')$q$,'CONTROL_STAGES');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,6,'{}',NULL,false,1,'six stages','np02_key_0017')$q$,'CONTROL_STAGES');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'audit.immutability',false,0,'{}',NULL,false,0,'try to disable audit','np02_key_0018')$q$,'CONTROL_INVARIANT');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'tenant.isolation',false,0,'{}',NULL,false,0,'try to disable isolation','np02_key_0019')$q$,'CONTROL_INVARIANT');
 PERFORM t_c10.expect($q$SELECT core10.control_grant_override_v1(9101,NULL,'audit.immutability',2,'bypass attempt','np02_ovr_0001')$q$,'CONTROL_INVARIANT');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'no.such_feature',true,0,'{}',NULL,false,0,'unknown feature','np02_key_0020')$q$,'CONTROL_UNKNOWN_FEATURE');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,9203,'gov002.review',true,1,'{}',NULL,false,0,'site of another business','np02_key_0021')$q$,'CONTROL_SCOPE');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,1,'{}',NULL,true,1,'inherit needs a site','np02_key_0022')$q$,'CONTROL_INHERIT_SCOPE');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{}',now()-interval '10 minutes',false,0,'back-dated change','np02_key_0023')$q$,'CONTROL_EFFECTIVE_PAST');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{}',now()+interval '400 days',false,0,'too far ahead','np02_key_0024')$q$,'CONTROL_EFFECTIVE_FUTURE');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9101,NULL,'setup001.profile_preview',true,1,'{}',NULL,false,0,'stages on a read-only control','np02_key_0025')$q$,'CONTROL_STAGES');
END $t$;

-- 3. Site override, inherit, scheduled change, revert, history --------------------------------------
DO $t$
DECLARE v jsonb; h jsonb;
BEGIN
 v := t_c10.cset(9101,9201,'gov002.review',true,3,'{"exception_escalation":false}',NULL,false,0,'Showroom keeps 3 stages','np02_key_0030');
 PERFORM t_c10.ok((v->>'version')::int=1, 'site version 1');
 PERFORM t_c10.ok((t_c10.eff(9101,'gov002.review',9201)->>'enabled')::boolean
   AND (t_c10.eff(9101,'gov002.review',9201)->>'stages')::int=3
   AND t_c10.eff(9101,'gov002.review',9201)->>'source'='site', 'site override wins at its site');
 PERFORM t_c10.ok(NOT (t_c10.eff(9101,'gov002.review',9202)->>'enabled')::boolean
   AND t_c10.eff(9101,'gov002.review',9202)->>'source'='business', 'other site falls back to business');
 v := t_c10.cset(9101,9201,'gov002.review',NULL,NULL,NULL,NULL,true,1,'Showroom follows business again','np02_key_0031');
 PERFORM t_c10.ok(NOT (t_c10.eff(9101,'gov002.review',9201)->>'enabled')::boolean
   AND t_c10.eff(9101,'gov002.review',9201)->>'source'='business', 'inherit returns to business setting');

 v := t_c10.cset(9101,NULL,'gov003.review_export',true,0,'{"max_rows":500}',now()+interval '1 hour',false,0,'Switch export on from tomorrow morning','np02_key_0032');
 PERFORM t_c10.ok(NOT (t_c10.eff(9101,'gov003.review_export')->>'enabled')::boolean
   AND (t_c10.eff(9101,'gov003.review_export')->>'version')::int=0, 'scheduled change not yet effective');
 PERFORM t_c10.ok((t_c10.eff(9101,'gov003.review_export')->'scheduled'->>'version')::int=1, 'scheduled change is visible');

 v := t_c10.cset(9101,NULL,'gov002.review',true,2,'{}',NULL,false,1,'Owner resumes review with two stages','np02_key_0033');
 PERFORM t_c10.ok((v->>'version')::int=2 AND (t_c10.eff(9101,'gov002.review')->>'enabled')::boolean, 'version 2 effective');
 PERFORM t_c10.expect($q$SELECT core10.control_revert_v1(9101,NULL,'gov002.review',9,2,'revert to nothing','np02_key_0034')$q$,'CONTROL_NO_SUCH_VERSION');
 v := core10.control_revert_v1(9101,NULL,'gov002.review',1,2,'Owner restores the paused state','np02_key_0035');
 PERFORM t_c10.ok((v->>'version')::int=3 AND (v->>'reverted_from')::int=1 AND NOT (v->>'enabled')::boolean, 'revert is a new version');
 PERFORM t_c10.ok(NOT (t_c10.eff(9101,'gov002.review')->>'enabled')::boolean, 'reverted state effective');

 h := core10.control_history_v1(9101,'gov002.review',50);
 PERFORM t_c10.ok(jsonb_array_length(h)=5 AND (h->0->>'version')::int=3 AND (h->0->>'reverted_from')::int=1, 'history newest first');
 PERFORM t_c10.ok((SELECT bool_and((x->>'audit_event_id') IS NOT NULL) FROM jsonb_array_elements(h) x), 'every version has an audit event');
END $t$;

-- 4. Server-side enforcement and one-time Owner exceptions -----------------------------------------
SELECT t_c10.as_user('93333333-3333-4333-8333-333333333333');
DO $t$
DECLARE r jsonb; o jsonb;
BEGIN
 PERFORM t_c10.expect($q$SELECT core10._t_controlled_action(9101,NULL)$q$,'CONTROL_DISABLED:gov002.review');
 PERFORM t_c10.expect($q$SELECT core10._t_controlled_action(9101,9201)$q$,'CONTROL_DISABLED:gov002.review');
 r := core10.control_approval_binding_v1(9101,'gov002.review');
 PERFORM t_c10.ok(NOT (r->>'enabled')::boolean AND (r->>'stages')::int=1, 'approval binding readable by a member');
 r := core10.control_approval_binding_v1(9101,'inventory.stock_event');
 PERFORM t_c10.ok((r->>'enabled')::boolean AND r->>'approval_domain'='inventory' AND r->>'approval_action'='adjust', 'binding exposes the policy key');
END $t$;
SELECT t_c10.as_user('91111111-1111-4111-8111-111111111111');
DO $t$
DECLARE o jsonb; v jsonb;
BEGIN
 v := t_c10.cset(9101,9201,'gov002.review',true,2,'{}',NULL,false,2,'Showroom runs review again','np02_key_0040');
 PERFORM t_c10.ok((v->>'version')::int=3, 'site version 3 after inherit');
 o := core10.control_grant_override_v1(9101,NULL,'gov002.review',24,'Urgent approval during audit','np02_ovr_0002');
 PERFORM t_c10.ok((o->>'override_id') IS NOT NULL AND NOT (o->>'replayed')::boolean, 'override granted');
 o := core10.control_grant_override_v1(9101,NULL,'gov002.review',24,'Urgent approval during audit','np02_ovr_0002');
 PERFORM t_c10.ok((o->>'replayed')::boolean, 'override grant replay');
 PERFORM t_c10.expect($q$SELECT core10.control_grant_override_v1(9101,NULL,'gov002.review',24,'Different reason here','np02_ovr_0002')$q$,'CONTROL_REPLAY_CONFLICT');
 PERFORM t_c10.expect($q$SELECT core10.control_grant_override_v1(9101,NULL,'gov002.review',500,'too long a window','np02_ovr_0003')$q$,'CONTROL_BAD_HOURS');
END $t$;
SELECT t_c10.as_user('93333333-3333-4333-8333-333333333333');
DO $t$
DECLARE r jsonb;
BEGIN
 PERFORM t_c10.ok((core10._t_controlled_action(9101,9201)->>'enabled')::boolean
  AND NOT (core10._t_controlled_action(9101,9201)->>'override_used')::boolean, 'site-level setting allows the action');
 r := core10._t_controlled_action(9101,NULL);
 PERFORM t_c10.ok((r->>'override_used')::boolean, 'one-time exception allows exactly one action');
 PERFORM t_c10.expect($q$SELECT core10._t_controlled_action(9101,NULL)$q$,'CONTROL_DISABLED:gov002.review');
END $t$;
SELECT t_c10.as_user('91111111-1111-4111-8111-111111111111');
DO $t$
DECLARE o jsonb; l jsonb;
BEGIN
 o := core10.control_grant_override_v1(9101,NULL,'gov002.review',2,'Second urgent exception','np02_ovr_0004');
 PERFORM t_c10.ok((core10.control_revoke_override_v1(9101,(o->>'override_id')::bigint,'Not needed any more','np02_rev_0001')->>'ok')::boolean, 'revoke');
 PERFORM t_c10.ok((core10.control_revoke_override_v1(9101,(o->>'override_id')::bigint,'Not needed any more','np02_rev_0001')->>'replayed')::boolean, 'revoke replay');
 PERFORM t_c10.expect(format($q$SELECT core10.control_revoke_override_v1(9101,%s,'Revoke again with new key','np02_rev_0002')$q$,o->>'override_id'),'CONTROL_OVERRIDE_CLOSED');
 o := core10.control_grant_override_v1(9101,9201,'gov002.review',2,'Site scoped exception only','np02_ovr_0005');
 l := core10.control_overrides_v1(9101);
 PERFORM t_c10.ok(jsonb_array_length(l)=3, 'three exceptions listed');
 PERFORM t_c10.ok((SELECT count(*) FROM jsonb_array_elements(l) x WHERE x->>'status'='consumed')=1
   AND (SELECT count(*) FROM jsonb_array_elements(l) x WHERE x->>'status'='revoked')=1
   AND (SELECT count(*) FROM jsonb_array_elements(l) x WHERE x->>'status'='open')=1, 'exception states');
END $t$;
SELECT t_c10.as_user('93333333-3333-4333-8333-333333333333');
DO $t$
BEGIN
 PERFORM t_c10.expect($q$SELECT core10._t_controlled_action(9101,NULL)$q$,'CONTROL_DISABLED:gov002.review');
END $t$;
-- expired exception cannot be used (time moved by the table owner, then restored by rollback)
RESET ROLE;
ALTER TABLE core10.control_overrides_v1 DISABLE TRIGGER control_overrides_guard_v1;
UPDATE core10.control_overrides_v1 SET granted_at = now()-interval '3 hours', expires_at = now()-interval '1 hour'
 WHERE site_id=9201 AND consumed_at IS NULL AND revoked_at IS NULL;
ALTER TABLE core10.control_overrides_v1 ENABLE TRIGGER control_overrides_guard_v1;
SET LOCAL ROLE authenticated;
SELECT t_c10.as_user('91111111-1111-4111-8111-111111111111');
DO $t$
BEGIN
 PERFORM t_c10.ok((SELECT x->>'status' FROM jsonb_array_elements(core10.control_overrides_v1(9101)) x
   WHERE (x->>'site_id') IS NOT NULL)='expired', 'expired state shown');
END $t$;

-- 5. Who may do what: role matrix ---------------------------------------------------------------
DO $t$
DECLARE u text; sqls text[] := ARRAY[
 $q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,1,'{}',NULL,false,3,'matrix change attempt','np02_mx_set_0')$q$,
 $q$SELECT core10.control_revert_v1(9101,NULL,'gov002.review',1,3,'matrix revert attempt','np02_mx_rev_0')$q$,
 $q$SELECT core10.control_grant_override_v1(9101,NULL,'gov002.review',2,'matrix grant attempt','np02_mx_ovr_0')$q$,
 $q$SELECT core10.control_history_v1(9101)$q$,
 $q$SELECT core10.control_overrides_v1(9101)$q$];
 i int;
BEGIN
 sqls[1] := $q$SELECT t_c10.cset(9101,NULL,'gov002.review',true,1,'{}',NULL,false,3,'matrix change attempt','np02_mx_set_0')$q$;
 FOREACH u IN ARRAY ARRAY['93333333-3333-4333-8333-333333333333','95555555-5555-4555-8555-555555555555'] LOOP
  PERFORM t_c10.as_user(u);
  FOR i IN 1..5 LOOP PERFORM t_c10.expect(sqls[i],'CONTROL_FORBIDDEN'); END LOOP;
  PERFORM t_c10.ok(jsonb_array_length(core10.control_read_v1(9101))=9, 'members may read');
 END LOOP;
 -- an investor has no operational access in the Auth port, so the Control port shows them nothing
 FOREACH u IN ARRAY ARRAY['94444444-4444-4444-8444-444444444444','96666666-6666-4666-8666-666666666666','97777777-7777-4777-8777-777777777777'] LOOP
  PERFORM t_c10.as_user(u);
  FOR i IN 1..5 LOOP PERFORM t_c10.expect(sqls[i],'CONTROL_SCOPE'); END LOOP;
  PERFORM t_c10.expect($q$SELECT core10.control_read_v1(9101)$q$,'CONTROL_SCOPE');
  PERFORM t_c10.expect($q$SELECT core10.control_approval_binding_v1(9101,'gov002.review')$q$,'CONTROL_SCOPE');
  PERFORM t_c10.expect($q$SELECT core10._t_controlled_action(9101,NULL)$q$,'CONTROL_SCOPE');
 END LOOP;
 -- expired access is denied like no access
 PERFORM t_c10.as_user('98888888-8888-4888-8888-888888888888');
 FOR i IN 1..5 LOOP PERFORM t_c10.expect(sqls[i],'CONTROL_'); END LOOP;
 PERFORM t_c10.expect($q$SELECT core10.control_read_v1(9101)$q$,'CONTROL_SCOPE');
 -- no sign-in at all
 PERFORM t_c10.as_anon();
 FOR i IN 1..5 LOOP PERFORM t_c10.expect(sqls[i],'CONTROL_SCOPE'); END LOOP;
 PERFORM t_c10.expect($q$SELECT core10._t_controlled_action(9101,NULL)$q$,'CONTROL_UNAUTHENTICATED');
 -- a forged role claim changes nothing
 PERFORM set_config('request.jwt.claims','{"sub":"93333333-3333-4333-8333-333333333333","app_metadata":{"role":"tenant_owner"},"role":"service_role"}',true);
 PERFORM t_c10.expect(sqls[1],'CONTROL_FORBIDDEN');
END $t$;
-- business owner may write, only in their own business
SELECT t_c10.as_user('92222222-2222-4222-8222-222222222222');
DO $t$
DECLARE v jsonb;
BEGIN
 v := t_c10.cset(9101,NULL,'setup001.provision',true,1,'{"max_sites":20}',NULL,false,0,'Business owner requires one approval','np02_key_0050');
 PERFORM t_c10.ok((v->>'version')::int=1 AND (v->>'stages')::int=1, 'business owner writes');
 PERFORM t_c10.expect($q$SELECT t_c10.cset(9102,NULL,'setup001.provision',true,1,'{}',NULL,false,0,'other business','np02_key_0051')$q$,'CONTROL_SCOPE');
END $t$;
-- tenant B owner writes their own business and does not touch tenant A
SELECT t_c10.as_user('96666666-6666-4666-8666-666666666666');
DO $t$
BEGIN
 PERFORM t_c10.cset(9102,NULL,'gov002.review',false,1,'{}',NULL,false,0,'Tenant B pauses review','np02_key_0060');
 PERFORM t_c10.ok(NOT (t_c10.eff(9102,'gov002.review')->>'enabled')::boolean, 'tenant B setting');
 PERFORM t_c10.expect($q$SELECT core10.control_history_v1(9101)$q$,'CONTROL_SCOPE');
END $t$;
SELECT t_c10.as_user('91111111-1111-4111-8111-111111111111');
DO $t$
BEGIN
 PERFORM t_c10.ok((t_c10.eff(9101,'gov002.review')->>'version')::int=3, 'tenant A history untouched by tenant B');
END $t$;

-- 6. Tables are closed; internal functions are not callable; history cannot be altered ---------------
DO $t$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['control_catalog_v1','control_setting_versions_v1','control_overrides_v1','control_rpc_map_v1'] LOOP
  PERFORM t_c10.expect(format('SELECT count(*) FROM core10.%I',t),'permission denied');
  PERFORM t_c10.expect(format('DELETE FROM core10.%I',t),'permission denied');
 END LOOP;
 PERFORM t_c10.expect($q$SELECT core10.control_check_v1(9101,'gov002.review',NULL)$q$,'permission denied');
 PERFORM t_c10.expect($q$SELECT core10._control_resolve_v1(9101,'gov002.review',NULL)$q$,'permission denied');
 PERFORM t_c10.expect($q$SELECT core10._control_write_v1(901,9101,NULL,'gov002.review',true,1::smallint,'{}',NULL,false,3,'direct internal call','np02_key_0070',NULL)$q$,'permission denied');
 PERFORM t_c10.as_anon();
 PERFORM t_c10.expect($q$SELECT core10.control_read_v1(9101)$q$,'CONTROL_SCOPE');
END $t$;
RESET ROLE;
DO $t$
BEGIN
 PERFORM t_c10.expect($q$UPDATE core10.control_setting_versions_v1 SET enabled = NOT enabled$q$,'control_history_immutable');
 PERFORM t_c10.expect($q$DELETE FROM core10.control_setting_versions_v1$q$,'control_history_immutable');
 PERFORM t_c10.expect($q$TRUNCATE core10.control_setting_versions_v1 CASCADE$q$,'control_history_immutable');
 PERFORM t_c10.expect($q$TRUNCATE core10.control_overrides_v1 CASCADE$q$,'control_history_immutable');
 PERFORM t_c10.expect($q$DELETE FROM core10.control_overrides_v1$q$,'control_history_immutable');
 PERFORM t_c10.expect($q$UPDATE core10.control_overrides_v1 SET expires_at = expires_at + interval '1 day'$q$,'control_history_immutable');
 PERFORM t_c10.expect($q$UPDATE core10.control_overrides_v1 SET consumed_at = now(), consumed_by = granted_by WHERE consumed_at IS NOT NULL$q$,'control_history_immutable');
 PERFORM t_c10.ok(NOT has_function_privilege('anon','core10.control_set_v1(bigint,bigint,text,boolean,smallint,jsonb,timestamptz,boolean,integer,text,text)','execute'), 'anon cannot set');
 PERFORM t_c10.ok(NOT has_function_privilege('authenticated','core10.control_check_v1(bigint,text,bigint)','execute'), 'api roles cannot call the internal check');
 PERFORM t_c10.ok((SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='core10' AND c.relname LIKE 'control\_%' AND c.relkind='r' AND NOT c.relrowsecurity)=0, 'RLS on all control tables');
END $t$;

-- 7. Audit: every change and exception is in the one canonical tamper-evident stream -------------------
DO $t$
DECLARE n_ver int; n_evt int; v jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"91111111-1111-4111-8111-111111111111"}',true);
 PERFORM set_config('request.jwt.claim.sub','91111111-1111-4111-8111-111111111111',true);
 SELECT count(*) INTO n_ver FROM core10.control_setting_versions_v1 WHERE business_id=9101;
 SELECT count(*) INTO n_evt FROM core10.canonical_audit_events_v1 WHERE business_id=9101 AND action='control.setting_changed';
 PERFORM t_c10.ok(n_ver=n_evt AND n_ver>=8, format('one audit event per version (%s/%s)',n_ver,n_evt));
 PERFORM t_c10.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9101 AND action='control.override_granted')=3, 'grants audited');
 PERFORM t_c10.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9101 AND action='control.override_consumed')=1, 'consumption audited');
 PERFORM t_c10.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9101 AND action='control.override_revoked')=1, 'revocation audited');
 v := core10.verify_canonical_audit_v1(9101);
 PERFORM t_c10.ok((v->>'ok')::boolean, 'audit hash chain verifies');
 RAISE NOTICE 'PASS NP02 Owner Control: % versions, 8 personas, params/stages/scope/date validation, site override and inherit, scheduled change, revert, history, one-time exceptions, server enforcement, closed tables, immutable history, audit chain ok', n_ver;
END $t$;
ROLLBACK;
