-- Build 01: connect existing A018/A020/A034 setup and access authority.
-- Disposable c10_demo candidate ONLY; not a hosted/production migration.
-- Original membership, site, setup and access-event records remain canonical.
DO $guard$ BEGIN
 IF current_database() !~ '^core10_(build01|build02a|a[0-9]+|preview)' OR
    to_regclass('c10_demo.access_change_events_v1') IS NULL OR
    to_regclass('c10_demo.industry_catalog_v2') IS NULL THEN
  RAISE EXCEPTION 'BUILD01_DISPOSABLE_A018_A020_A034_REQUIRED';
 END IF;
END $guard$;

ALTER TABLE c10_demo.business_members ADD COLUMN valid_until timestamptz;
ALTER TABLE c10_demo.business_members ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK(version>0);
ALTER TABLE c10_demo.site_grants ADD COLUMN valid_until timestamptz;
ALTER TABLE c10_demo.site_grants ADD COLUMN denied_actions text[] NOT NULL DEFAULT '{}'
 CHECK(denied_actions <@ ARRAY['stock.read','stock.post']::text[]);
ALTER TABLE c10_demo.site_grants ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK(version>0);
ALTER TABLE c10_demo.access_change_events_v1 ADD COLUMN event_kind text NOT NULL DEFAULT 'base.access'
 CHECK(event_kind IN('base.access','policy.apply','setup.business','setup.site'));
ALTER TABLE c10_demo.access_change_events_v1 DROP CONSTRAINT access_change_events_v1_command_check;
ALTER TABLE c10_demo.access_change_events_v1 ADD CONSTRAINT access_change_events_v1_command_check
 CHECK(command IN('business_member.grant','business_member.revoke','site_grant.grant','site_grant.revoke','setup.business','setup.site'));

CREATE FUNCTION c10_demo.build01_bump_version_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN NEW.version:=OLD.version+1; RETURN NEW; END $$;
CREATE TRIGGER build01_membership_version BEFORE UPDATE ON c10_demo.business_members
 FOR EACH ROW EXECUTE FUNCTION c10_demo.build01_bump_version_v1();
CREATE TRIGGER build01_site_grant_version BEFORE UPDATE ON c10_demo.site_grants
 FOR EACH ROW EXECUTE FUNCTION c10_demo.build01_bump_version_v1();
CREATE FUNCTION c10_demo.build01_immutable_access_event_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN RAISE EXCEPTION 'BUILD01_AUDIT_IMMUTABLE'; END $$;
CREATE TRIGGER build01_access_audit_append_only BEFORE UPDATE OR DELETE ON c10_demo.access_change_events_v1
 FOR EACH ROW EXECUTE FUNCTION c10_demo.build01_immutable_access_event_v1();
REVOKE ALL ON FUNCTION c10_demo.build01_bump_version_v1(),c10_demo.build01_immutable_access_event_v1() FROM PUBLIC,authenticated;

-- With actual GoTrue tables, a signed access token is insufficient after logout:
-- its session must still exist and belong to the token's subject. In the plain
-- disposable fixtures no auth schema exists; those tests remain synthetic claims.
CREATE OR REPLACE FUNCTION c10_demo.actor_uid() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE claims jsonb; uid uuid; sid uuid; valid_session boolean;
BEGIN
 claims:=COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
 BEGIN
  uid:=COALESCE(NULLIF(claims->>'sub',''),NULLIF(current_setting('request.jwt.claim.sub',true),''))::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RETURN NULL; END;
 IF uid IS NULL THEN RETURN NULL; END IF;
 IF to_regclass('auth.sessions') IS NOT NULL THEN
  BEGIN sid:=NULLIF(claims->>'session_id','')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RETURN NULL; END;
  IF sid IS NULL OR to_regclass('auth.users') IS NULL THEN RETURN NULL; END IF;
  EXECUTE 'SELECT EXISTS(SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
   WHERE s.id=$1 AND s.user_id=$2 AND (s.not_after IS NULL OR s.not_after>statement_timestamp())
    AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=statement_timestamp()))'
   INTO valid_session USING sid,uid;
  IF NOT valid_session THEN RETURN NULL; END IF;
 END IF;
 RETURN uid;
END $$;
REVOKE ALL ON FUNCTION c10_demo.actor_uid() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.actor_uid() TO authenticated;

