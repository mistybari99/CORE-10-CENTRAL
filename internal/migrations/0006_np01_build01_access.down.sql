-- S1-b reverse Build01 without CASCADE; restore 0002 A018 resolver contracts.
-- Reverted functions match their pre-Build01 definitions; applied migrations are
-- intentionally immutable after release, and this is test-branch staging only.
DROP FUNCTION core10.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint);
DROP FUNCTION core10.build01_site_v1(bigint,text,text,text);
DROP FUNCTION core10.build01_setup_v1(bigint,text,text,text,text,jsonb,text,text);
DROP FUNCTION core10.build01_workspace_v1(bigint);
DROP FUNCTION core10.build01_context_v1();
DROP TRIGGER build01_membership_version ON core10.business_members;
DROP TRIGGER build01_site_grant_version ON core10.site_grants;
DROP TRIGGER build01_access_audit_append_only ON core10.access_change_events_v1;
DROP FUNCTION core10.build01_bump_version_v1();
DROP FUNCTION core10.build01_immutable_access_event_v1();
ALTER TABLE core10.access_change_events_v1 DROP CONSTRAINT access_change_events_v1_command_check;
ALTER TABLE core10.access_change_events_v1 ADD CONSTRAINT access_change_events_v1_command_check
 CHECK (command IN ('business_member.grant','business_member.revoke',
                    'site_grant.grant','site_grant.revoke'));
ALTER TABLE core10.access_change_events_v1 DROP COLUMN event_kind;
ALTER TABLE core10.site_grants DROP COLUMN version, DROP COLUMN denied_actions, DROP COLUMN valid_until;
ALTER TABLE core10.business_members DROP COLUMN version, DROP COLUMN valid_until;
CREATE OR REPLACE FUNCTION core10.actor_uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
 SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb ->> 'sub',
                 NULLIF(current_setting('request.jwt.claim.sub',true),''))::uuid
$$;

CREATE OR REPLACE FUNCTION core10.can_tenant(p_tenant bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT EXISTS(
 SELECT 1 FROM core10.tenant_members m
 WHERE m.user_id=core10.actor_uid() AND m.tenant_id=p_tenant
   AND m.role='tenant_owner' AND m.active)
$$;

CREATE OR REPLACE FUNCTION core10.can_business(p_tenant bigint,p_business bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT core10.can_tenant(p_tenant) OR EXISTS(
 SELECT 1 FROM core10.business_members m
 WHERE m.user_id=core10.actor_uid() AND m.tenant_id=p_tenant
   AND m.business_id=p_business AND m.active AND m.role IN('business_owner','manager'))
$$;

CREATE OR REPLACE FUNCTION core10.can_manage(p_tenant bigint,p_business bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT core10.can_tenant(p_tenant) OR EXISTS(
 SELECT 1 FROM core10.business_members m
 WHERE m.user_id=core10.actor_uid() AND m.tenant_id=p_tenant
   AND m.business_id=p_business AND m.active AND m.role='business_owner')
$$;

CREATE OR REPLACE FUNCTION core10.can_site(p_tenant bigint,p_business bigint,p_site bigint,p_action text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT core10.can_business(p_tenant,p_business) OR EXISTS (
 SELECT 1 FROM core10.site_grants g
 WHERE g.user_id=core10.actor_uid() AND g.active
   AND g.tenant_id=p_tenant AND g.business_id=p_business
   AND g.site_id=p_site AND p_action=ANY(g.actions))
$$;

CREATE OR REPLACE FUNCTION core10.can_see_business(p_tenant bigint,p_business bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT core10.can_business(p_tenant,p_business) OR EXISTS (
 SELECT 1 FROM core10.site_grants g
 WHERE g.user_id=core10.actor_uid() AND g.active
 AND g.tenant_id=p_tenant AND g.business_id=p_business AND array_length(g.actions,1)>0)
$$;
REVOKE EXECUTE ON FUNCTION core10.actor_uid(),core10.can_tenant(bigint),
 core10.can_business(bigint,bigint),core10.can_manage(bigint,bigint),
 core10.can_site(bigint,bigint,bigint,text),core10.can_see_business(bigint,bigint)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.actor_uid(),core10.can_tenant(bigint),
 core10.can_business(bigint,bigint),core10.can_manage(bigint,bigint),
 core10.can_site(bigint,bigint,bigint,text),core10.can_see_business(bigint,bigint)
 TO authenticated;
