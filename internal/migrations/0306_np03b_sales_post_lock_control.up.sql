-- Sales decides using the current policy after waiting for its command and document locks.
CREATE OR REPLACE FUNCTION core10.control_check_v1(p_business bigint, p_feature text, p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); v_tenant bigint; r jsonb; o core10.control_overrides_v1%ROWTYPE;
 v_at timestamptz := CASE WHEN (p_feature = 'setup001.provision' OR p_feature LIKE 'sales.%')
  THEN clock_timestamp() ELSE statement_timestamp() END;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'CONTROL_UNAUTHENTICATED'; END IF;
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = v_tenant) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 r := core10._control_resolve_at_v1(p_business, p_feature, p_site, v_at);
 IF (r->>'enabled')::boolean THEN RETURN r || jsonb_build_object('override_used', false); END IF;
 SELECT * INTO o FROM core10.control_overrides_v1
  WHERE business_id = p_business AND feature_key = p_feature
    AND (site_id IS NULL OR site_id = p_site)
    AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > v_at
  ORDER BY (site_id IS NULL), id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_DISABLED:%', p_feature; END IF;
 UPDATE core10.control_overrides_v1 SET consumed_at = v_at, consumed_by = v_actor WHERE id = o.id;
 PERFORM core10._append_canonical_audit_v1(v_tenant, p_business, 'control',
  'override:' || o.id || ':consumed', 'control.override_consumed', v_actor,
  'control:ovr:' || o.id || ':consumed',
  jsonb_build_object('feature_key', p_feature, 'site_id', p_site, 'override_id', o.id));
 RETURN r || jsonb_build_object('override_used', true, 'override_id', o.id);
END $$;

-- Require reconciliation of any already-recorded zero-stage approval claims.
-- Otherwise an old successful command could still return that receipt on retry.
DO $history$
BEGIN
 IF EXISTS (
  SELECT 1 FROM core10.canonical_audit_events_v1
  WHERE payload->>'approval_id' IS NOT NULL
    AND ((source_domain='sales' AND action IN ('sales.confirm','sales.cancel')
          AND payload->'source'->>'required_stages'='0')
      OR (source_domain='sales_invoice' AND action='sales.invoice_draft_validated'
          AND payload->'approval_payload'->>'required_stages'='0'))
 ) THEN RAISE EXCEPTION 'SALES_ZERO_STAGE_APPROVAL_HISTORY_REQUIRES_RECONCILIATION'; END IF;
END
$history$;
