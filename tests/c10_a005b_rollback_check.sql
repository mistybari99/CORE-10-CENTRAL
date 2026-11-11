\set ON_ERROR_STOP on
-- Run after security/c10_a005b_acl_ROLLBACK.sql: proacl must equal the fixture snapshot (entry order is not significant in an ACL).
DO $t$ DECLARE bad text; BEGIN
 SELECT string_agg(s.sig,',') INTO bad FROM public.a005b_acl_snapshot s JOIN pg_proc p ON p.oid=s.sig::regprocedure WHERE (SELECT array_agg(x ORDER BY x::text) FROM unnest(p.proacl) x) IS DISTINCT FROM (SELECT array_agg(x ORDER BY x::text) FROM unnest(s.acl::aclitem[]) x);
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'ROLLBACK_ACL_MISMATCH %',bad; END IF;
END $t$;
\echo PASS: A005b rollback restores exact pre-ACL
