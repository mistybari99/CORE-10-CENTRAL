-- DELIBERATE bad changes, applied by the TEST as superuser in a scratch database only.
-- They are what an attacker or a careless migration could do; feature 09 must flag them as ADVISORY.
\set ON_ERROR_STOP on
-- 1) EXECUTE on a SECURITY DEFINER writer to PUBLIC
grant execute on function c10_gov003_demo.append_event(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,uuid,uuid) to public;
-- 2) EXECUTE on the internal audit appender to the ordinary app role
grant execute on function c10_gov003_demo._append_audit(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,int,uuid,uuid) to c10g3_app;
-- 3) INSERT on the audit table to the backend role
grant insert on c10_gov003_demo.audit_events to c10g3_backend;
-- 4) a permissive OR policy that widens SELECT on the audit table to everyone
create policy bad_permissive_or on c10_gov003_demo.audit_events for select to public using (true);
