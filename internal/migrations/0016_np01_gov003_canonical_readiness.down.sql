-- 0016 rollback on disposable PostgreSQL only, never canonical audit data.
DROP FUNCTION IF EXISTS core10.gov003_audit_export_v1(bigint,bigint,integer);
DROP FUNCTION IF EXISTS core10.gov003_audit_risk_v1(bigint,timestamptz);
DROP FUNCTION IF EXISTS core10.gov003_audit_readiness_v1(bigint);
