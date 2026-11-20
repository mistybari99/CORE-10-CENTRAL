-- NP01 B-005 / 0013: prevent TRUNCATE from bypassing row-level journal immutability.
-- A BEFORE UPDATE/DELETE row trigger is NOT fired by TRUNCATE. This is a structural
-- integrity invariant, never a business-configurable DEC-08 on/off preference.
-- Apply only through the canonical migration runner, not directly to hosted DB.
CREATE FUNCTION core10._deny_np01_journal_truncate_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, core10 AS $np01$
BEGIN
  RAISE EXCEPTION 'core10_journal_truncate_denied:%', TG_TABLE_NAME
    USING ERRCODE = '42501';
END
$np01$;
REVOKE ALL ON FUNCTION core10._deny_np01_journal_truncate_v1()
  FROM PUBLIC, authenticated;

CREATE TRIGGER np01_truncate_guard_01_v1
  BEFORE TRUNCATE ON core10.audit_chain_heads_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_02_v1
  BEFORE TRUNCATE ON core10.canonical_audit_events_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_03_v1
  BEFORE TRUNCATE ON core10.access_change_events_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_04_v1
  BEFORE TRUNCATE ON core10.approval_requests
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_05_v1
  BEFORE TRUNCATE ON core10.approval_events
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_06_v1
  BEFORE TRUNCATE ON core10.approval_policy_versions_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_07_v1
  BEFORE TRUNCATE ON core10.approval_routes_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_08_v1
  BEFORE TRUNCATE ON core10.approval_stage_receipts_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_09_v1
  BEFORE TRUNCATE ON core10.approval_delegations_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();
