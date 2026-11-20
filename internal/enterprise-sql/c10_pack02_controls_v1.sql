-- PACK-02 slice 3 (A042/A043/A044; D033/D045): control placement projection
-- for the Universal Owner and Business Owner workspaces.
-- Additive, READ-ONLY, disposable core10 only. Loaded after
-- c10_a044_control_settings_v1.sql and c10_pack02_workspace_v1.sql.
-- One canonical config: reads control_catalog_v1 / control_settings_v1 only.
-- Writes stay with A044 write_control_setting_v1 / decide_control_setting_v1.
-- Placement is presentation, NOT permission: nothing here grants an action.
DO $guard$ BEGIN
 IF current_database() !~ '^core10_(build01|build02a|a[0-9]+|preview|pack02)' OR
    to_regclass('core10.control_settings_v1') IS NULL OR
    to_regprocedure('core10.pack02_workspace_v1(text,bigint)') IS NULL THEN
  RAISE EXCEPTION 'PACK02_DISPOSABLE_A044_AND_WORKSPACE_REQUIRED';
 END IF;
END $guard$;

CREATE FUNCTION core10.pack02_controls_v1(p_surface text,p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid:=core10.actor_uid(); tenant bigint; central boolean; items jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'PACK02_SIGNED_SESSION_REQUIRED'; END IF;
 IF p_surface IS NULL OR p_surface NOT IN('central','business') THEN RAISE EXCEPTION 'PACK02_SURFACE_INVALID'; END IF;
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF tenant IS NULL THEN RAISE EXCEPTION 'PACK02_CONTROLS_DENIED'; END IF;
 central:=core10.can_tenant(tenant);
 -- Central surface: tenant owner only. Business surface: business owner of
 -- record (or tenant owner). Managers, staff, investors get no control surface.
 IF (p_surface='central' AND NOT central) OR
    (p_surface='business' AND NOT core10.can_manage(tenant,p_business)) THEN
  RAISE EXCEPTION 'PACK02_CONTROLS_DENIED';
 END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'control_id',x.control_id,'group',x.display_group,'placement',x.placement,
   'in_menu',x.in_menu,'preferred_enabled',x.preferred_enabled,'version',x.version,
   -- How THIS actor may change it on THIS surface. A044 re-checks on write.
   'edit',CASE WHEN central THEN 'direct'
               WHEN x.local_edit_mode='business_owner' THEN 'direct'
               WHEN x.local_edit_mode='request_approval' THEN 'request'
               ELSE 'view' END) ORDER BY x.control_id),'[]'::jsonb)
  INTO items FROM (
   SELECT c.control_id,c.display_group,
    COALESCE(s.placement,'central_only') AS placement,
    COALESCE(s.local_edit_mode,'central_only') AS local_edit_mode,
    COALESCE(s.preferred_enabled,false) AS preferred_enabled,COALESCE(s.version,0) AS version,
    CASE p_surface WHEN 'central' THEN COALESCE(s.placement,'central_only') IN('central_only','both')
                   ELSE COALESCE(s.placement,'central_only') IN('business_only','both') END AS in_menu
   FROM core10.control_catalog_v1 c
   LEFT JOIN core10.control_settings_v1 s ON s.business_id=p_business AND s.tenant_id=tenant AND s.control_id=c.control_id) x
  -- Central registry lists every control (Business Only / Hidden stay
  -- discoverable there, D045). The business surface lists ONLY its own menu:
  -- central-only and hidden controls are not disclosed to a delegated owner.
  WHERE p_surface='central' OR x.in_menu;
 RETURN jsonb_build_object('contract','C10_PACK02_CONTROLS_V1','surface',p_surface,
  'business_id',p_business,'items',items,
  'placement_is_not_permission',true,'operationally_certified',false,'production_certified',false);
END $$;
REVOKE ALL ON FUNCTION core10.pack02_controls_v1(text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.pack02_controls_v1(text,bigint) TO authenticated;
