-- CORE10 S0 / DEC-01: canonical engine schema and migration ledger.
-- Engine tables and RPCs live in schema core10. c10_demo stays fixture/test only.
-- The protected legacy IMG-ERP-SG public schema is never touched by these files (D051).
CREATE SCHEMA core10;
REVOKE ALL ON SCHEMA core10 FROM PUBLIC;
COMMENT ON SCHEMA core10 IS 'CORE10 canonical engine schema (DEC-01). Access only through versioned SECURITY DEFINER RPCs.';

CREATE TABLE core10.schema_migrations(
 version integer PRIMARY KEY CHECK(version>0),
 name text NOT NULL CHECK(name ~ '^[0-9]{4}_[a-z0-9_]+$'),
 checksum text NOT NULL CHECK(checksum ~ '^[0-9a-f]{64}$'),
 applied_at timestamptz NOT NULL DEFAULT now(),
 applied_by text NOT NULL DEFAULT session_user
);
ALTER TABLE core10.schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.schema_migrations FROM PUBLIC;
COMMENT ON TABLE core10.schema_migrations IS 'One row per applied migration; written only by internal/migrations/run.sh.';
