-- S1-b A034 rollback: inverse of 0003, no CASCADE or external schema changes.
DROP VIEW core10.access_governance_overview_v1;
DROP FUNCTION core10.owner_access_metric_v1(bigint,text);
DROP FUNCTION core10.change_access_v1(bigint,uuid,text,text,bigint,text[],text);
DROP POLICY access_audit_owner_read_v1 ON core10.access_change_events_v1;
DROP TABLE core10.access_change_events_v1;