-- These existing canonical predicates use tightly scoped definer reads to avoid
-- recursive RLS when checking tenant.active. They return booleans, not rows, and
-- do not trust user_metadata, caller tenant/role claims or menu visibility.
CREATE OR REPLACE FUNCTION c10_demo.can_tenant(p_tenant bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
 SELECT EXISTS(SELECT 1 FROM c10_demo.tenants t JOIN c10_demo.tenant_members m ON m.tenant_id=t.id
 WHERE t.id=p_tenant AND t.active AND m.user_id=c10_demo.actor_uid() AND m.active AND m.role='tenant_owner')
$$;
CREATE OR REPLACE FUNCTION c10_demo.can_business(p_tenant bigint,p_business bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
 SELECT EXISTS(SELECT 1 FROM c10_demo.businesses b JOIN c10_demo.tenants t ON t.id=b.tenant_id
 WHERE b.id=p_business AND b.tenant_id=p_tenant AND t.active AND
 (c10_demo.can_tenant(p_tenant) OR EXISTS(SELECT 1 FROM c10_demo.business_members m
 WHERE m.business_id=p_business AND m.tenant_id=p_tenant AND m.user_id=c10_demo.actor_uid()
 AND m.active AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()) AND m.role IN('business_owner','manager'))))
$$;
CREATE OR REPLACE FUNCTION c10_demo.can_manage(p_tenant bigint,p_business bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
 SELECT EXISTS(SELECT 1 FROM c10_demo.businesses b JOIN c10_demo.tenants t ON t.id=b.tenant_id
 WHERE b.id=p_business AND b.tenant_id=p_tenant AND t.active AND
 (c10_demo.can_tenant(p_tenant) OR EXISTS(SELECT 1 FROM c10_demo.business_members m
 WHERE m.business_id=p_business AND m.tenant_id=p_tenant AND m.user_id=c10_demo.actor_uid()
 AND m.active AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()) AND m.role='business_owner')))
$$;
CREATE OR REPLACE FUNCTION c10_demo.can_site(p_tenant bigint,p_business bigint,p_site bigint,p_action text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
 SELECT p_action=ANY(ARRAY['stock.read','stock.post']) AND EXISTS(
 SELECT 1 FROM c10_demo.sites s JOIN c10_demo.tenants t ON t.id=s.tenant_id
 WHERE s.id=p_site AND s.tenant_id=p_tenant AND s.business_id=p_business AND t.active
 -- Explicit active denies precede inherited owner/manager rights. A denied read
 -- also blocks posting because canonical stock writes need that record context.
 AND NOT EXISTS(SELECT 1 FROM c10_demo.site_grants g WHERE g.site_id=p_site
  AND g.user_id=c10_demo.actor_uid() AND g.active AND (g.valid_until IS NULL OR g.valid_until>statement_timestamp())
  AND (p_action=ANY(g.denied_actions) OR (p_action='stock.post' AND 'stock.read'=ANY(g.denied_actions))))
 AND (c10_demo.can_business(p_tenant,p_business) OR EXISTS(
  SELECT 1 FROM c10_demo.site_grants g WHERE g.site_id=p_site AND g.tenant_id=p_tenant AND g.business_id=p_business
  AND g.user_id=c10_demo.actor_uid() AND g.active AND (g.valid_until IS NULL OR g.valid_until>statement_timestamp())
  AND p_action=ANY(g.actions))))
$$;
CREATE OR REPLACE FUNCTION c10_demo.can_see_business(p_tenant bigint,p_business bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
 SELECT c10_demo.can_business(p_tenant,p_business) OR EXISTS(
 SELECT 1 FROM c10_demo.sites s WHERE s.tenant_id=p_tenant AND s.business_id=p_business
 AND c10_demo.can_site(p_tenant,p_business,s.id,'stock.read'))
$$;
REVOKE ALL ON FUNCTION c10_demo.can_tenant(bigint),c10_demo.can_business(bigint,bigint),
 c10_demo.can_manage(bigint,bigint),c10_demo.can_site(bigint,bigint,bigint,text),c10_demo.can_see_business(bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.can_tenant(bigint),c10_demo.can_business(bigint,bigint),
 c10_demo.can_manage(bigint,bigint),c10_demo.can_site(bigint,bigint,bigint,text),c10_demo.can_see_business(bigint,bigint) TO authenticated;

CREATE FUNCTION c10_demo.build01_context_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); response jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'BUILD01_SIGNED_SESSION_REQUIRED'; END IF;
 SELECT jsonb_build_object('actor_uid',actor,
 'real_auth_account_verified',to_regclass('auth.sessions') IS NOT NULL,
 'tenants',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'slug',t.slug) ORDER BY t.id)
  FROM c10_demo.tenants t WHERE t.active AND (c10_demo.can_tenant(t.id) OR EXISTS(
   SELECT 1 FROM c10_demo.businesses b WHERE b.tenant_id=t.id AND c10_demo.can_see_business(t.id,b.id)))),'[]'::jsonb),
 'legal_entities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',l.id,'tenant_id',l.tenant_id,'label',l.label) ORDER BY l.id)
  FROM c10_demo.legal_entities l WHERE c10_demo.can_tenant(l.tenant_id)),'[]'::jsonb),
 'templates',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',t.code,'label',COALESCE(i.name_en,t.code),
   'source_status',t.source_status,'readiness',COALESCE(i.readiness,t.source_status),
   'draft_supported',true,'demo_allowed',t.demo_allowed,'enterprise_certified',t.enterprise_certified) ORDER BY t.code)
  FROM c10_demo.templates t LEFT JOIN c10_demo.industry_catalog_v2 i ON i.id=t.code
  WHERE i.id IS NOT NULL OR t.demo_allowed),'[]'::jsonb),
 'businesses',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',b.id,'tenant_id',b.tenant_id,'slug',b.slug,
   'label',COALESCE(c.display_name,b.slug),'status',b.status,'can_manage',c10_demo.can_manage(b.tenant_id,b.id),
   'role',CASE WHEN c10_demo.can_tenant(b.tenant_id) THEN 'tenant_owner' ELSE COALESCE((
    SELECT m.role FROM c10_demo.business_members m WHERE m.business_id=b.id AND m.user_id=actor AND m.active
     AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp())),'site_staff') END) ORDER BY b.id)
  FROM c10_demo.businesses b LEFT JOIN c10_demo.business_configuration_v1 c ON c.business_id=b.id
  WHERE c10_demo.can_see_business(b.tenant_id,b.id)),'[]'::jsonb),
 'sites',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'tenant_id',s.tenant_id,'business_id',s.business_id,
  'kind',s.kind,'label',s.label,'allowed_actions',to_jsonb(ARRAY(SELECT a FROM unnest(ARRAY['stock.read','stock.post']) a
   WHERE c10_demo.can_site(s.tenant_id,s.business_id,s.id,a)))) ORDER BY s.id)
  FROM c10_demo.sites s WHERE c10_demo.can_manage(s.tenant_id,s.business_id)
   OR c10_demo.can_site(s.tenant_id,s.business_id,s.id,'stock.read')),'[]'::jsonb),
 'production_certified',false,'data_mode','disposable-demo') INTO response;
 RETURN response;
