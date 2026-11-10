-- CORE10 A034 — authenticated, auditable staff/business access governance.
-- DISPOSABLE PG17 CI ONLY. Independent additive layer on A018 tenant/business/site auth.
-- Never deploy this SECURITY DEFINER code to public SG without staged real Auth tests.
CREATE TABLE c10_demo.access_change_events_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 request_key text NOT NULL CHECK (length(btrim(request_key)) BETWEEN 1 AND 120),
 command text NOT NULL CHECK (command IN (
   'business_member.grant','business_member.revoke',
   'site_grant.grant','site_grant.revoke'
 )),
 subject_uid uuid NOT NULL,
 site_id bigint,
 desired_role text,
 desired_actions text[],
 input_signature jsonb NOT NULL CHECK (jsonb_typeof(input_signature)='object'),
 before_state jsonb NOT NULL,
 after_state jsonb NOT NULL,
 actor_uid uuid NOT NULL,
 executed_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'applied' CHECK(status='applied'),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
ALTER TABLE c10_demo.access_change_events_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY access_audit_owner_read_v1 ON c10_demo.access_change_events_v1
 FOR SELECT TO authenticated
 USING (c10_demo.can_manage(tenant_id,business_id));
REVOKE ALL ON c10_demo.access_change_events_v1 FROM PUBLIC;
GRANT SELECT ON c10_demo.access_change_events_v1 TO authenticated;

