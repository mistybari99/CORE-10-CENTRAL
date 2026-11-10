-- Restores pre-patch ACL {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
BEGIN;
GRANT EXECUTE ON FUNCTION public._costx_pct(uuid) TO PUBLIC, anon, authenticated, service_role;
COMMIT;