END $$;

CREATE FUNCTION c10_demo.build01_workspace_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); tenant bigint; owner boolean; response jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM c10_demo.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT c10_demo.can_see_business(tenant,p_business)
 THEN RAISE EXCEPTION 'BUILD01_BUSINESS_DENIED'; END IF;
 owner:=c10_demo.can_manage(tenant,p_business);
 SELECT jsonb_build_object('actor_uid',actor,'business_id',p_business,'can_manage',owner,
 'business',(SELECT value FROM jsonb_array_elements(c10_demo.build01_context_v1()->'businesses') value WHERE value->>'id'=p_business::text),
 'sites',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'tenant_id',s.tenant_id,'business_id',s.business_id,'kind',s.kind,'label',s.label,
   'allowed_actions',to_jsonb(ARRAY(SELECT a FROM unnest(ARRAY['stock.read','stock.post']) a WHERE c10_demo.can_site(tenant,p_business,s.id,a)))) ORDER BY s.id)
  FROM c10_demo.sites s WHERE s.business_id=p_business AND (owner OR c10_demo.can_site(tenant,p_business,s.id,'stock.read'))),'[]'::jsonb),
 'access',jsonb_build_object(
  'business_members',COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.user_id) FROM c10_demo.business_members m
   WHERE m.business_id=p_business AND (owner OR m.user_id=actor)),'[]'::jsonb),
  'site_grants',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY g.site_id,g.user_id) FROM c10_demo.site_grants g
   WHERE g.business_id=p_business AND (owner OR g.user_id=actor)),'[]'::jsonb)),
 'audit',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id DESC) FROM (
  SELECT * FROM c10_demo.access_change_events_v1 WHERE business_id=p_business AND (owner OR subject_uid=actor) ORDER BY id DESC LIMIT 100)e),'[]'::jsonb),
 'setup_runs',CASE WHEN owner THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'business_id',r.business_id,'request_key',r.request_key,'created_by',r.created_by,'created_at',r.created_at) ORDER BY r.id)
  FROM c10_demo.business_setup_runs_v1 r WHERE r.business_id=p_business),'[]'::jsonb) ELSE '[]'::jsonb END,
 'receipt_truth',jsonb_build_object('real_auth_account_verified',to_regclass('auth.sessions') IS NOT NULL,
  'production_certified',false,'money_movement',false)) INTO response;
 RETURN response;
