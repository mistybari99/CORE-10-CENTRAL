-- Rollback of 0153: restore the 0151 lookup (no lock).
CREATE OR REPLACE FUNCTION core10._master_replay_v1(p_business bigint, p_key text, p_entity text) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE r core10.master_requests_v1%ROWTYPE;
BEGIN
 IF p_key IS NULL OR length(p_key) NOT BETWEEN 8 AND 120 THEN RAISE EXCEPTION 'MASTER_BAD_REQUEST_KEY'; END IF;
 SELECT * INTO r FROM core10.master_requests_v1 WHERE business_id=p_business AND request_key=p_key;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.actor_id IS DISTINCT FROM core10.actor_uid() OR r.entity<>p_entity THEN RAISE EXCEPTION 'MASTER_REQUEST_KEY_REUSED'; END IF;
 RETURN r.entity_id;
END $$;
REVOKE ALL ON FUNCTION core10._master_replay_v1(bigint,text,text) FROM PUBLIC, authenticated;
