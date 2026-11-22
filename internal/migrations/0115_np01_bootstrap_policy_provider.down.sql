-- Refuse to remove tenant policy/Audit representation once durable history exists.
DO $guard$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.control_setting_versions_v1 WHERE business_id IS NULL)
 OR EXISTS (SELECT 1 FROM core10.canonical_audit_events_v1 WHERE business_id IS NULL)
 OR EXISTS (SELECT 1 FROM core10.audit_chain_heads_v1 WHERE business_id IS NULL) THEN
  RAISE EXCEPTION 'BOOTSTRAP_POLICY_HISTORY_ROLLBACK_REFUSED';
 END IF;
END
$guard$;
DROP FUNCTION core10._set_bootstrap_policy_v1(bigint, boolean, timestamptz, integer, text, text);
DROP FUNCTION core10._bootstrap_policy_decision_v1(bigint);
DROP FUNCTION core10._append_bootstrap_audit_v1(bigint, integer, uuid, text, jsonb);
DROP FUNCTION core10._lock_bootstrap_policy_v1(bigint);
DROP INDEX core10.control_bootstrap_effective_v1, core10.control_bootstrap_request_v1,
 core10.control_bootstrap_version_v1;
ALTER TABLE core10.control_setting_versions_v1
 ALTER COLUMN business_id SET NOT NULL,
 DROP CONSTRAINT control_setting_versions_bootstrap_scope_v1,
 DROP CONSTRAINT control_setting_versions_tenant_fk_v1;
DROP POLICY canonical_audit_tenant_owner_read_v1 ON core10.canonical_audit_events_v1;
DROP INDEX core10.canonical_audit_tenant_request_v1, core10.canonical_audit_tenant_source_v1,
 core10.canonical_audit_tenant_seq_v1;
ALTER TABLE core10.canonical_audit_events_v1
 ALTER COLUMN business_id SET NOT NULL,
 DROP CONSTRAINT canonical_audit_tenant_fk_v1;
DROP INDEX core10.audit_chain_heads_tenant_scope_v1;
ALTER TABLE core10.audit_chain_heads_v1
 DROP CONSTRAINT audit_chain_heads_tenant_fk_v1,
 DROP CONSTRAINT audit_chain_heads_business_unique_v1,
 ADD PRIMARY KEY (business_id);
ALTER TABLE core10.tenants DROP COLUMN bootstrap_policy_initialized;