END $$;

CREATE FUNCTION c10_demo.build01_setup_v1(
 p_legal bigint,p_slug text,p_template text,p_display_name text,p_mode text,p_sites jsonb,p_request text,p_brand_hex text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE business bigint; tenant bigint; actor uuid:=c10_demo.actor_uid(); signature jsonb; previous record; event_id bigint; modules jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM c10_demo.legal_entities WHERE id=p_legal;
 IF actor IS NULL OR tenant IS NULL OR NOT c10_demo.can_tenant(tenant) THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 -- Original setup engines perform multiple canonical inserts. Serialize the
 -- same tenant/request before entering either engine so concurrent retries
 -- observe the committed receipt instead of racing the unique slug constraint.
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('build01.setup',tenant,p_request)::text,0));
 IF NOT c10_demo.can_tenant(tenant) THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 -- Reuse the original ten-family draft engine. Module selections come only
 -- from its canonical catalog; that engine keeps every module locked/disabled.
 -- Legacy demo-approved template codes retain the existing A020 v1 contract.
 IF EXISTS(SELECT 1 FROM c10_demo.industry_catalog_v2 WHERE id=p_template) THEN
  SELECT COALESCE(jsonb_agg(module_code ORDER BY module_code),'[]'::jsonb) INTO modules
   FROM c10_demo.industry_module_catalog_v2 WHERE industry_id=p_template;
  business:=c10_demo.setup_industry_draft_v2(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,modules,p_request,p_brand_hex);
 ELSE
  business:=c10_demo.setup_business_v1(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,p_request,p_brand_hex);
 END IF;
 signature:=jsonb_build_object('legal',p_legal,'slug',p_slug,'template',p_template,'display_name',p_display_name,'mode',p_mode,'sites',p_sites,'request',p_request,'brand_hex',p_brand_hex);
 SELECT * INTO previous FROM c10_demo.access_change_events_v1 WHERE business_id=business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'setup.business' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  event_id:=previous.id;
 ELSE
  INSERT INTO c10_demo.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,input_signature,before_state,after_state,actor_uid,event_kind)
   VALUES(tenant,business,p_request,'setup.business',actor,signature,'{}',jsonb_build_object('business_id',business,'status','draft'),actor,'setup.business') RETURNING id INTO event_id;
 END IF;
 RETURN jsonb_build_object('business_id',business,'request_key',p_request,'event_id',event_id,'status','draft','production_certified',false);
END $$;

CREATE FUNCTION c10_demo.build01_site_v1(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE site bigint; tenant bigint; actor uuid:=c10_demo.actor_uid(); signature jsonb; previous record; event_id bigint;
BEGIN
 SELECT tenant_id INTO tenant FROM c10_demo.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT c10_demo.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_SITE_DENIED'; END IF;
 PERFORM 1 FROM c10_demo.businesses WHERE id=p_business FOR UPDATE;
 IF NOT c10_demo.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_SITE_DENIED'; END IF;
 signature:=jsonb_build_object('business',p_business,'kind',p_kind,'label',p_label,'request',p_request);
 SELECT * INTO previous FROM c10_demo.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'setup.site' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  RETURN previous.after_state||jsonb_build_object('event_id',previous.id,'request_key',p_request);
 END IF;
 site:=c10_demo.provision_site(p_business,p_kind,p_label,p_request);
 INSERT INTO c10_demo.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,site_id,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,'setup.site',actor,site,signature,'{}',jsonb_build_object('business_id',p_business,'site_id',site),actor,'setup.site') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'site_id',site,'request_key',p_request,'event_id',event_id);
END $$;

