-- CORE 10 A011 | CANDIDATE ONLY | REQUIRES STAGING + OWNER GO/NO-GO
-- Replaces only the existing RPC implementation; no table DDL, no data backfill.
-- Uses existing business_place_ops135.impact JSONB for immutable request binding.
-- Refuses to apply if an op already exists, if the baseline RPC drifted, or ACL drifted.
BEGIN;
DO $c10_preflight$
DECLARE fn oid := to_regprocedure('public.business_place_create135(bigint,text,text,text,text,bigint,uuid)')::oid;
BEGIN
  IF fn IS NULL THEN RAISE EXCEPTION 'c10_a011_missing_function'; END IF;
  IF md5(pg_get_functiondef(fn)) <> 'a3bc0655b89398e124147a6d3d8f4f41' THEN
    RAISE EXCEPTION 'c10_a011_rpc_baseline_drift';
  END IF;
  IF (SELECT count(*) FROM public.business_place_ops135) <> 0 THEN
    RAISE EXCEPTION 'c10_a011_existing_ops_require_migration_review';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='business_place_ops135'
    AND column_name='impact' AND udt_name='jsonb') THEN
    RAISE EXCEPTION 'c10_a011_impact_column_missing';
  END IF;
  IF has_function_privilege('anon',fn,'EXECUTE')
    OR NOT has_function_privilege('authenticated',fn,'EXECUTE') THEN
    RAISE EXCEPTION 'c10_a011_rpc_acl_drift';
  END IF;
