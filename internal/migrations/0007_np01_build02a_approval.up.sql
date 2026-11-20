-- S1-b canonical Build02A approval-policy access extension.
-- Dependency-based guard, no assumption about disposable database naming.
-- Build 02A: approval actions reuse Build01's canonical membership and audit.
-- Disposable core10 candidate only; not a production migration or posting API.
DO $guard$ BEGIN
 IF to_regclass('core10.access_change_events_v1') IS NULL OR
    to_regprocedure('core10.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint)') IS NULL THEN
  RAISE EXCEPTION 'BUILD02A_BUILD01_REQUIRED';
 END IF;
END $guard$;

ALTER TABLE core10.business_members
 ADD COLUMN approval_actions text[] NOT NULL DEFAULT '{}'
 CHECK(approval_actions <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]),
 ADD COLUMN approval_denied_actions text[] NOT NULL DEFAULT '{}'
 CHECK(approval_denied_actions <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]),
 ADD COLUMN approval_valid_until timestamptz;

ALTER TABLE core10.access_change_events_v1 DROP CONSTRAINT access_change_events_v1_command_check;
ALTER TABLE core10.access_change_events_v1 ADD CONSTRAINT access_change_events_v1_command_check
 CHECK(command IN('business_member.grant','business_member.revoke','site_grant.grant','site_grant.revoke','setup.business','setup.site','approval_policy.apply'));

CREATE OR REPLACE FUNCTION core10.can_approval_action_v1(p_tenant bigint,p_business bigint,p_action text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT p_action=ANY(ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception'])
 AND EXISTS(SELECT 1 FROM core10.businesses b JOIN core10.tenants t ON t.id=b.tenant_id
  WHERE b.id=p_business AND b.tenant_id=p_tenant AND t.active
   AND NOT EXISTS(SELECT 1 FROM core10.business_members d
    WHERE d.business_id=p_business AND d.tenant_id=p_tenant AND d.user_id=core10.actor_uid()
     AND d.active AND (d.valid_until IS NULL OR d.valid_until>statement_timestamp())
     AND (d.approval_valid_until IS NULL OR d.approval_valid_until>statement_timestamp())
     AND p_action=ANY(d.approval_denied_actions))
   AND (
     core10.can_tenant(p_tenant)
     OR EXISTS(SELECT 1 FROM core10.business_members m
       WHERE m.business_id=p_business AND m.tenant_id=p_tenant AND m.user_id=core10.actor_uid()
        AND m.active AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp())
        AND (
          ((m.approval_valid_until IS NULL OR m.approval_valid_until>statement_timestamp()) AND p_action=ANY(m.approval_actions))
          OR (m.role='business_owner')
          OR (m.role='manager' AND p_action=ANY(ARRAY['approval.submit','approval.withdraw']))
        ))
   ))
$$;

CREATE FUNCTION core10.build02a_set_approval_policy_v1(
 p_business bigint,p_subject uuid,p_actions text[],p_denied_actions text[],p_valid_until timestamptz,
 p_request text,p_expected_version bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid:=core10.actor_uid(); tenant bigint; member record; previous record; event_id bigint;
 desired text[]:=COALESCE(p_actions,'{}'::text[]); denied text[]:=COALESCE(p_denied_actions,'{}'::text[]); signature jsonb; after_state jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD02A_POLICY_DENIED'; END IF;
 IF p_subject IS NULL OR p_subject=actor OR p_request IS NULL OR length(btrim(p_request)) NOT BETWEEN 1 AND 120 OR p_expected_version<0 THEN
  RAISE EXCEPTION 'BUILD02A_INVALID_POLICY';
 END IF;
 IF NOT desired <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]
  OR NOT denied <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]
  OR cardinality(desired)<>(SELECT count(DISTINCT x) FROM unnest(desired)x)
  OR cardinality(denied)<>(SELECT count(DISTINCT x) FROM unnest(denied)x)
  OR EXISTS(SELECT 1 FROM unnest(desired)x WHERE x=ANY(denied)) THEN RAISE EXCEPTION 'BUILD02A_INVALID_ACTIONS'; END IF;
 IF p_valid_until IS NOT NULL AND p_valid_until<=statement_timestamp() THEN RAISE EXCEPTION 'BUILD02A_EXPIRY_MUST_BE_FUTURE'; END IF;
 PERFORM 1 FROM core10.businesses WHERE id=p_business FOR UPDATE;
 IF NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD02A_POLICY_DENIED'; END IF;
 SELECT * INTO member FROM core10.business_members WHERE business_id=p_business AND user_id=p_subject FOR UPDATE;
 IF NOT FOUND OR NOT member.active OR (member.valid_until IS NOT NULL AND member.valid_until<=statement_timestamp()) OR member.role='investor' THEN
  RAISE EXCEPTION 'BUILD02A_SUBJECT_NOT_ELIGIBLE';
 END IF;
 signature:=jsonb_build_object('business',p_business,'subject',p_subject,'actions',desired,'denied_actions',denied,
  'valid_until',p_valid_until,'expected_version',p_expected_version);
 SELECT * INTO previous FROM core10.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.command<>'approval_policy.apply' THEN RAISE EXCEPTION 'BUILD02A_REQUEST_CONFLICT'; END IF;
  RETURN jsonb_build_object('business_id',p_business,'event_id',previous.id,'request_key',p_request,'after_state',previous.after_state);
 END IF;
 IF p_expected_version IS NOT NULL AND p_expected_version<>member.version THEN RAISE EXCEPTION 'BUILD02A_STALE_VERSION'; END IF;
 UPDATE core10.business_members SET approval_actions=desired,approval_denied_actions=denied,approval_valid_until=p_valid_until
  WHERE business_id=p_business AND user_id=p_subject;
 SELECT to_jsonb(m) INTO after_state FROM core10.business_members m WHERE m.business_id=p_business AND m.user_id=p_subject;
 INSERT INTO core10.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,'approval_policy.apply',p_subject,signature,to_jsonb(member),after_state,actor,'policy.apply') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'event_id',event_id,'request_key',p_request,'after_state',after_state);
END $$;

REVOKE ALL ON FUNCTION core10.can_approval_action_v1(bigint,bigint,text),
 core10.build02a_set_approval_policy_v1(bigint,uuid,text[],text[],timestamptz,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.can_approval_action_v1(bigint,bigint,text),
 core10.build02a_set_approval_policy_v1(bigint,uuid,text[],text[],timestamptz,text,bigint) TO authenticated;