CREATE FUNCTION c10_demo.change_access_v1(
 p_business bigint,p_subject uuid,p_command text,p_role text,
 p_site bigint,p_actions text[],p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $$
DECLARE v_tenant bigint; v_actor uuid; v_owner boolean;
 v_site_tenant bigint; v_site_business bigint;
 v_previous record; v_event bigint; v_before jsonb:='{}'::jsonb;
 v_after jsonb:='{}'::jsonb; v_input jsonb; v_subject_role text;
 v_actions text[]:=COALESCE(p_actions,ARRAY[]::text[]);
BEGIN
 v_actor:=c10_demo.actor_uid();
 IF v_actor IS NULL OR p_business IS NULL OR p_subject IS NULL OR
    p_command IS NULL OR p_command NOT IN (
     'business_member.grant','business_member.revoke',
     'site_grant.grant','site_grant.revoke') OR
    p_request IS NULL OR length(btrim(p_request)) NOT BETWEEN 1 AND 120
 THEN RAISE EXCEPTION 'invalid_access_change'; END IF;
 IF p_command LIKE 'business_member.%' THEN
  IF p_site IS NOT NULL OR cardinality(v_actions)<>0 THEN
   RAISE EXCEPTION 'invalid_membership_payload'; END IF;
  IF p_command='business_member.grant' AND
     (p_role IS NULL OR p_role NOT IN('business_owner','manager','investor'))
  THEN RAISE EXCEPTION 'invalid_business_role'; END IF;
  IF p_command='business_member.revoke' AND p_role IS NOT NULL
  THEN RAISE EXCEPTION 'invalid_membership_payload'; END IF;
 ELSE
  IF p_site IS NULL OR p_role IS NOT NULL THEN
   RAISE EXCEPTION 'invalid_site_access_payload'; END IF;
  IF p_command='site_grant.grant' AND
   (cardinality(v_actions)<1 OR cardinality(v_actions)>2 OR
     NOT v_actions <@ ARRAY['stock.read','stock.post']::text[] OR
     (SELECT count(DISTINCT x) FROM unnest(v_actions) x)<>cardinality(v_actions))
  THEN RAISE EXCEPTION 'invalid_site_actions'; END IF;
  IF p_command='site_grant.revoke' AND cardinality(v_actions)<>0
  THEN RAISE EXCEPTION 'invalid_site_access_payload'; END IF;
 END IF;
 SELECT tenant_id INTO v_tenant FROM c10_demo.businesses WHERE id=p_business;
 IF v_tenant IS NULL OR NOT c10_demo.can_manage(v_tenant,p_business)
 THEN RAISE EXCEPTION 'access_change_not_authorized'; END IF;
 v_owner:=c10_demo.can_tenant(v_tenant);
 IF p_subject=v_actor THEN RAISE EXCEPTION 'self_access_change_forbidden'; END IF;
 -- Serialize all membership changes per business; this also protects duplicate
 -- request keys under concurrent callers and role changes during approval.
 PERFORM 1 FROM c10_demo.businesses WHERE id=p_business FOR UPDATE;
 IF p_command LIKE 'site_grant.%' THEN
  SELECT tenant_id,business_id INTO v_site_tenant,v_site_business
    FROM c10_demo.sites WHERE id=p_site;
  IF v_site_tenant IS NULL OR v_site_tenant<>v_tenant OR v_site_business<>p_business
  THEN RAISE EXCEPTION 'site_business_scope_mismatch'; END IF;
 END IF;
 v_input:=jsonb_build_object('business',p_business,'subject',p_subject,
   'command',p_command,'role',p_role,'site',p_site,'actions',v_actions);
 SELECT id,input_signature,actor_uid INTO v_previous
 FROM c10_demo.access_change_events_v1
 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF v_previous.input_signature<>v_input OR v_previous.actor_uid<>v_actor
  THEN RAISE EXCEPTION 'access_request_idempotency_conflict'; END IF;
  RETURN v_previous.id;
 END IF;

 IF p_command LIKE 'business_member.%' THEN
  SELECT role,active INTO v_subject_role,v_previous
   FROM c10_demo.business_members
   WHERE business_id=p_business AND user_id=p_subject;
  -- Re-select the row using fixed output columns; not caller-supplied roles.
  SELECT role,active INTO v_previous
   FROM c10_demo.business_members
   WHERE business_id=p_business AND user_id=p_subject;
  IF FOUND THEN
   v_before:=jsonb_build_object('role',v_previous.role,'active',v_previous.active);
  END IF;
  IF p_command='business_member.grant' THEN
   IF p_role='business_owner' AND NOT v_owner THEN
    RAISE EXCEPTION 'tenant_owner_required_for_business_owner_role'; END IF;
   IF NOT v_owner AND v_previous.role='business_owner' THEN
    RAISE EXCEPTION 'business_owner_membership_protected'; END IF;
   INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
   VALUES(v_tenant,p_business,p_subject,p_role,true)
   ON CONFLICT(business_id,user_id) DO UPDATE
    SET role=EXCLUDED.role,active=true;
  ELSE
   IF v_before='{}'::jsonb OR NOT v_previous.active THEN
    RAISE EXCEPTION 'membership_not_active'; END IF;
   IF v_previous.role='business_owner' AND NOT v_owner THEN
    RAISE EXCEPTION 'business_owner_membership_protected'; END IF;
   UPDATE c10_demo.business_members SET active=false
    WHERE business_id=p_business AND user_id=p_subject;
  END IF;
  SELECT jsonb_build_object('role',role,'active',active) INTO v_after
   FROM c10_demo.business_members WHERE business_id=p_business AND user_id=p_subject;
 ELSE
  SELECT role INTO v_subject_role FROM c10_demo.business_members
   WHERE business_id=p_business AND user_id=p_subject AND active;
  IF v_subject_role='investor' THEN
   RAISE EXCEPTION 'investor_cannot_receive_stock_grant'; END IF;
  SELECT active,actions INTO v_previous
   FROM c10_demo.site_grants WHERE site_id=p_site AND user_id=p_subject;
  IF FOUND THEN
   v_before:=jsonb_build_object('active',v_previous.active,'actions',v_previous.actions);
  END IF;
  IF p_command='site_grant.grant' THEN
   INSERT INTO c10_demo.site_grants(
    tenant_id,business_id,site_id,user_id,actions,active)
   VALUES(v_tenant,p_business,p_site,p_subject,v_actions,true)
   ON CONFLICT(site_id,user_id) DO UPDATE
    SET actions=EXCLUDED.actions,active=true;
  ELSE
   IF v_before='{}'::jsonb OR NOT v_previous.active THEN
    RAISE EXCEPTION 'site_grant_not_active'; END IF;
   UPDATE c10_demo.site_grants SET active=false
    WHERE site_id=p_site AND user_id=p_subject;
  END IF;
  SELECT jsonb_build_object('active',active,'actions',actions) INTO v_after
   FROM c10_demo.site_grants WHERE site_id=p_site AND user_id=p_subject;
 END IF;

 INSERT INTO c10_demo.access_change_events_v1(
  tenant_id,business_id,request_key,command,subject_uid,
  site_id,desired_role,desired_actions,input_signature,before_state,after_state,actor_uid)
 VALUES(v_tenant,p_business,p_request,p_command,p_subject,
  p_site,p_role,NULLIF(v_actions,ARRAY[]::text[]),v_input,
  v_before,v_after,v_actor) RETURNING id INTO v_event;
 RETURN v_event;
END $$;

CREATE VIEW c10_demo.access_governance_overview_v1 WITH(security_invoker=true) AS
 SELECT b.tenant_id,b.id AS business_id,b.slug,
 (SELECT count(*) FROM c10_demo.business_members m
   WHERE m.business_id=b.id AND m.active AND m.role='business_owner') AS active_business_owners,
 (SELECT count(*) FROM c10_demo.business_members m
   WHERE m.business_id=b.id AND m.active AND m.role='manager') AS active_managers,
 (SELECT count(*) FROM c10_demo.business_members m
   WHERE m.business_id=b.id AND m.active AND m.role='investor') AS active_investors,
 (SELECT count(*) FROM c10_demo.site_grants g WHERE g.business_id=b.id AND g.active) AS active_site_grants,
 (SELECT count(*) FROM c10_demo.access_change_events_v1 a
   WHERE a.business_id=b.id) AS audited_access_changes,
 false::boolean AS real_auth_account_verified
 FROM c10_demo.businesses b WHERE c10_demo.can_manage(b.tenant_id,b.id);
REVOKE ALL ON c10_demo.access_governance_overview_v1 FROM PUBLIC;
GRANT SELECT ON c10_demo.access_governance_overview_v1 TO authenticated;
REVOKE EXECUTE ON FUNCTION c10_demo.change_access_v1(bigint,uuid,text,text,bigint,text[],text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.change_access_v1(bigint,uuid,text,text,bigint,text[],text) TO authenticated;
-- Production gate: validate p_subject against actual Supabase auth.users and
-- session revocation (short JWT TTL). This CI-only prototype does not create user accounts.