END $c10_preflight$;
CREATE OR REPLACE FUNCTION public.business_place_create135(p_business bigint, p_kind text, p_code text, p_name_bn text, p_name_en text, p_org_branch bigint DEFAULT NULL::bigint, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); b public.org_units; u public.org_units; unit_id bigint; k text; pre text; lc text; stored text; nm_bn text; nm_en text; r jsonb; nid int; op public.business_place_ops135;
  base text; n int := 1; c10_payload jsonb; existing_status text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  -- strict scope: the owner, or the org_manage holder of THAT business; a foreign or missing business answers alike (the owner gets the precise text below)
  if not public._biz_mgr134(p_business) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  -- Immutable idempotency identity; do not compare with editable current location names.
  -- Canonical fields reflect the original accepted arguments, not a generated code.
  c10_payload := jsonb_build_object(
    'v', 1,
    'business_id', p_business,
    'kind', case lower(btrim(coalesce(p_kind,'')))
      when 'branch' then 'showroom' when 'dealer_branch' then 'showroom'
      when 'sales_point' then 'showroom' when 'warehouse' then 'godown'
      when 'store' then 'godown' else lower(btrim(coalesce(p_kind,''))) end,
    'code_input', nullif(lower(btrim(coalesce(p_code,''))),''),
    'name_bn', nullif(btrim(coalesce(p_name_bn,'')),''),
    'name_en', nullif(btrim(coalesce(p_name_en,'')),''),
    'org_branch', p_org_branch
  );
  select * into op from public.business_place_ops135 where client_id = p_client;
  if found then
    if op.by_user is distinct from me or op.op <> 'create' then raise exception 'client_id_taken'; end if;
    -- Fail closed on old unsigned operations and on any changed business/payload.
    if op.business_id is distinct from p_business or
       op.impact->'c10_create_request_v1' is distinct from c10_payload
       then raise exception 'client_id_payload_mismatch'; end if;
    select l.code, l.status into lc, existing_status from public.locations l where l.id = op.location_id;
    if not found then raise exception 'client_id_location_missing'; end if;
    return jsonb_build_object(
      'dup', true, 'request_matched', true,
      'id', op.location_id, 'code', lc, 'business_id', op.business_id,
      'org_unit_id', op.to_unit, 'kind', op.kind, 'status', existing_status);
  end if;
  select * into b from public.org_units where id = p_business;
  if not found or b.kind <> 'business' then raise exception 'unknown_business'; end if;
  if b.status = 'inactive' then raise exception 'business_inactive'; end if;
  -- kind
  k := lower(btrim(coalesce(p_kind, '')));
  k := case k when 'branch' then 'showroom' when 'dealer_branch' then 'showroom' when 'sales_point' then 'showroom' when 'warehouse' then 'godown' when 'store' then 'godown' else k end;
  if k not in ('showroom', 'factory', 'godown', 'hub', 'online', 'other') then raise exception 'bad_kind'; end if;
  -- names
  nm_bn := nullif(btrim(coalesce(p_name_bn, '')), ''); nm_en := nullif(btrim(coalesce(p_name_en, '')), '');
  if nm_bn is null and nm_en is null then raise exception 'name_required'; end if;
  if length(coalesce(nm_bn, '')) > 120 or length(coalesce(nm_en, '')) > 120 then raise exception 'too_long:name'; end if;
  -- the unit the place hangs on: the business, or a branch / site INSIDE it (a foreign or missing unit answers alike)
  unit_id := p_business;
  if p_org_branch is not null then
    select * into u from public.org_units where id = p_org_branch;
    if not found or u.kind not in ('branch', 'site') or u.status = 'inactive' or public._business_of_unit123(u.id) is distinct from p_business then raise exception 'bad_branch'; end if;
    unit_id := u.id;
  end if;
  -- code: <business code lower case>_<code>
  pre := trim(both '_' from lower(regexp_replace(b.code, '[^A-Za-z0-9]+', '_', 'g')));
  if pre !~ '^[a-z]' then pre := 'b' || pre; end if;
  lc := lower(btrim(coalesce(p_code, '')));
  if lc = '' then
    base := public._slug(coalesce(nm_en, ''));
    if base is null or length(base) < 2 or base !~ '^[a-z]' then base := 'place'; end if;
    lc := base;
  elsif lc !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code';
  end if;
  stored := case when lc like pre || '\_%' then lc else pre || '_' || lc end;
  if nullif(btrim(coalesce(p_code, '')), '') is null then   -- no code given: a free one is found by numbering
    while exists (select 1 from public.locations x where x.code = stored) loop n := n + 1; stored := left(case when lc like pre || '\_%' then lc else pre || '_' || lc end, 26) || '_' || n; end loop;
  end if;
  if length(stored) > 30 then raise exception 'code_too_long'; end if;
  if stored !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code'; end if;
  if exists (select 1 from public.locations x where x.code = stored) then raise exception 'code_in_use'; end if;

  -- the SAME creation path as the Places screen (phase16 location_save), with the token that says "already checked"
  perform set_config('bos.pc135', txid_current()::text, true);
  perform set_config('bos.pc135biz', p_business::text, true);
  perform set_config('bos.pc135unit', unit_id::text, true);
  r := public.location_save(null, jsonb_strip_nulls(jsonb_build_object('name_bn', nm_bn, 'name_en', nm_en, 'kind', k, 'model', 'A', 'code', stored)));
  perform set_config('bos.pc135', '', true); perform set_config('bos.pc135biz', '', true); perform set_config('bos.pc135unit', '', true);
  nid := (r ->> 'id')::int;
  update public.locations set status = 'setting_up', status_by = me, status_at = now() where id = nid;
  insert into public.business_place_ops135 (op, client_id, location_id, business_id, from_unit, to_unit, kind, by_user, impact) values ('create', p_client, nid, p_business, null, unit_id, k, me, jsonb_build_object('c10_create_request_v1', c10_payload));
  perform public.business_profile_ensure135(p_business);
  return jsonb_build_object('dup', false, 'request_matched', true, 'id', nid, 'code', stored, 'business_id', p_business, 'org_unit_id', unit_id, 'kind', k, 'status', 'setting_up');
end $function$;
DO $c10_verify$
DECLARE fn oid := to_regprocedure('public.business_place_create135(bigint,text,text,text,text,bigint,uuid)')::oid;
BEGIN
 IF fn IS NULL OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=fn) THEN
   RAISE EXCEPTION 'c10_a011_security_definer_regressed';
 END IF;
 IF has_function_privilege('anon',fn,'EXECUTE')
     OR NOT has_function_privilege('authenticated',fn,'EXECUTE') THEN
   RAISE EXCEPTION 'c10_a011_function_acl_changed';
 END IF;
END $c10_verify$;
COMMIT;
