-- Reversible audit port. All dependent approval migrations must roll back first.
DROP TRIGGER access_to_canonical_audit_v1 ON core10.access_change_events_v1;
DROP FUNCTION core10._access_to_canonical_audit_v1();
DROP FUNCTION core10.verify_canonical_audit_v1(bigint);
DROP FUNCTION core10._append_canonical_audit_v1(bigint,bigint,text,text,text,uuid,text,jsonb);
DROP TRIGGER canonical_audit_events_immutable_v1 ON core10.canonical_audit_events_v1;
DROP FUNCTION core10._immutable_canonical_audit_v1();
DROP POLICY canonical_audit_owner_read_v1 ON core10.canonical_audit_events_v1;
DROP TABLE core10.canonical_audit_events_v1;
DROP TABLE core10.audit_chain_heads_v1;
