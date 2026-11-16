-- NP02 / B-021 / 0104: Owner reads the Control part of the one canonical audit stream.
-- Read only (STABLE). Owners only; members get CONTROL_FORBIDDEN, others CONTROL_SCOPE.
CREATE FUNCTION core10.control_audit_v1(p_business bigint, p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; v_events jsonb; v_chain jsonb;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'stream_seq')::bigint DESC), '[]'::jsonb) INTO v_events FROM (
  SELECT jsonb_build_object('stream_seq', e.stream_seq, 'action', e.action, 'source_ref', e.source_ref,
   'actor_id', e.actor_id, 'event_at', e.event_at, 'payload', e.payload, 'event_digest', e.event_digest) AS x
  FROM core10.canonical_audit_events_v1 e
  WHERE e.business_id = p_business AND e.source_domain = 'control'
  ORDER BY e.stream_seq DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 200))) q;
 BEGIN
  v_chain := core10.verify_canonical_audit_v1(p_business);
 EXCEPTION WHEN OTHERS THEN
  v_chain := jsonb_build_object('ok', NULL, 'reason', 'chain check not available to this role');
 END;
 RETURN jsonb_build_object('events', v_events, 'chain', v_chain);
END $$;
REVOKE EXECUTE ON FUNCTION core10.control_audit_v1(bigint, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.control_audit_v1(bigint, integer) TO authenticated;