CREATE FUNCTION c10_demo.build01_set_access_v1(
 p_business bigint,p_subject uuid,p_command text,p_role text,p_site bigint,p_actions text[],
 p_denied_actions text[],p_valid_until timestamptz,p_request text,p_expected_version bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); tenant bigint; signature jsonb; previous record; before_state jsonb; after_state jsonb;
 event_id bigint; base_event bigint; current_version bigint; known_subject boolean; desired text[]:=COALESCE(p_actions,'{}'::text[]);
 denied text[]:=COALESCE(p_denied_actions,'{}'::text[]); membership_role text;
BEGIN
 SELECT tenant_id INTO tenant FROM c10_demo.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT c10_demo.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_ACCESS_DENIED'; END IF;
 IF p_subject IS NULL OR p_subject=actor THEN RAISE EXCEPTION 'BUILD01_SELF_ACCESS_CHANGE_FORBIDDEN'; END IF;
 IF p_command IS NULL OR p_command NOT IN('business_member.grant','business_member.revoke','site_grant.grant','site_grant.revoke') OR
  p_request IS NULL OR length(btrim(p_request)) NOT BETWEEN 1 AND 120 OR p_expected_version<0 THEN RAISE EXCEPTION 'BUILD01_INVALID_ACCESS'; END IF;
 IF NOT denied <@ ARRAY['stock.read','stock.post']::text[] OR cardinality(denied)<>(SELECT count(DISTINCT x) FROM unnest(denied)x) OR
  NOT desired <@ ARRAY['stock.read','stock.post']::text[] OR cardinality(desired)<>(SELECT count(DISTINCT x) FROM unnest(desired)x)
 THEN RAISE EXCEPTION 'BUILD01_INVALID_ACTIONS'; END IF;
 IF p_command LIKE 'business_member.%' AND (p_site IS NOT NULL OR cardinality(desired)>0 OR cardinality(denied)>0) THEN RAISE EXCEPTION 'BUILD01_INVALID_MEMBERSHIP'; END IF;
 IF p_command LIKE 'site_grant.%' AND (p_site IS NULL OR p_role IS NOT NULL) THEN RAISE EXCEPTION 'BUILD01_INVALID_SITE_POLICY'; END IF;
 IF p_command LIKE '%.revoke' AND (p_valid_until IS NOT NULL OR cardinality(desired)>0 OR cardinality(denied)>0 OR p_role IS NOT NULL) THEN RAISE EXCEPTION 'BUILD01_INVALID_REVOKE'; END IF;
 IF p_command='site_grant.grant' AND cardinality(desired)=0 AND cardinality(denied)=0 THEN RAISE EXCEPTION 'BUILD01_EMPTY_POLICY'; END IF;
 IF to_regclass('auth.users') IS NOT NULL THEN
  EXECUTE 'SELECT EXISTS(SELECT 1 FROM auth.users WHERE id=$1 AND deleted_at IS NULL)' INTO known_subject USING p_subject;
 ELSE
  SELECT EXISTS(SELECT 1 FROM c10_demo.tenant_members WHERE user_id=p_subject) OR
   EXISTS(SELECT 1 FROM c10_demo.business_members WHERE user_id=p_subject) OR
   EXISTS(SELECT 1 FROM c10_demo.site_grants WHERE user_id=p_subject) INTO known_subject;
 END IF;
 IF NOT known_subject THEN RAISE EXCEPTION 'BUILD01_SUBJECT_NOT_REGISTERED'; END IF;
 PERFORM 1 FROM c10_demo.businesses WHERE id=p_business FOR UPDATE;
 IF NOT c10_demo.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_ACCESS_DENIED'; END IF;
 SELECT role INTO membership_role FROM c10_demo.business_members WHERE business_id=p_business AND user_id=p_subject AND active;
 IF membership_role='business_owner' AND NOT c10_demo.can_tenant(tenant) THEN RAISE EXCEPTION 'BUILD01_BUSINESS_OWNER_PROTECTED'; END IF;
 IF p_command LIKE 'site_grant.%' THEN
  IF NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_site AND business_id=p_business AND tenant_id=tenant) THEN RAISE EXCEPTION 'BUILD01_SITE_SCOPE_MISMATCH'; END IF;
  IF membership_role='investor' THEN RAISE EXCEPTION 'investor_cannot_receive_stock_grant'; END IF;
  SELECT to_jsonb(g),g.version INTO before_state,current_version FROM c10_demo.site_grants g WHERE site_id=p_site AND user_id=p_subject;
 ELSE
  SELECT to_jsonb(m),m.version INTO before_state,current_version FROM c10_demo.business_members m WHERE business_id=p_business AND user_id=p_subject;
  before_state:=COALESCE(before_state,'{}')||jsonb_build_object('site_grants',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY g.site_id) FROM c10_demo.site_grants g WHERE g.business_id=p_business AND g.user_id=p_subject),'[]'::jsonb));
 END IF;
 signature:=jsonb_build_object('business',p_business,'subject',p_subject,'command',p_command,'role',p_role,'site',p_site,
  'actions',desired,'denied_actions',denied,'valid_until',p_valid_until,'expected_version',p_expected_version);
 SELECT * INTO previous FROM c10_demo.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'policy.apply' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  RETURN jsonb_build_object('business_id',p_business,'event_id',previous.id,'request_key',p_request,'after_state',previous.after_state);
 END IF;
 IF p_valid_until IS NOT NULL AND p_valid_until<=statement_timestamp() THEN RAISE EXCEPTION 'BUILD01_EXPIRY_MUST_BE_FUTURE'; END IF;
 IF p_expected_version IS NOT NULL AND p_expected_version<>COALESCE(current_version,0) THEN RAISE EXCEPTION 'BUILD01_STALE_ACCESS_VERSION'; END IF;
 -- Deny-only policies must not silently grant read access just to satisfy the
 -- legacy A034 nonempty-actions command. All other base changes delegate A034.
 IF p_command='site_grant.grant' AND cardinality(desired)=0 THEN
  INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active,valid_until,denied_actions)
  VALUES(tenant,p_business,p_site,p_subject,'{}',true,p_valid_until,denied)
  ON CONFLICT(site_id,user_id) DO UPDATE SET actions='{}',active=true,valid_until=EXCLUDED.valid_until,denied_actions=EXCLUDED.denied_actions;
 ELSE
  base_event:=c10_demo.change_access_v1(p_business,p_subject,p_command,p_role,p_site,desired,'build01-base:'||md5(p_request));
  IF p_command='site_grant.grant' THEN
   UPDATE c10_demo.site_grants SET valid_until=p_valid_until,denied_actions=denied
    WHERE site_id=p_site AND user_id=p_subject AND (valid_until IS DISTINCT FROM p_valid_until OR denied_actions IS DISTINCT FROM denied);
  ELSIF p_command='business_member.grant' THEN
   UPDATE c10_demo.business_members SET valid_until=p_valid_until WHERE business_id=p_business AND user_id=p_subject AND valid_until IS DISTINCT FROM p_valid_until;
  ELSIF p_command='business_member.revoke' THEN
   -- Build01's business revoke removes all this subject's business site grants
   -- atomically too; the policy receipt records every affected canonical row.
   UPDATE c10_demo.site_grants SET active=false WHERE business_id=p_business AND user_id=p_subject AND active;
  END IF;
 END IF;
 IF p_command LIKE 'site_grant.%' THEN
  SELECT to_jsonb(g) INTO after_state FROM c10_demo.site_grants g WHERE site_id=p_site AND user_id=p_subject;
 ELSE
  SELECT to_jsonb(m) INTO after_state FROM c10_demo.business_members m WHERE business_id=p_business AND user_id=p_subject;
  after_state:=after_state||jsonb_build_object('site_grants',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY g.site_id) FROM c10_demo.site_grants g WHERE g.business_id=p_business AND g.user_id=p_subject),'[]'::jsonb));
 END IF;
 INSERT INTO c10_demo.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,site_id,desired_role,desired_actions,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,p_command,p_subject,p_site,p_role,NULLIF(desired,'{}'),signature,COALESCE(before_state,'{}'),after_state,actor,'policy.apply') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'event_id',event_id,'request_key',p_request,'after_state',after_state);
END $$;

REVOKE ALL ON FUNCTION c10_demo.build01_context_v1(),c10_demo.build01_workspace_v1(bigint),
 c10_demo.build01_setup_v1(bigint,text,text,text,text,jsonb,text,text),c10_demo.build01_site_v1(bigint,text,text,text),
 c10_demo.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.build01_context_v1(),c10_demo.build01_workspace_v1(bigint),
 c10_demo.build01_setup_v1(bigint,text,text,text,text,jsonb,text,text),c10_demo.build01_site_v1(bigint,text,text,text),
 c10_demo.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint) TO authenticated;
-- No direct grant-table mutation, owner-account provisioning, production switch,
-- provider call, stock/financial posting, alternate permission or audit store.
