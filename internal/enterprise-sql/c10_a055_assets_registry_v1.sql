-- C10-A055 Enterprise Assets & Maintenance (3/7): REGISTRY - grants, categories, codes, assets, assemblies, status,
-- site transfers, meters, warranties, warranty claims and every registry READ.
-- DISPOSABLE c10_demo ONLY. Load after core (and policy). Public API = am_*_v1 (see docs/architecture/C10_A055_RPC_CONTRACT.md);
-- helpers ami_r_* are internal (lockdown file revokes them from authenticated/anon).
-- Conventions: unknown / foreign / not-visible ids => am_denied (never reveals existence); capability missing at a visible site =>
-- am_not_permitted; owner-only => am_owner_required. Money fields (acquisition_cost, claim amounts) are shown only to owner/supervisor/auditor.
-- Extra stable error codes: am_duplicate_grant am_duplicate_code am_duplicate_serial am_serial_required am_duplicate_meter
-- am_category_inactive am_category_cycle am_category_too_deep am_invalid_parent am_parent_site_mismatch am_invalid_state
-- am_invalid_transition am_asset_has_open_wo am_asset_has_open_downtime am_asset_has_children am_transfer_pending
-- am_transfer_has_parent am_transfer_children_required am_transfer_blocked am_transfer_stale am_self_approval_not_allowed
-- am_meter_decrease am_reading_in_future am_reading_out_of_order am_warranty_void am_warranty_has_open_claims
-- am_claim_outside_warranty am_claim_wo_mismatch am_maker_checker_violation.

-- ===================== input helpers (strict, typed, no dynamic SQL) =====================
CREATE FUNCTION c10_demo.ami_r_keys(p jsonb,p_allowed text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text;
BEGIN
 IF p IS NULL OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 FOR k IN SELECT jsonb_object_keys(p) LOOP
  IF NOT (k=ANY(p_allowed)) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 END LOOP;
END$$;
CREATE FUNCTION c10_demo.ami_r_text(p jsonb,k text,p_min int,p_max int,p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v jsonb:=p->k; t text;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN
  IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(v)<>'string' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 t:=btrim(v#>>'{}');
 IF length(t) NOT BETWEEN p_min AND p_max OR t ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN t;
END$$;
CREATE FUNCTION c10_demo.ami_r_num(p jsonb,k text,p_min numeric,p_max numeric,p_req boolean,p_scale int DEFAULT 2) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v jsonb:=p->k; n numeric;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN
  IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(v)<>'number' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 n:=(v#>>'{}')::numeric;
 IF n<p_min OR n>p_max OR n<>round(n,p_scale) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN n;
END$$;
CREATE FUNCTION c10_demo.ami_r_int(p jsonb,k text,p_min bigint,p_max bigint,p_req boolean) RETURNS bigint LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN RETURN c10_demo.ami_r_num(p,k,p_min,p_max,p_req,0)::bigint; END$$;
CREATE FUNCTION c10_demo.ami_r_bool(p jsonb,k text,p_req boolean) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v jsonb:=p->k;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN
  IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(v)<>'boolean' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN (v#>>'{}')::boolean;
END$$;
CREATE FUNCTION c10_demo.ami_r_date(p jsonb,k text,p_req boolean) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v jsonb:=p->k; d date;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN
  IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(v)<>'string' OR (v#>>'{}')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 BEGIN d:=(v#>>'{}')::date; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'am_invalid_input'; END;
 IF d<DATE '1990-01-01' OR d>DATE '2100-12-31' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN d;
END$$;
CREATE FUNCTION c10_demo.ami_r_enum(p jsonb,k text,p_allowed text[],p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text:=c10_demo.ami_r_text(p,k,1,40,p_req);
BEGIN
 IF t IS NOT NULL AND NOT (t=ANY(p_allowed)) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN t;
END$$;
-- code-like identifiers: upper-cased, pattern checked
CREATE FUNCTION c10_demo.ami_r_code(p jsonb,k text,p_max int,p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text:=c10_demo.ami_r_text(p,k,1,p_max,p_req);
BEGIN
 IF t IS NULL THEN RETURN NULL; END IF;
 t:=upper(t);
 IF t !~ ('^[A-Z0-9][A-Z0-9_-]{0,'||(p_max-1)||'}$') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN t;
END$$;
-- reference-like tokens (PO refs, custodian refs)
CREATE FUNCTION c10_demo.ami_r_ref(p jsonb,k text,p_max int) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text:=c10_demo.ami_r_text(p,k,1,p_max,false);
BEGIN
 IF t IS NOT NULL AND t !~ ('^[A-Za-z0-9][A-Za-z0-9._/-]{0,'||(p_max-1)||'}$') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN t;
END$$;
-- custom attributes: flat object, scalar values only, bounded size
CREATE FUNCTION c10_demo.ami_r_attrs(p jsonb,k text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v jsonb:=p->k; e record; n int:=0;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN RETURN '{}'::jsonb; END IF;
 IF jsonb_typeof(v)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 FOR e IN SELECT key,value FROM jsonb_each(v) LOOP
  n:=n+1;
  IF n>40 OR e.key !~ '^[A-Za-z][A-Za-z0-9_]{0,39}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF jsonb_typeof(e.value) NOT IN('string','number','boolean','null') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF jsonb_typeof(e.value)='string' AND (length(e.value#>>'{}')>500 OR (e.value#>>'{}')~'[[:cntrl:]]') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 END LOOP;
 IF pg_column_size(v)>4000 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_r_reason(p text,p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text;
BEGIN
 IF p IS NULL THEN IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 t:=btrim(p);
 IF length(t) NOT BETWEEN 3 AND 500 OR t ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN t;
END$$;
CREATE FUNCTION c10_demo.ami_r_size(p jsonb) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN IF p IS NOT NULL AND length(p::text)>20000 THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END$$;

-- ===================== authority helpers =====================
-- A site id that must belong to this business. Owners learn "invalid input"; everybody else learns nothing (am_denied).
CREATE FUNCTION c10_demo.ami_r_site_chk(c c10_demo.am_ctx_t,p_site bigint) RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF p_site IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_site AND business_id=c.business_id AND tenant_id=c.tenant_id) THEN
  IF c10_demo.ami_is_owner(c) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  RAISE EXCEPTION 'am_denied'; END IF;
END$$;
-- Asset by id, hidden (am_denied) unless the caller holds 'view' at its site; optional capability check; optional row lock.
CREATE FUNCTION c10_demo.ami_r_asset(c c10_demo.am_ctx_t,p_asset bigint,p_cap text,p_lock boolean) RETURNS c10_demo.am_assets
LANGUAGE plpgsql AS $$
DECLARE a c10_demo.am_assets;
BEGIN
 IF p_asset IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_lock THEN SELECT * INTO a FROM c10_demo.am_assets WHERE id=p_asset AND business_id=c.business_id FOR UPDATE;
 ELSE SELECT * INTO a FROM c10_demo.am_assets WHERE id=p_asset AND business_id=c.business_id; END IF;
 IF NOT FOUND OR NOT c10_demo.ami_has(c,a.site_id,'view') THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF p_cap IS NOT NULL THEN PERFORM c10_demo.ami_need_cap(c,a.site_id,p_cap); END IF;
 RETURN a;
END$$;
CREATE FUNCTION c10_demo.ami_r_asset_ro(c c10_demo.am_ctx_t,p_asset bigint) RETURNS c10_demo.am_assets LANGUAGE plpgsql STABLE AS $$
DECLARE a c10_demo.am_assets;
BEGIN
 IF p_asset IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO a FROM c10_demo.am_assets WHERE id=p_asset AND business_id=c.business_id;
 IF NOT FOUND OR NOT c10_demo.ami_has(c,a.site_id,'view') THEN RAISE EXCEPTION 'am_denied'; END IF;
 RETURN a;
END$$;
-- true when meter_write at this site derives ONLY from technician grants (policy access.technician_can_record_meter applies).
CREATE FUNCTION c10_demo.ami_r_tech_only(c c10_demo.am_ctx_t,p_site bigint) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF c.is_tenant_owner OR c.is_business_owner OR c.manager_as_supervisor THEN RETURN false; END IF;
 RETURN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c.grants) g WHERE g->>'role'='supervisor'
   AND ((g->>'site_id') IS NULL OR (g->>'site_id')::bigint=p_site));
END$$;
-- money (cost / claim amounts) is visible to owner, supervisor and auditor only.
CREATE FUNCTION c10_demo.ami_r_money(c c10_demo.am_ctx_t,p_site bigint) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT 'claim_write'=ANY(c10_demo.ami_caps(c,p_site)) OR 'audit_read'=ANY(c10_demo.ami_caps(c,p_site)) $$;
CREATE FUNCTION c10_demo.ami_r_money_sites(c c10_demo.am_ctx_t) RETURNS bigint[] LANGUAGE sql STABLE AS $$
 SELECT COALESCE(array_agg(s.id),ARRAY[]::bigint[]) FROM c10_demo.sites s WHERE s.business_id=c.business_id
  AND ('claim_write'=ANY(c10_demo.ami_caps(c,s.id)) OR 'audit_read'=ANY(c10_demo.ami_caps(c,s.id))) $$;
-- the asset plus all its descendants (assembly tree)
CREATE FUNCTION c10_demo.ami_r_descendants(p_asset bigint) RETURNS bigint[] LANGUAGE sql STABLE AS $$
 WITH RECURSIVE d(id) AS (SELECT p_asset UNION SELECT a.id FROM c10_demo.am_assets a JOIN d ON a.parent_asset_id=d.id)
 SELECT array_agg(id ORDER BY id) FROM d $$;
CREATE FUNCTION c10_demo.ami_r_wstate(p_status text,p_expires date,p_today date,p_warn int) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN p_status='void' THEN 'void' WHEN p_expires<p_today THEN 'expired'
  WHEN p_expires-p_today<=p_warn THEN 'expiring' ELSE 'active' END $$;

-- ===================== grants =====================
CREATE FUNCTION c10_demo.am_grant_role_v1(p_business bigint,p_request text,p_user uuid,p_role text,p_site bigint,p_note text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; g am_grants; res jsonb; v_note text; v_reason text; v_id bigint; v_re boolean:=false; v_before jsonb;
BEGIN
 pay:=jsonb_build_object('user',p_user,'role',p_role,'site',p_site,'note',p_note,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'grant_role',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 v_reason:=ami_r_reason(p_reason,true);
 IF p_user IS NULL OR p_user='00000000-0000-0000-0000-000000000000'::uuid OR p_user=c.user_id THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_role IS NULL OR p_role NOT IN('supervisor','technician','reporter','auditor') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_note IS NOT NULL THEN v_note:=btrim(p_note);
  IF length(v_note) NOT BETWEEN 1 AND 200 OR v_note~'[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
 IF p_site IS NOT NULL THEN PERFORM ami_r_site_chk(c,p_site); END IF;
 SELECT * INTO g FROM am_grants WHERE business_id=p_business AND user_id=p_user AND role=p_role AND COALESCE(site_id,0)=COALESCE(p_site,0) FOR UPDATE;
 IF FOUND THEN
  IF g.active THEN RAISE EXCEPTION 'am_duplicate_grant'; END IF;
  v_before:=to_jsonb(g);
  UPDATE am_grants SET active=true,revoked_by=NULL,revoked_at=NULL,granted_by=c.user_id,granted_at=now(),note=v_note WHERE id=g.id RETURNING * INTO g;
  v_re:=true; v_id:=g.id;
 ELSE
  INSERT INTO am_grants(tenant_id,business_id,user_id,role,site_id,active,note,granted_by)
  VALUES(c.tenant_id,p_business,p_user,p_role,p_site,true,v_note,c.user_id) RETURNING * INTO g; v_id:=g.id;
 END IF;
 res:=jsonb_build_object('status','applied','grant_id',v_id,'reactivated',v_re);
 PERFORM ami_log(c.tenant_id,p_business,'grant',v_id::text,CASE WHEN v_re THEN 'reactivated' ELSE 'granted' END,v_before,to_jsonb(g),v_reason,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'grant_role',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_revoke_role_v1(p_business bigint,p_request text,p_grant bigint,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; g am_grants; res jsonb; v_reason text; v_before jsonb;
BEGIN
 pay:=jsonb_build_object('grant',p_grant,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'revoke_role',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 v_reason:=ami_r_reason(p_reason,true);
 IF p_grant IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO g FROM am_grants WHERE id=p_grant AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF NOT g.active THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 v_before:=to_jsonb(g);
 UPDATE am_grants SET active=false,revoked_by=c.user_id,revoked_at=now() WHERE id=g.id RETURNING * INTO g;
 res:=jsonb_build_object('status','applied','grant_id',g.id);
 PERFORM ami_log(c.tenant_id,p_business,'grant',g.id::text,'revoked',v_before,to_jsonb(g),v_reason,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'revoke_role',pay,res);
END$$;

-- ===================== categories & codes =====================
CREATE FUNCTION c10_demo.ami_r_cat_parent(c c10_demo.am_ctx_t,p_cat bigint,p_parent bigint) RETURNS void LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE par am_categories; cur bigint; d int:=0;
BEGIN
 SELECT * INTO par FROM am_categories WHERE id=p_parent AND business_id=c.business_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF NOT par.active THEN RAISE EXCEPTION 'am_category_inactive'; END IF;
 cur:=p_parent;
 WHILE cur IS NOT NULL LOOP
  d:=d+1;
  IF p_cat IS NOT NULL AND cur=p_cat THEN RAISE EXCEPTION 'am_category_cycle'; END IF;
  IF d>8 THEN RAISE EXCEPTION 'am_category_too_deep'; END IF;
  SELECT parent_id INTO cur FROM am_categories WHERE id=cur;
 END LOOP;
END$$;

CREATE FUNCTION c10_demo.am_save_category_v1(p_business bigint,p_request text,p_id bigint,p_expected_version bigint,p_data jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; cat am_categories; n am_categories; res jsonb; v_reason text; v_before jsonb; v_create boolean;
BEGIN
 PERFORM ami_r_size(p_data);
 pay:=jsonb_build_object('id',p_id,'ver',p_expected_version,'data',p_data,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'save_category',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 v_reason:=ami_r_reason(p_reason,true);
 PERFORM ami_r_keys(p_data,ARRAY['code','name','name_bn','parent_id','asset_kind','default_criticality','default_meter_unit',
   'safety_critical','useful_life_months','salvage_pct','active']);
 v_create:=(p_id IS NULL OR p_id=0);
 IF v_create THEN
  IF p_expected_version IS NOT NULL AND p_expected_version<>0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  n.tenant_id:=c.tenant_id; n.business_id:=p_business; n.is_system:=false; n.version:=1;
  n.code:=ami_r_code(p_data,'code',24,true); n.name:=ami_r_text(p_data,'name',2,80,true);
  n.name_bn:=ami_r_text(p_data,'name_bn',1,80,false);
  n.asset_kind:=COALESCE(ami_r_enum(p_data,'asset_kind',ARRAY['fixed_asset','equipment','tool','vehicle','it','facility','other'],false),'equipment');
  n.default_criticality:=COALESCE(ami_r_int(p_data,'default_criticality',1,5,false),3);
  n.default_meter_unit:=ami_r_enum(p_data,'default_meter_unit',ARRAY['hours','km','cycles','units'],false);
  n.safety_critical:=COALESCE(ami_r_bool(p_data,'safety_critical',false),false);
  n.useful_life_months:=ami_r_int(p_data,'useful_life_months',1,600,false);
  n.salvage_pct:=ami_r_num(p_data,'salvage_pct',0,100,false,2);
  n.active:=COALESCE(ami_r_bool(p_data,'active',false),true);
  n.parent_id:=ami_r_int(p_data,'parent_id',1,9007199254740991,false);
  IF n.parent_id IS NOT NULL THEN PERFORM ami_r_cat_parent(c,NULL,n.parent_id); END IF;
  IF EXISTS(SELECT 1 FROM am_categories WHERE business_id=p_business AND code=n.code) THEN RAISE EXCEPTION 'am_duplicate_code'; END IF;
  BEGIN
   INSERT INTO am_categories(tenant_id,business_id,code,name,name_bn,parent_id,asset_kind,default_criticality,default_meter_unit,
     safety_critical,useful_life_months,salvage_pct,active)
   VALUES(c.tenant_id,p_business,n.code,n.name,n.name_bn,n.parent_id,n.asset_kind,n.default_criticality,n.default_meter_unit,
     n.safety_critical,n.useful_life_months,n.salvage_pct,n.active) RETURNING * INTO cat;
  EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_duplicate_code';
            WHEN check_violation THEN RAISE EXCEPTION 'am_invalid_input'; END;
  res:=jsonb_build_object('status','applied','category_id',cat.id,'version',cat.version);
  PERFORM ami_log(c.tenant_id,p_business,'category',cat.id::text,'created',NULL,to_jsonb(cat),v_reason,p_request);
 ELSE
  IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  SELECT * INTO cat FROM am_categories WHERE id=p_id AND business_id=p_business FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
  IF cat.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
  IF p_data='{}'::jsonb THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  v_before:=to_jsonb(cat); n:=cat;
  IF p_data ? 'code' THEN
   n.code:=ami_r_code(p_data,'code',24,true);
   IF n.code<>cat.code THEN
    IF cat.is_system THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
    IF EXISTS(SELECT 1 FROM am_categories WHERE business_id=p_business AND code=n.code AND id<>cat.id) THEN RAISE EXCEPTION 'am_duplicate_code'; END IF;
   END IF;
  END IF;
  IF p_data ? 'name' THEN n.name:=ami_r_text(p_data,'name',2,80,true); END IF;
  IF p_data ? 'name_bn' THEN n.name_bn:=ami_r_text(p_data,'name_bn',1,80,false); END IF;
  IF p_data ? 'asset_kind' THEN n.asset_kind:=ami_r_enum(p_data,'asset_kind',ARRAY['fixed_asset','equipment','tool','vehicle','it','facility','other'],true); END IF;
  IF p_data ? 'default_criticality' THEN n.default_criticality:=ami_r_int(p_data,'default_criticality',1,5,true); END IF;
  IF p_data ? 'default_meter_unit' THEN n.default_meter_unit:=ami_r_enum(p_data,'default_meter_unit',ARRAY['hours','km','cycles','units'],false); END IF;
  IF p_data ? 'safety_critical' THEN n.safety_critical:=ami_r_bool(p_data,'safety_critical',true); END IF;
  IF p_data ? 'useful_life_months' THEN n.useful_life_months:=ami_r_int(p_data,'useful_life_months',1,600,false); END IF;
  IF p_data ? 'salvage_pct' THEN n.salvage_pct:=ami_r_num(p_data,'salvage_pct',0,100,false,2); END IF;
  IF p_data ? 'active' THEN n.active:=ami_r_bool(p_data,'active',true); END IF;
  IF p_data ? 'parent_id' THEN
   n.parent_id:=ami_r_int(p_data,'parent_id',1,9007199254740991,false);
   IF n.parent_id IS NOT NULL AND n.parent_id IS DISTINCT FROM cat.parent_id THEN PERFORM ami_r_cat_parent(c,cat.id,n.parent_id); END IF;
  END IF;
  BEGIN
   UPDATE am_categories SET code=n.code,name=n.name,name_bn=n.name_bn,parent_id=n.parent_id,asset_kind=n.asset_kind,
     default_criticality=n.default_criticality,default_meter_unit=n.default_meter_unit,safety_critical=n.safety_critical,
     useful_life_months=n.useful_life_months,salvage_pct=n.salvage_pct,active=n.active,version=version+1
   WHERE id=cat.id RETURNING * INTO cat;
  EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_duplicate_code';
            WHEN check_violation THEN RAISE EXCEPTION 'am_invalid_input'; END;
  res:=jsonb_build_object('status','applied','category_id',cat.id,'version',cat.version);
  PERFORM ami_log(c.tenant_id,p_business,'category',cat.id::text,'updated',v_before,to_jsonb(cat),v_reason,p_request);
 END IF;
 RETURN ami_finish(p_business,c.tenant_id,p_request,'save_category',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_save_code_v1(p_business bigint,p_request text,p_kind text,p_code text,p_label text,p_label_bn text,p_active boolean,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; cd am_codes; res jsonb; v_reason text; v_code text; v_label text; v_bn text; v_before jsonb; v_new boolean:=false;
BEGIN
 pay:=jsonb_build_object('kind',p_kind,'code',p_code,'label',p_label,'bn',p_label_bn,'active',p_active,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'save_code',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 v_reason:=ami_r_reason(p_reason,true);
 IF p_kind IS NULL OR p_kind NOT IN('failure','cause','action','downtime_reason','service_category') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_code:=upper(btrim(COALESCE(p_code,'')));
 IF v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_label:=btrim(COALESCE(p_label,''));
 IF length(v_label) NOT BETWEEN 2 AND 80 OR v_label~'[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_label_bn IS NOT NULL THEN v_bn:=btrim(p_label_bn);
  IF length(v_bn) NOT BETWEEN 1 AND 80 OR v_bn~'[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
 IF p_active IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO cd FROM am_codes WHERE business_id=p_business AND kind=p_kind AND code=v_code FOR UPDATE;
 IF FOUND THEN
  v_before:=to_jsonb(cd);
  UPDATE am_codes SET label=v_label,label_bn=v_bn,active=p_active WHERE id=cd.id RETURNING * INTO cd;
 ELSE
  v_new:=true;
  INSERT INTO am_codes(tenant_id,business_id,kind,code,label,label_bn,active) VALUES(c.tenant_id,p_business,p_kind,v_code,v_label,v_bn,p_active) RETURNING * INTO cd;
 END IF;
 res:=jsonb_build_object('status','applied','code_id',cd.id,'created',v_new);
 PERFORM ami_log(c.tenant_id,p_business,'code',cd.id::text,CASE WHEN v_new THEN 'created' ELSE 'updated' END,v_before,to_jsonb(cd),v_reason,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'save_code',pay,res);
END$$;

-- ===================== meters (internal helper) & warranties (parse helper) =====================
CREATE FUNCTION c10_demo.ami_r_meter_ins(c c10_demo.am_ctx_t,p_asset bigint,p_code text,p_unit text,p_reading numeric,p_request text)
RETURNS bigint LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE m am_meters;
BEGIN
 IF EXISTS(SELECT 1 FROM am_meters WHERE asset_id=p_asset AND code=p_code) THEN RAISE EXCEPTION 'am_duplicate_meter'; END IF;
 BEGIN
  INSERT INTO am_meters(tenant_id,business_id,asset_id,code,unit,current_reading,last_reading_at)
  VALUES(c.tenant_id,c.business_id,p_asset,p_code,p_unit,COALESCE(p_reading,0),CASE WHEN p_reading IS NULL THEN NULL ELSE now() END) RETURNING * INTO m;
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_duplicate_meter';
           WHEN check_violation THEN RAISE EXCEPTION 'am_invalid_input'; END;
 IF p_reading IS NOT NULL THEN
  INSERT INTO am_meter_readings(tenant_id,business_id,meter_id,asset_id,reading,kind,read_at,note,recorded_by,request_key)
  VALUES(c.tenant_id,c.business_id,m.id,p_asset,p_reading,'reading',m.last_reading_at,'initial reading',c.user_id,p_request);
 END IF;
 PERFORM ami_log(c.tenant_id,c.business_id,'meter',m.id::text,'created',NULL,to_jsonb(m),NULL,p_request);
 RETURN m.id;
END$$;

-- Parse warranty fields on top of an old row (NULL composite for create). Returns the new values (nothing is written).
CREATE FUNCTION c10_demo.ami_r_warranty_parse(w jsonb,p_old c10_demo.am_warranties) RETURNS c10_demo.am_warranties
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE r am_warranties:=p_old;
BEGIN
 PERFORM ami_r_keys(w,ARRAY['supplier_name','supplier_ref','coverage','starts_on','expires_on','status']);
 IF p_old.id IS NULL AND w ? 'status' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF w ? 'supplier_name' OR p_old.id IS NULL THEN r.supplier_name:=ami_r_text(w,'supplier_name',2,120,true); END IF;
 IF w ? 'supplier_ref' THEN r.supplier_ref:=ami_r_text(w,'supplier_ref',1,60,false); END IF;
 IF w ? 'coverage' THEN r.coverage:=ami_r_text(w,'coverage',1,500,false); END IF;
 IF w ? 'starts_on' OR p_old.id IS NULL THEN r.starts_on:=ami_r_date(w,'starts_on',true); END IF;
 IF w ? 'expires_on' OR p_old.id IS NULL THEN r.expires_on:=ami_r_date(w,'expires_on',true); END IF;
 IF w ? 'status' THEN r.status:=ami_r_enum(w,'status',ARRAY['active','void'],true); END IF;
 IF r.expires_on<r.starts_on THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN r;
END$$;

-- ===================== assets =====================
CREATE FUNCTION c10_demo.am_create_asset_v1(p_business bigint,p_request text,p_data jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; d jsonb; res jsonb; cat am_categories; par am_assets; a am_assets; w am_warranties;
 v_site bigint; v_reason text; v_status text; v_serial text; v_manu text; v_parent bigint; v_attrs jsonb; v_meters jsonb; v_wj jsonb;
 v_crit smallint; v_qty numeric; v_acq date; v_com date; v_con text; v_mid bigint; v_mids bigint[]:=ARRAY[]::bigint[]; v_wid bigint;
 i int; m jsonb; v_codes text[]:=ARRAY[]::text[]; mc text; mu text; mr numeric;
BEGIN
 PERFORM ami_r_size(p_data);
 pay:=jsonb_build_object('data',p_data,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'create_asset',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; d:=p_data;
 IF d IS NULL OR jsonb_typeof(d)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_site:=ami_r_int(d,'site_id',1,9007199254740991,true);
 PERFORM ami_r_site_chk(c,v_site);
 PERFORM ami_need_cap(c,v_site,'asset_write');
 PERFORM ami_r_keys(d,ARRAY['name','category_id','site_id','criticality','status','location_note','serial_no','model','manufacturer',
   'ownership','provenance','supplier_name','supplier_ref','purchase_order_ref','custodian_ref','acquisition_date','commission_date',
   'acquisition_cost','quantity','parent_asset_id','custom_attrs','meters','warranty']);
 v_reason:=COALESCE(ami_r_reason(p_reason,false),'Asset registered');
 SELECT * INTO cat FROM am_categories WHERE id=ami_r_int(d,'category_id',1,9007199254740991,true) AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF NOT cat.active THEN RAISE EXCEPTION 'am_category_inactive'; END IF;
 v_status:=COALESCE(ami_r_enum(d,'status',ARRAY['planned','active','under_maintenance','breakdown','idle','retired','disposed'],false),'active');
 IF v_status NOT IN('planned','active','idle') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_crit:=COALESCE(ami_r_int(d,'criticality',1,5,false),cat.default_criticality);
 v_serial:=ami_r_text(d,'serial_no',1,64,false);
 IF v_serial IS NOT NULL AND v_serial !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_manu:=ami_r_text(d,'manufacturer',1,80,false);
 IF v_serial IS NULL AND ami_cfg_bool(p_business,v_site,cat.id,'asset.require_serial') THEN RAISE EXCEPTION 'am_serial_required'; END IF;
 IF v_serial IS NOT NULL AND EXISTS(SELECT 1 FROM am_assets WHERE business_id=p_business AND lower(COALESCE(manufacturer,''))=lower(COALESCE(v_manu,''))
    AND lower(serial_no)=lower(v_serial) AND status NOT IN('retired','disposed')) THEN RAISE EXCEPTION 'am_duplicate_serial'; END IF;
 v_qty:=COALESCE(ami_r_num(d,'quantity',0.001,99999999999,false,3),1);
 v_acq:=ami_r_date(d,'acquisition_date',false); v_com:=ami_r_date(d,'commission_date',false);
 IF v_acq IS NOT NULL AND v_com IS NOT NULL AND v_com<v_acq THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_attrs:=ami_r_attrs(d,'custom_attrs');
 v_parent:=ami_r_int(d,'parent_asset_id',1,9007199254740991,false);
 IF v_parent IS NOT NULL THEN
  SELECT * INTO par FROM am_assets WHERE id=v_parent AND business_id=p_business FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF par.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_parent'; END IF;
  IF par.site_id<>v_site THEN RAISE EXCEPTION 'am_parent_site_mismatch'; END IF;
 END IF;
 -- embedded meters / warranty are fully validated BEFORE any write
 v_meters:=d->'meters';
 IF v_meters IS NOT NULL AND jsonb_typeof(v_meters)<>'null' THEN
  IF jsonb_typeof(v_meters)<>'array' OR jsonb_array_length(v_meters)>10 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  FOR i IN 0..jsonb_array_length(v_meters)-1 LOOP
   m:=v_meters->i; PERFORM ami_r_keys(m,ARRAY['code','unit','reading']);
   mc:=ami_r_code(m,'code',16,true);
   IF mc=ANY(v_codes) THEN RAISE EXCEPTION 'am_duplicate_meter'; END IF; v_codes:=v_codes||mc;
   mu:=COALESCE(ami_r_enum(m,'unit',ARRAY['hours','km','cycles','units'],false),cat.default_meter_unit);
   IF mu IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   PERFORM ami_r_num(m,'reading',0,99999999999999,false,3);
  END LOOP;
 END IF;
 v_wj:=d->'warranty';
 IF v_wj IS NOT NULL AND jsonb_typeof(v_wj)<>'null' THEN
  IF jsonb_typeof(v_wj)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  w:=ami_r_warranty_parse(v_wj,NULL::am_warranties);
 END IF;
 BEGIN
  INSERT INTO am_assets(tenant_id,business_id,asset_no,name,category_id,status,criticality,site_id,location_note,serial_no,model,manufacturer,
    ownership,provenance,supplier_name,supplier_ref,purchase_order_ref,custodian_ref,acquisition_date,commission_date,acquisition_cost,
    quantity,parent_asset_id,custom_attrs,created_by)
  VALUES(c.tenant_id,p_business,ami_next_no(p_business,'asset'),ami_r_text(d,'name',2,120,true),cat.id,v_status,v_crit,v_site,
    ami_r_text(d,'location_note',1,200,false),v_serial,ami_r_text(d,'model',1,80,false),v_manu,
    COALESCE(ami_r_enum(d,'ownership',ARRAY['owned','leased','rented','client_owned','consignment'],false),'owned'),
    ami_r_text(d,'provenance',1,300,false),ami_r_text(d,'supplier_name',1,120,false),ami_r_text(d,'supplier_ref',1,60,false),
    ami_r_ref(d,'purchase_order_ref',40),ami_r_ref(d,'custodian_ref',40),v_acq,v_com,ami_r_num(d,'acquisition_cost',0,10000000000000,false,2),
    v_qty,v_parent,v_attrs,c.user_id) RETURNING * INTO a;
 EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS v_con=CONSTRAINT_NAME;
   IF v_con='am_assets_serial_uq' THEN RAISE EXCEPTION 'am_duplicate_serial'; END IF; RAISE;
  WHEN check_violation THEN RAISE EXCEPTION 'am_invalid_input';
 END;
 INSERT INTO am_asset_movements(tenant_id,business_id,asset_id,from_site_id,to_site_id,kind,reason,moved_by,request_key)
 VALUES(c.tenant_id,p_business,a.id,NULL,a.site_id,'initial',v_reason,c.user_id,p_request);
 IF v_meters IS NOT NULL AND jsonb_typeof(v_meters)='array' THEN
  FOR i IN 0..jsonb_array_length(v_meters)-1 LOOP
   m:=v_meters->i;
   v_mid:=ami_r_meter_ins(c,a.id,ami_r_code(m,'code',16,true),COALESCE(ami_r_enum(m,'unit',ARRAY['hours','km','cycles','units'],false),cat.default_meter_unit),
     ami_r_num(m,'reading',0,99999999999999,false,3),p_request);
   v_mids:=v_mids||v_mid;
  END LOOP;
 END IF;
 IF w.supplier_name IS NOT NULL THEN
  INSERT INTO am_warranties(tenant_id,business_id,asset_id,supplier_name,supplier_ref,coverage,starts_on,expires_on,created_by)
  VALUES(c.tenant_id,p_business,a.id,w.supplier_name,w.supplier_ref,w.coverage,w.starts_on,w.expires_on,c.user_id) RETURNING id INTO v_wid;
  PERFORM ami_log(c.tenant_id,p_business,'warranty',v_wid::text,'created',NULL,jsonb_build_object('asset_id',a.id,'expires_on',w.expires_on),v_reason,p_request);
 END IF;
 res:=jsonb_build_object('status','applied','asset_id',a.id,'asset_no',a.asset_no,'version',a.version,'meter_ids',to_jsonb(v_mids),'warranty_id',v_wid);
 PERFORM ami_log(c.tenant_id,p_business,'asset',a.id::text,'created',NULL,to_jsonb(a),v_reason,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'create_asset',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_update_asset_v1(p_business bigint,p_request text,p_asset bigint,p_expected_version bigint,p_changes jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; d jsonb; res jsonb; a am_assets; n am_assets; cat am_categories; par am_assets; v_reason text; v_con text; v_before jsonb;
 v_cat bigint;
BEGIN
 PERFORM ami_r_size(p_changes);
 pay:=jsonb_build_object('asset',p_asset,'ver',p_expected_version,'changes',p_changes,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'update_asset',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; d:=p_changes;
 a:=ami_r_asset(c,p_asset,'asset_write',true);
 IF d IS NULL OR jsonb_typeof(d)<>'object' OR d='{}'::jsonb THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_r_keys(d,ARRAY['name','category_id','criticality','location_note','serial_no','model','manufacturer','ownership','provenance',
   'supplier_name','supplier_ref','purchase_order_ref','custodian_ref','acquisition_date','commission_date','acquisition_cost','quantity',
   'parent_asset_id','custom_attrs']);
 IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF a.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 v_reason:=ami_r_reason(p_reason,false);
 v_before:=to_jsonb(a); n:=a;
 IF d ? 'name' THEN n.name:=ami_r_text(d,'name',2,120,true); END IF;
 IF d ? 'category_id' THEN
  v_cat:=ami_r_int(d,'category_id',1,9007199254740991,true);
  IF v_cat<>a.category_id THEN
   SELECT * INTO cat FROM am_categories WHERE id=v_cat AND business_id=p_business;
   IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   IF NOT cat.active THEN RAISE EXCEPTION 'am_category_inactive'; END IF;
   n.category_id:=v_cat;
  END IF;
 END IF;
 IF d ? 'criticality' THEN n.criticality:=ami_r_int(d,'criticality',1,5,true); END IF;
 IF d ? 'location_note' THEN n.location_note:=ami_r_text(d,'location_note',1,200,false); END IF;
 IF d ? 'serial_no' THEN n.serial_no:=ami_r_text(d,'serial_no',1,64,false);
  IF n.serial_no IS NOT NULL AND n.serial_no !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
 IF d ? 'model' THEN n.model:=ami_r_text(d,'model',1,80,false); END IF;
 IF d ? 'manufacturer' THEN n.manufacturer:=ami_r_text(d,'manufacturer',1,80,false); END IF;
 IF d ? 'ownership' THEN n.ownership:=ami_r_enum(d,'ownership',ARRAY['owned','leased','rented','client_owned','consignment'],true); END IF;
 IF d ? 'provenance' THEN n.provenance:=ami_r_text(d,'provenance',1,300,false); END IF;
 IF d ? 'supplier_name' THEN n.supplier_name:=ami_r_text(d,'supplier_name',1,120,false); END IF;
 IF d ? 'supplier_ref' THEN n.supplier_ref:=ami_r_text(d,'supplier_ref',1,60,false); END IF;
 IF d ? 'purchase_order_ref' THEN n.purchase_order_ref:=ami_r_ref(d,'purchase_order_ref',40); END IF;
 IF d ? 'custodian_ref' THEN n.custodian_ref:=ami_r_ref(d,'custodian_ref',40); END IF;
 IF d ? 'acquisition_date' THEN n.acquisition_date:=ami_r_date(d,'acquisition_date',false); END IF;
 IF d ? 'commission_date' THEN n.commission_date:=ami_r_date(d,'commission_date',false); END IF;
 IF d ? 'acquisition_cost' THEN n.acquisition_cost:=ami_r_num(d,'acquisition_cost',0,10000000000000,false,2); END IF;
 IF d ? 'quantity' THEN n.quantity:=ami_r_num(d,'quantity',0.001,99999999999,true,3); END IF;
 IF d ? 'custom_attrs' THEN n.custom_attrs:=ami_r_attrs(d,'custom_attrs'); END IF;
 IF n.acquisition_date IS NOT NULL AND n.commission_date IS NOT NULL AND n.commission_date<n.acquisition_date THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF d ? 'parent_asset_id' THEN
  n.parent_asset_id:=ami_r_int(d,'parent_asset_id',1,9007199254740991,false);
  IF n.parent_asset_id IS NOT NULL AND n.parent_asset_id IS DISTINCT FROM a.parent_asset_id THEN
   IF n.parent_asset_id=a.id THEN RAISE EXCEPTION 'am_assembly_cycle_or_too_deep'; END IF;
   SELECT * INTO par FROM am_assets WHERE id=n.parent_asset_id AND business_id=p_business FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   IF par.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_parent'; END IF;
   IF par.site_id<>a.site_id THEN RAISE EXCEPTION 'am_parent_site_mismatch'; END IF;
   IF a.id=ANY(ami_r_descendants(par.id)) THEN RAISE EXCEPTION 'am_assembly_cycle_or_too_deep'; END IF;
  END IF;
 END IF;
 IF n.serial_no IS NULL AND (d ? 'serial_no' OR d ? 'category_id') AND ami_cfg_bool(p_business,a.site_id,n.category_id,'asset.require_serial') THEN
  RAISE EXCEPTION 'am_serial_required'; END IF;
 IF n.serial_no IS NOT NULL AND (n.serial_no IS DISTINCT FROM a.serial_no OR n.manufacturer IS DISTINCT FROM a.manufacturer)
   AND EXISTS(SELECT 1 FROM am_assets WHERE business_id=p_business AND id<>a.id AND lower(COALESCE(manufacturer,''))=lower(COALESCE(n.manufacturer,''))
     AND lower(serial_no)=lower(n.serial_no) AND status NOT IN('retired','disposed')) THEN RAISE EXCEPTION 'am_duplicate_serial'; END IF;
 BEGIN
  UPDATE am_assets SET name=n.name,category_id=n.category_id,criticality=n.criticality,location_note=n.location_note,serial_no=n.serial_no,
    model=n.model,manufacturer=n.manufacturer,ownership=n.ownership,provenance=n.provenance,supplier_name=n.supplier_name,supplier_ref=n.supplier_ref,
    purchase_order_ref=n.purchase_order_ref,custodian_ref=n.custodian_ref,acquisition_date=n.acquisition_date,commission_date=n.commission_date,
    acquisition_cost=n.acquisition_cost,quantity=n.quantity,parent_asset_id=n.parent_asset_id,custom_attrs=n.custom_attrs,
    version=version+1,updated_at=now() WHERE id=a.id RETURNING * INTO n;
 EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS v_con=CONSTRAINT_NAME;
   IF v_con='am_assets_serial_uq' THEN RAISE EXCEPTION 'am_duplicate_serial'; END IF; RAISE;
  WHEN check_violation THEN RAISE EXCEPTION 'am_invalid_input';
 END;
 res:=jsonb_build_object('status','applied','asset_id',n.id,'version',n.version);
 PERFORM ami_log(c.tenant_id,p_business,'asset',n.id::text,'updated',v_before,to_jsonb(n),v_reason,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'update_asset',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_set_asset_status_v1(p_business bigint,p_request text,p_asset bigint,p_expected_version bigint,p_status text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; res jsonb; a am_assets; n am_assets; v_reason text; v_ok boolean; v_before jsonb;
BEGIN
 pay:=jsonb_build_object('asset',p_asset,'ver',p_expected_version,'status',p_status,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'set_asset_status',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 a:=ami_r_asset(c,p_asset,'asset_write',true);
 v_reason:=ami_r_reason(p_reason,true);
 IF p_status IS NULL OR p_status NOT IN('planned','active','under_maintenance','breakdown','idle','retired','disposed') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF a.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 -- breakdown / under_maintenance are driven only by work-order logic; planned only exists at creation.
 v_ok:=CASE a.status
   WHEN 'planned' THEN p_status IN('active','retired')
   WHEN 'active' THEN p_status IN('idle','retired','disposed')
   WHEN 'idle' THEN p_status IN('active','retired','disposed')
   WHEN 'retired' THEN p_status IN('active','idle','disposed')
   ELSE false END;
 IF NOT v_ok THEN RAISE EXCEPTION 'am_invalid_transition'; END IF;
 IF p_status IN('retired','disposed') THEN
  IF EXISTS(SELECT 1 FROM am_work_orders WHERE asset_id=a.id AND status NOT IN('CLOSED','CANCELLED')) THEN RAISE EXCEPTION 'am_asset_has_open_wo'; END IF;
  IF EXISTS(SELECT 1 FROM am_downtime WHERE asset_id=a.id AND ended_at IS NULL) THEN RAISE EXCEPTION 'am_asset_has_open_downtime'; END IF;
  IF EXISTS(SELECT 1 FROM am_assets WHERE parent_asset_id=a.id AND status NOT IN('retired','disposed')) THEN RAISE EXCEPTION 'am_asset_has_children'; END IF;
  IF EXISTS(SELECT 1 FROM am_transfers WHERE asset_id=a.id AND status='pending') THEN RAISE EXCEPTION 'am_transfer_pending'; END IF;
 END IF;
 v_before:=jsonb_build_object('status',a.status,'version',a.version);
 BEGIN
  UPDATE am_assets SET status=p_status,version=version+1,updated_at=now(),
    retired_at=CASE WHEN p_status IN('retired','disposed') THEN COALESCE(retired_at,now()) WHEN p_status IN('active','idle') THEN NULL ELSE retired_at END,
    commission_date=CASE WHEN a.status='planned' AND p_status='active' THEN COALESCE(commission_date,ami_today(p_business)) ELSE commission_date END
  WHERE id=a.id RETURNING * INTO n;
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_duplicate_serial';
           WHEN check_violation THEN RAISE EXCEPTION 'am_invalid_input'; END;
 res:=jsonb_build_object('status','applied','asset_id',n.id,'from_status',a.status,'to_status',n.status,'version',n.version);
 PERFORM ami_log(c.tenant_id,p_business,'asset',n.id::text,'status_changed',v_before,jsonb_build_object('status',n.status,'version',n.version),v_reason,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'set_asset_status',pay,res);
END$$;

-- ===================== transfers =====================
CREATE FUNCTION c10_demo.ami_r_transfer_blocks(p_business bigint,p_site bigint,p_ids bigint[]) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF ami_cfg_bool(p_business,p_site,NULL,'asset.allow_transfer_with_active_wo') THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM am_work_orders WHERE asset_id=ANY(p_ids) AND status='IN_PROGRESS')
  OR EXISTS(SELECT 1 FROM am_downtime WHERE asset_id=ANY(p_ids) AND ended_at IS NULL) THEN RAISE EXCEPTION 'am_transfer_blocked'; END IF;
END$$;

-- Applies a pending transfer row atomically (asset + all descendants, movements, open WOs follow). Returns moved asset count.
CREATE FUNCTION c10_demo.ami_r_apply_transfer(c c10_demo.am_ctx_t,t c10_demo.am_transfers,p_request text) RETURNS int
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE a am_assets; ids bigint[];
BEGIN
 SELECT * INTO a FROM am_assets WHERE id=t.asset_id AND business_id=t.business_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF a.site_id<>t.from_site_id THEN RAISE EXCEPTION 'am_transfer_stale'; END IF;
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 IF NOT EXISTS(SELECT 1 FROM sites WHERE id=t.to_site_id AND business_id=t.business_id AND tenant_id=t.tenant_id) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 ids:=ami_r_descendants(a.id);
 IF NOT t.include_children AND cardinality(ids)>1 THEN RAISE EXCEPTION 'am_transfer_children_required'; END IF;
 PERFORM ami_r_transfer_blocks(t.business_id,t.from_site_id,ids);
 INSERT INTO am_asset_movements(tenant_id,business_id,asset_id,from_site_id,to_site_id,kind,transfer_id,reason,moved_by,request_key)
  SELECT t.tenant_id,t.business_id,x.id,x.site_id,t.to_site_id,'transfer',t.id,t.reason,c.user_id,p_request
  FROM am_assets x WHERE x.id=ANY(ids) ORDER BY x.id;
 UPDATE am_assets SET site_id=t.to_site_id,version=version+1,updated_at=now() WHERE id=ANY(ids);
 UPDATE am_work_orders SET site_id=t.to_site_id,version=version+1,updated_at=now()
  WHERE asset_id=ANY(ids) AND status IN('DRAFT','SUBMITTED','APPROVED') AND site_id<>t.to_site_id;
 RETURN cardinality(ids);
END$$;

CREATE FUNCTION c10_demo.am_request_transfer_v1(p_business bigint,p_request text,p_asset bigint,p_to_site bigint,p_include_children boolean,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; res jsonb; a am_assets; t am_transfers; v_reason text; v_inc boolean; v_direct boolean; v_moved int:=0; ids bigint[];
BEGIN
 pay:=jsonb_build_object('asset',p_asset,'to',p_to_site,'children',p_include_children,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'request_transfer',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 a:=ami_r_asset(c,p_asset,'transfer',true);
 v_reason:=ami_r_reason(p_reason,true); v_inc:=COALESCE(p_include_children,true);
 PERFORM ami_r_site_chk(c,p_to_site);
 IF p_to_site=a.site_id THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 IF a.parent_asset_id IS NOT NULL THEN RAISE EXCEPTION 'am_transfer_has_parent'; END IF;
 IF EXISTS(SELECT 1 FROM am_transfers WHERE asset_id=a.id AND status='pending') THEN RAISE EXCEPTION 'am_transfer_pending'; END IF;
 ids:=ami_r_descendants(a.id);
 IF NOT v_inc AND cardinality(ids)>1 THEN RAISE EXCEPTION 'am_transfer_children_required'; END IF;
 PERFORM ami_r_transfer_blocks(p_business,a.site_id,ids);
 v_direct:=NOT ami_cfg_bool(p_business,a.site_id,NULL,'asset.transfer_requires_approval') AND ami_has(c,p_to_site,'transfer');
 BEGIN
  INSERT INTO am_transfers(tenant_id,business_id,asset_id,from_site_id,to_site_id,include_children,reason,requested_by)
  VALUES(c.tenant_id,p_business,a.id,a.site_id,p_to_site,v_inc,v_reason,c.user_id) RETURNING * INTO t;
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_transfer_pending'; END;
 PERFORM ami_log(c.tenant_id,p_business,'transfer',t.id::text,'requested',NULL,to_jsonb(t),v_reason,p_request);
 IF v_direct THEN
  v_moved:=ami_r_apply_transfer(c,t,p_request);
  UPDATE am_transfers SET status='applied',decided_by=c.user_id,decided_at=now(),decision_note='applied directly (no approval required)',version=version+1
   WHERE id=t.id RETURNING * INTO t;
  PERFORM ami_log(c.tenant_id,p_business,'transfer',t.id::text,'applied',NULL,to_jsonb(t),v_reason,p_request);
  PERFORM ami_log(c.tenant_id,p_business,'asset',a.id::text,'transferred',jsonb_build_object('site_id',a.site_id),jsonb_build_object('site_id',p_to_site,'moved_assets',v_moved),v_reason,p_request);
 END IF;
 res:=jsonb_build_object('status','applied','transfer_id',t.id,'transfer_status',t.status,'version',t.version,'moved_assets',v_moved);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'request_transfer',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_decide_transfer_v1(p_business bigint,p_request text,p_transfer bigint,p_expected_version bigint,p_decision text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; res jsonb; t am_transfers; v_note text; v_moved int:=0; v_new text; v_before jsonb;
BEGIN
 pay:=jsonb_build_object('transfer',p_transfer,'ver',p_expected_version,'decision',p_decision,'note',p_note);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'decide_transfer',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 IF p_transfer IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO t FROM am_transfers WHERE id=p_transfer AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT (ami_has(c,t.from_site_id,'view') OR ami_has(c,t.to_site_id,'view')) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN('approve','reject','cancel') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_note IS NOT NULL THEN v_note:=btrim(p_note);
  IF length(v_note) NOT BETWEEN 1 AND 500 OR v_note~'[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
 IF p_decision='approve' THEN
  IF NOT (ami_has(c,t.from_site_id,'transfer') AND ami_has(c,t.to_site_id,'transfer')) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 ELSIF p_decision='reject' THEN
  IF NOT (ami_has(c,t.from_site_id,'transfer') OR ami_has(c,t.to_site_id,'transfer')) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 ELSE
  IF NOT (t.requested_by=c.user_id OR ami_is_owner(c) OR ami_has(c,t.from_site_id,'transfer')) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 END IF;
 IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF t.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 IF t.status<>'pending' THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 IF p_decision='approve' AND t.requested_by=c.user_id AND NOT ami_is_owner(c) THEN RAISE EXCEPTION 'am_self_approval_not_allowed'; END IF;
 v_before:=to_jsonb(t);
 IF p_decision='approve' THEN v_moved:=ami_r_apply_transfer(c,t,p_request); v_new:='applied';
 ELSIF p_decision='reject' THEN v_new:='rejected'; ELSE v_new:='cancelled'; END IF;
 UPDATE am_transfers SET status=v_new,decided_by=c.user_id,decided_at=now(),decision_note=v_note,version=version+1 WHERE id=t.id RETURNING * INTO t;
 res:=jsonb_build_object('status','applied','transfer_id',t.id,'transfer_status',t.status,'version',t.version,'moved_assets',v_moved);
 PERFORM ami_log(c.tenant_id,p_business,'transfer',t.id::text,v_new,v_before,to_jsonb(t),v_note,p_request);
 IF v_new='applied' THEN
  PERFORM ami_log(c.tenant_id,p_business,'asset',t.asset_id::text,'transferred',jsonb_build_object('site_id',t.from_site_id),
   jsonb_build_object('site_id',t.to_site_id,'moved_assets',v_moved),v_note,p_request); END IF;
 RETURN ami_finish(p_business,c.tenant_id,p_request,'decide_transfer',pay,res);
END$$;

-- ===================== meters =====================
CREATE FUNCTION c10_demo.am_add_meter_v1(p_business bigint,p_request text,p_asset bigint,p_code text,p_unit text,p_initial_reading numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; res jsonb; a am_assets; v_code text; v_id bigint;
BEGIN
 pay:=jsonb_build_object('asset',p_asset,'code',p_code,'unit',p_unit,'initial',p_initial_reading);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'add_meter',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 a:=ami_r_asset(c,p_asset,'asset_write',true);
 v_code:=upper(btrim(COALESCE(p_code,'')));
 IF v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,15}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_unit IS NULL OR p_unit NOT IN('hours','km','cycles','units') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_initial_reading IS NOT NULL AND (p_initial_reading<0 OR p_initial_reading>99999999999999 OR p_initial_reading<>round(p_initial_reading,3)) THEN
  RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 v_id:=ami_r_meter_ins(c,a.id,v_code,p_unit,p_initial_reading,p_request);
 res:=jsonb_build_object('status','applied','meter_id',v_id,'asset_id',a.id,'code',v_code);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'add_meter',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_record_meter_reading_v1(p_business bigint,p_request text,p_meter bigint,p_reading numeric,p_read_at timestamptz,p_kind text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; res jsonb; m am_meters; a am_assets; v_kind text; v_note text; v_at timestamptz; v_rid bigint; v_before jsonb;
BEGIN
 pay:=jsonb_build_object('meter',p_meter,'reading',p_reading,'read_at',p_read_at,'kind',p_kind,'note',p_note);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'record_meter_reading',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 IF p_meter IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO m FROM am_meters WHERE id=p_meter AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 a:=ami_r_asset(c,m.asset_id,'meter_write',false);
 IF ami_r_tech_only(c,a.site_id) AND NOT ami_cfg_bool(p_business,a.site_id,a.category_id,'access.technician_can_record_meter') THEN
  RAISE EXCEPTION 'am_not_permitted'; END IF;
 v_kind:=COALESCE(p_kind,'reading');
 IF v_kind NOT IN('reading','reset') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_reading IS NULL OR p_reading<0 OR p_reading>99999999999999 OR p_reading<>round(p_reading,3) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_note IS NOT NULL THEN v_note:=btrim(p_note);
  IF length(v_note) NOT BETWEEN 1 AND 300 OR v_note~'[[:cntrl:]]' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
 IF v_kind='reset' AND (v_note IS NULL OR length(v_note)<3) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF NOT m.active OR a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
 v_at:=COALESCE(p_read_at,now());
 IF v_at>now()+interval '5 minutes' THEN RAISE EXCEPTION 'am_reading_in_future'; END IF;
 IF m.last_reading_at IS NOT NULL AND v_at<m.last_reading_at THEN RAISE EXCEPTION 'am_reading_out_of_order'; END IF;
 IF v_kind='reading' AND p_reading<m.current_reading AND NOT ami_cfg_bool(p_business,a.site_id,a.category_id,'meter.allow_decrease') THEN
  RAISE EXCEPTION 'am_meter_decrease'; END IF;
 v_before:=jsonb_build_object('current_reading',m.current_reading,'last_reading_at',m.last_reading_at,'version',m.version);
 INSERT INTO am_meter_readings(tenant_id,business_id,meter_id,asset_id,reading,kind,read_at,note,recorded_by,request_key)
 VALUES(c.tenant_id,p_business,m.id,m.asset_id,p_reading,v_kind,v_at,v_note,c.user_id,p_request) RETURNING id INTO v_rid;
 UPDATE am_meters SET current_reading=p_reading,last_reading_at=v_at,version=version+1 WHERE id=m.id RETURNING * INTO m;
 res:=jsonb_build_object('status','applied','meter_id',m.id,'reading_id',v_rid,'current_reading',m.current_reading,'version',m.version);
 PERFORM ami_log(c.tenant_id,p_business,'meter',m.id::text,CASE WHEN v_kind='reset' THEN 'reset' ELSE 'reading' END,v_before,
   jsonb_build_object('current_reading',m.current_reading,'last_reading_at',m.last_reading_at,'version',m.version),v_note,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'record_meter_reading',pay,res);
END$$;

-- ===================== warranties & claims =====================
CREATE FUNCTION c10_demo.am_save_warranty_v1(p_business bigint,p_request text,p_id bigint,p_expected_version bigint,p_data jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; res jsonb; a am_assets; w am_warranties; n am_warranties; v_reason text; v_before jsonb; v_asset bigint;
BEGIN
 PERFORM ami_r_size(p_data);
 pay:=jsonb_build_object('id',p_id,'ver',p_expected_version,'data',p_data,'reason',p_reason);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'save_warranty',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_id IS NULL OR p_id=0 THEN
  v_asset:=ami_r_int(p_data,'asset_id',1,9007199254740991,true);
  a:=ami_r_asset(c,v_asset,'warranty_write',true);
  v_reason:=ami_r_reason(p_reason,false);
  IF p_expected_version IS NOT NULL AND p_expected_version<>0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  PERFORM ami_r_keys(p_data,ARRAY['asset_id','supplier_name','supplier_ref','coverage','starts_on','expires_on']);
  n:=ami_r_warranty_parse(p_data-'asset_id',NULL::am_warranties);
  INSERT INTO am_warranties(tenant_id,business_id,asset_id,supplier_name,supplier_ref,coverage,starts_on,expires_on,created_by)
  VALUES(c.tenant_id,p_business,a.id,n.supplier_name,n.supplier_ref,n.coverage,n.starts_on,n.expires_on,c.user_id) RETURNING * INTO w;
  res:=jsonb_build_object('status','applied','warranty_id',w.id,'version',w.version);
  PERFORM ami_log(c.tenant_id,p_business,'warranty',w.id::text,'created',NULL,to_jsonb(w),v_reason,p_request);
 ELSE
  SELECT * INTO w FROM am_warranties WHERE id=p_id AND business_id=p_business FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
  a:=ami_r_asset(c,w.asset_id,'warranty_write',true);
  v_reason:=ami_r_reason(p_reason,false);
  IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF w.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
  IF p_data='{}'::jsonb THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF w.status='void' THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
  n:=ami_r_warranty_parse(p_data,w);
  IF n.status='void' AND EXISTS(SELECT 1 FROM am_warranty_claims WHERE warranty_id=w.id AND status IN('draft','submitted','accepted')) THEN
   RAISE EXCEPTION 'am_warranty_has_open_claims'; END IF;
  v_before:=to_jsonb(w);
  UPDATE am_warranties SET supplier_name=n.supplier_name,supplier_ref=n.supplier_ref,coverage=n.coverage,starts_on=n.starts_on,expires_on=n.expires_on,
    status=n.status,version=version+1 WHERE id=w.id RETURNING * INTO w;
  res:=jsonb_build_object('status','applied','warranty_id',w.id,'version',w.version);
  PERFORM ami_log(c.tenant_id,p_business,'warranty',w.id::text,CASE WHEN w.status='void' THEN 'voided' ELSE 'updated' END,v_before,to_jsonb(w),v_reason,p_request);
 END IF;
 RETURN ami_finish(p_business,c.tenant_id,p_request,'save_warranty',pay,res);
END$$;

-- claim window check (shared by create / edit / submit)
CREATE FUNCTION c10_demo.ami_r_claim_window(p_business bigint,w c10_demo.am_warranties,a c10_demo.am_assets,p_failure date) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE grace int;
BEGIN
 IF w.status='void' THEN RAISE EXCEPTION 'am_warranty_void'; END IF;
 grace:=ami_cfg_int(p_business,a.site_id,a.category_id,'asset.warranty_claim_grace_days');
 IF p_failure<w.starts_on OR p_failure>w.expires_on+grace THEN RAISE EXCEPTION 'am_claim_outside_warranty'; END IF;
END$$;

CREATE FUNCTION c10_demo.am_save_claim_v1(p_business bigint,p_request text,p_id bigint,p_expected_version bigint,p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; d jsonb; res jsonb; a am_assets; w am_warranties; cl am_warranty_claims; n am_warranty_claims; v_wo am_work_orders; v_before jsonb;
BEGIN
 PERFORM ami_r_size(p_data);
 pay:=jsonb_build_object('id',p_id,'ver',p_expected_version,'data',p_data);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'save_claim',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; d:=p_data;
 IF d IS NULL OR jsonb_typeof(d)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_id IS NULL OR p_id=0 THEN
  IF p_expected_version IS NOT NULL AND p_expected_version<>0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF ami_r_int(d,'warranty_id',1,9007199254740991,true) IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  SELECT * INTO w FROM am_warranties WHERE id=(d->>'warranty_id')::bigint AND business_id=p_business FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
  a:=ami_r_asset(c,w.asset_id,'claim_write',true);
  PERFORM ami_r_keys(d,ARRAY['warranty_id','failure_on','description','work_order_id','amount_claimed','supplier_claim_ref']);
  n.failure_on:=ami_r_date(d,'failure_on',true);
  IF n.failure_on>ami_today(p_business) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  n.description:=ami_r_text(d,'description',3,1000,true);
  n.amount_claimed:=ami_r_num(d,'amount_claimed',0,10000000000000,false,2);
  n.supplier_claim_ref:=ami_r_text(d,'supplier_claim_ref',1,60,false);
  n.work_order_id:=ami_r_int(d,'work_order_id',1,9007199254740991,false);
  PERFORM ami_r_claim_window(p_business,w,a,n.failure_on);
  IF n.work_order_id IS NOT NULL THEN
   SELECT * INTO v_wo FROM am_work_orders WHERE id=n.work_order_id AND business_id=p_business;
   IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   IF v_wo.asset_id<>a.id THEN RAISE EXCEPTION 'am_claim_wo_mismatch'; END IF;
  END IF;
  INSERT INTO am_warranty_claims(tenant_id,business_id,claim_no,warranty_id,asset_id,work_order_id,failure_on,description,amount_claimed,supplier_claim_ref,created_by)
  VALUES(c.tenant_id,p_business,ami_next_no(p_business,'claim'),w.id,a.id,n.work_order_id,n.failure_on,n.description,n.amount_claimed,n.supplier_claim_ref,c.user_id)
  RETURNING * INTO cl;
  res:=jsonb_build_object('status','applied','claim_id',cl.id,'claim_no',cl.claim_no,'version',cl.version);
  PERFORM ami_log(c.tenant_id,p_business,'claim',cl.id::text,'created',NULL,to_jsonb(cl),NULL,p_request);
 ELSE
  SELECT * INTO cl FROM am_warranty_claims WHERE id=p_id AND business_id=p_business FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
  a:=ami_r_asset(c,cl.asset_id,'claim_write',true);
  IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF cl.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
  PERFORM ami_r_keys(d,ARRAY['failure_on','description','work_order_id','amount_claimed','supplier_claim_ref']);
  IF d='{}'::jsonb THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF cl.status<>'draft' THEN RAISE EXCEPTION 'am_invalid_state'; END IF;
  v_before:=to_jsonb(cl); n:=cl;
  IF d ? 'failure_on' THEN n.failure_on:=ami_r_date(d,'failure_on',true);
   IF n.failure_on>ami_today(p_business) THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
  IF d ? 'description' THEN n.description:=ami_r_text(d,'description',3,1000,true); END IF;
  IF d ? 'amount_claimed' THEN n.amount_claimed:=ami_r_num(d,'amount_claimed',0,10000000000000,false,2); END IF;
  IF d ? 'supplier_claim_ref' THEN n.supplier_claim_ref:=ami_r_text(d,'supplier_claim_ref',1,60,false); END IF;
  IF d ? 'work_order_id' THEN n.work_order_id:=ami_r_int(d,'work_order_id',1,9007199254740991,false);
   IF n.work_order_id IS NOT NULL THEN
    SELECT * INTO v_wo FROM am_work_orders WHERE id=n.work_order_id AND business_id=p_business;
    IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
    IF v_wo.asset_id<>a.id THEN RAISE EXCEPTION 'am_claim_wo_mismatch'; END IF;
   END IF; END IF;
  SELECT * INTO w FROM am_warranties WHERE id=cl.warranty_id;
  PERFORM ami_r_claim_window(p_business,w,a,n.failure_on);
  UPDATE am_warranty_claims SET failure_on=n.failure_on,description=n.description,amount_claimed=n.amount_claimed,
   supplier_claim_ref=n.supplier_claim_ref,work_order_id=n.work_order_id,version=version+1 WHERE id=cl.id RETURNING * INTO cl;
  res:=jsonb_build_object('status','applied','claim_id',cl.id,'claim_no',cl.claim_no,'version',cl.version);
  PERFORM ami_log(c.tenant_id,p_business,'claim',cl.id::text,'updated',v_before,to_jsonb(cl),NULL,p_request);
 END IF;
 RETURN ami_finish(p_business,c.tenant_id,p_request,'save_claim',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_claim_transition_v1(p_business bigint,p_request text,p_claim bigint,p_expected_version bigint,p_action text,p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; d jsonb; res jsonb; a am_assets; w am_warranties; cl am_warranty_claims; v_before jsonb; v_new text; v_note text;
 v_ref text; v_amt numeric; v_set_amt boolean:=false; v_set_claimed boolean:=false; v_claimed numeric;
BEGIN
 PERFORM ami_r_size(p_data);
 pay:=jsonb_build_object('claim',p_claim,'ver',p_expected_version,'action',p_action,'data',p_data);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'claim_transition',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; d:=COALESCE(p_data,'{}'::jsonb);
 IF p_claim IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO cl FROM am_warranty_claims WHERE id=p_claim AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 a:=ami_r_asset(c,cl.asset_id,'claim_write',true);
 IF p_action IS NULL OR p_action NOT IN('submit','accept','reject','settle','close') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF jsonb_typeof(d)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_r_keys(d,CASE p_action WHEN 'submit' THEN ARRAY['supplier_claim_ref','amount_claimed']
   WHEN 'settle' THEN ARRAY['amount_settled','decision_note','supplier_claim_ref'] ELSE ARRAY['decision_note','supplier_claim_ref'] END);
 IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF cl.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 v_note:=ami_r_text(d,'decision_note',3,1000,p_action='reject');
 v_ref:=ami_r_text(d,'supplier_claim_ref',1,60,false);
 v_new:=CASE p_action WHEN 'submit' THEN 'submitted' WHEN 'accept' THEN 'accepted' WHEN 'reject' THEN 'rejected'
   WHEN 'settle' THEN 'settled' ELSE 'closed' END;
 IF NOT ((cl.status='draft' AND p_action='submit') OR (cl.status='submitted' AND p_action IN('accept','reject'))
   OR (cl.status='accepted' AND p_action='settle') OR (cl.status IN('settled','rejected') AND p_action='close')) THEN
  RAISE EXCEPTION 'am_invalid_state'; END IF;
 IF p_action='accept' AND cl.submitted_by=c.user_id AND ami_cfg_bool(p_business,NULL,NULL,'wo.maker_checker') THEN
  RAISE EXCEPTION 'am_maker_checker_violation'; END IF;
 IF p_action='submit' THEN
  SELECT * INTO w FROM am_warranties WHERE id=cl.warranty_id;
  PERFORM ami_r_claim_window(p_business,w,a,cl.failure_on);
  IF d ? 'amount_claimed' THEN v_claimed:=ami_r_num(d,'amount_claimed',0,10000000000000,false,2); v_set_claimed:=true; END IF;
 END IF;
 IF p_action='settle' AND d ? 'amount_settled' THEN v_amt:=ami_r_num(d,'amount_settled',0,10000000000000,false,2); v_set_amt:=true; END IF;
 v_before:=to_jsonb(cl);
 UPDATE am_warranty_claims SET status=v_new,version=version+1,
   supplier_claim_ref=COALESCE(v_ref,supplier_claim_ref),
   amount_claimed=CASE WHEN v_set_claimed THEN v_claimed ELSE amount_claimed END,
   amount_settled=CASE WHEN v_set_amt THEN v_amt ELSE amount_settled END,
   decision_note=COALESCE(v_note,decision_note),
   submitted_by=CASE WHEN p_action='submit' THEN c.user_id ELSE submitted_by END,
   submitted_at=CASE WHEN p_action='submit' THEN now() ELSE submitted_at END,
   decided_by=CASE WHEN p_action IN('accept','reject') THEN c.user_id ELSE decided_by END,
   decided_at=CASE WHEN p_action IN('accept','reject') THEN now() ELSE decided_at END
 WHERE id=cl.id RETURNING * INTO cl;
 res:=jsonb_build_object('status','applied','claim_id',cl.id,'claim_status',cl.status,'version',cl.version);
 PERFORM ami_log(c.tenant_id,p_business,'claim',cl.id::text,v_new,v_before,to_jsonb(cl),v_note,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'claim_transition',pay,res);
END$$;

-- ===================== READS (STABLE, never write; filtered by sites where the caller holds 'view') =====================
CREATE FUNCTION c10_demo.am_list_grants_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; items jsonb;
BEGIN
 c:=ami_read_ctx(p_business); PERFORM ami_need_owner(c);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',g.id,'user_id',g.user_id,'role',g.role,'site_id',g.site_id,'active',g.active,'note',g.note,
   'granted_by',g.granted_by,'granted_at',g.granted_at,'revoked_by',g.revoked_by,'revoked_at',g.revoked_at) ORDER BY g.id),'[]'::jsonb) INTO items
 FROM am_grants g WHERE g.business_id=p_business;
 RETURN jsonb_build_object('items',items,'total',jsonb_array_length(items));
END$$;

CREATE FUNCTION c10_demo.am_list_catalog_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; sites bigint[]; cats jsonb; cds jsonb; ss jsonb; ab jsonb;
BEGIN
 c:=ami_read_ctx(p_business); sites:=ami_sites_with(c,'view');
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',k.id,'code',k.code,'name',k.name,'name_bn',k.name_bn,'parent_id',k.parent_id,'asset_kind',k.asset_kind,
   'default_criticality',k.default_criticality,'default_meter_unit',k.default_meter_unit,'safety_critical',k.safety_critical,
   'useful_life_months',k.useful_life_months,'salvage_pct',k.salvage_pct,'active',k.active,'is_system',k.is_system,'version',k.version) ORDER BY k.code),'[]'::jsonb)
  INTO cats FROM am_categories k WHERE k.business_id=p_business;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'code',x.code,'label',x.label,'label_bn',x.label_bn,'active',x.active,'is_system',x.is_system)
   ORDER BY x.kind,x.code),'[]'::jsonb) INTO cds FROM am_codes x WHERE x.business_id=p_business;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'label',s.label,'kind',s.kind,'capabilities',to_jsonb(ami_caps(c,s.id))) ORDER BY s.id),'[]'::jsonb)
  INTO ss FROM sites s WHERE s.business_id=p_business AND s.id=ANY(sites);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'asset_no',a.asset_no,'name',a.name,'site_id',a.site_id,'status',a.status,
   'category_id',a.category_id,'parent_asset_id',a.parent_asset_id) ORDER BY a.asset_no),'[]'::jsonb) INTO ab
  FROM (SELECT * FROM am_assets WHERE business_id=p_business AND site_id=ANY(sites) ORDER BY asset_no LIMIT 500) a;
 RETURN jsonb_build_object('categories',cats,'codes',cds,'sites',ss,'assets_brief',ab);
END$$;

CREATE FUNCTION c10_demo.am_list_assets_v1(p_business bigint,p_filters jsonb,p_limit int,p_offset int) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; f jsonb:=COALESCE(p_filters,'{}'::jsonb); sites bigint[]; msites bigint[]; v_search text; v_like text; v_status text; v_cat bigint; v_site bigint;
 v_parent bigint; v_own text; ids bigint[]; v_lim int; v_off int; page bigint[]; items jsonb;
BEGIN
 c:=ami_read_ctx(p_business);
 sites:=ami_sites_with(c,'view'); msites:=ami_r_money_sites(c);
 PERFORM ami_r_keys(f,ARRAY['search','status','category_id','site_id','parent_asset_id','ownership']);
 v_search:=ami_r_text(f,'search',1,100,false);
 v_status:=ami_r_enum(f,'status',ARRAY['planned','active','under_maintenance','breakdown','idle','retired','disposed'],false);
 v_cat:=ami_r_int(f,'category_id',1,9007199254740991,false); v_site:=ami_r_int(f,'site_id',1,9007199254740991,false);
 v_parent:=ami_r_int(f,'parent_asset_id',0,9007199254740991,false);
 v_own:=ami_r_enum(f,'ownership',ARRAY['owned','leased','rented','client_owned','consignment'],false);
 v_lim:=LEAST(GREATEST(COALESCE(p_limit,50),1),200); v_off:=GREATEST(COALESCE(p_offset,0),0);
 IF v_search IS NOT NULL THEN v_like:='%'||regexp_replace(v_search,'([\\%_])','\\\1','g')||'%'; END IF;
 SELECT COALESCE(array_agg(a.id ORDER BY a.asset_no,a.id),ARRAY[]::bigint[]) INTO ids FROM am_assets a
  WHERE a.business_id=p_business AND a.site_id=ANY(sites) AND (v_status IS NULL OR a.status=v_status) AND (v_cat IS NULL OR a.category_id=v_cat)
   AND (v_site IS NULL OR a.site_id=v_site) AND (v_own IS NULL OR a.ownership=v_own)
   AND (v_parent IS NULL OR (v_parent=0 AND a.parent_asset_id IS NULL) OR a.parent_asset_id=v_parent)
   AND (v_search IS NULL OR a.name ILIKE v_like OR a.asset_no ILIKE v_like OR a.serial_no ILIKE v_like OR a.model ILIKE v_like OR a.manufacturer ILIKE v_like);
 page:=ids[v_off+1:v_off+v_lim];
 SELECT COALESCE(jsonb_agg(q.item ORDER BY q.ord),'[]'::jsonb) INTO items FROM (
  SELECT x.ord,jsonb_build_object('id',a.id,'asset_no',a.asset_no,'name',a.name,'category_id',a.category_id,'category_code',k.code,'category_name',k.name,
    'status',a.status,'criticality',a.criticality,'site_id',a.site_id,'site_label',s.label,'location_note',a.location_note,'serial_no',a.serial_no,
    'model',a.model,'manufacturer',a.manufacturer,'ownership',a.ownership,'parent_asset_id',a.parent_asset_id,'quantity',a.quantity,
    'commission_date',a.commission_date,'version',a.version,
    'open_work_orders',(SELECT count(*) FROM am_work_orders w WHERE w.asset_id=a.id AND w.status NOT IN('CLOSED','CANCELLED')),
    'open_downtime',EXISTS(SELECT 1 FROM am_downtime d WHERE d.asset_id=a.id AND d.ended_at IS NULL))
   || CASE WHEN a.site_id=ANY(msites) THEN jsonb_build_object('acquisition_cost',a.acquisition_cost) ELSE '{}'::jsonb END AS item
  FROM unnest(page) WITH ORDINALITY x(id,ord) JOIN am_assets a ON a.id=x.id JOIN am_categories k ON k.id=a.category_id JOIN sites s ON s.id=a.site_id) q;
 RETURN jsonb_build_object('items',items,'total',cardinality(ids),'limit',v_lim,'offset',v_off);
END$$;

CREATE FUNCTION c10_demo.am_get_asset_v1(p_business bigint,p_asset bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; a am_assets; k am_categories; money boolean; today date; warn int; stale int; j_asset jsonb; j_children jsonb; j_meters jsonb; j_war jsonb;
 j_mov jsonb; j_wo jsonb; j_pt jsonb; j_dt jsonb; j_cal jsonb; j_claims jsonb; j_tr jsonb; j_parent jsonb; j_site jsonb;
BEGIN
 c:=ami_read_ctx(p_business);
 a:=ami_r_asset_ro(c,p_asset);
 money:=ami_r_money(c,a.site_id); today:=ami_today(p_business);
 warn:=ami_cfg_int(p_business,a.site_id,a.category_id,'asset.warranty_warn_days');
 stale:=ami_cfg_int(p_business,a.site_id,a.category_id,'meter.stale_days');
 SELECT * INTO k FROM am_categories WHERE id=a.category_id;
 j_asset:=to_jsonb(a)-'tenant_id'-'created_by';
 IF NOT money THEN j_asset:=j_asset-'acquisition_cost'; END IF;
 SELECT jsonb_build_object('id',id,'label',label,'kind',kind) INTO j_site FROM sites WHERE id=a.site_id;
 SELECT jsonb_build_object('id',id,'asset_no',asset_no,'name',name,'status',status) INTO j_parent FROM am_assets WHERE id=a.parent_asset_id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'asset_no',x.asset_no,'name',x.name,'status',x.status,'site_id',x.site_id,'quantity',x.quantity,'version',x.version) ORDER BY x.asset_no),'[]'::jsonb)
  INTO j_children FROM (SELECT * FROM am_assets WHERE parent_asset_id=a.id ORDER BY asset_no LIMIT 200) x;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',m.id,'code',m.code,'unit',m.unit,'current_reading',m.current_reading,'last_reading_at',m.last_reading_at,
   'active',m.active,'version',m.version,'stale_days',stale,
   'stale',(m.last_reading_at IS NULL OR m.last_reading_at<now()-make_interval(days=>stale))) ORDER BY m.code),'[]'::jsonb) INTO j_meters FROM am_meters m WHERE m.asset_id=a.id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',w.id,'supplier_name',w.supplier_name,'supplier_ref',w.supplier_ref,'coverage',w.coverage,'starts_on',w.starts_on,
   'expires_on',w.expires_on,'status',w.status,'state',ami_r_wstate(w.status,w.expires_on,today,warn),'days_left',w.expires_on-today,'version',w.version) ORDER BY w.expires_on DESC,w.id),'[]'::jsonb)
  INTO j_war FROM am_warranties w WHERE w.asset_id=a.id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'from_site_id',x.from_site_id,'to_site_id',x.to_site_id,'kind',x.kind,'transfer_id',x.transfer_id,
   'reason',x.reason,'moved_by',x.moved_by,'moved_at',x.moved_at) ORDER BY x.id DESC),'[]'::jsonb)
  INTO j_mov FROM (SELECT * FROM am_asset_movements WHERE asset_id=a.id ORDER BY id DESC LIMIT 50) x;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',w.id,'wo_no',w.wo_no,'kind',w.kind,'status',w.status,'priority',w.priority,'title',w.title,'due_on',w.due_on,
   'site_id',w.site_id,'assigned_to',w.assigned_to) ORDER BY w.id DESC),'[]'::jsonb)
  INTO j_wo FROM am_work_orders w WHERE w.asset_id=a.id AND w.status NOT IN('CLOSED','CANCELLED');
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'plan_id',t.plan_id,'plan_name',p.name,'plan_type',p.plan_type,'frequency_kind',p.frequency_kind,
   'next_due_on',t.next_due_on,'next_due_reading',t.next_due_reading,'last_done_on',t.last_done_on,'last_done_reading',t.last_done_reading,
   'deferred_until',t.deferred_until,'status',t.status) ORDER BY t.id),'[]'::jsonb)
  INTO j_pt FROM am_plan_targets t JOIN am_plans p ON p.id=t.plan_id WHERE t.asset_id=a.id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'kind',d.kind,'reason_code',d.reason_code,'impact',d.impact,'started_at',d.started_at,
   'work_order_id',d.work_order_id,'site_id',d.site_id) ORDER BY d.id),'[]'::jsonb)
  INTO j_dt FROM am_downtime d WHERE d.asset_id=a.id AND d.ended_at IS NULL;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'plan_kind',x.plan_kind,'performed_on',x.performed_on,'next_due_on',x.next_due_on,'result',x.result,
   'certificate_ref',x.certificate_ref,'standard_ref',x.standard_ref,'vendor',x.vendor,'note',x.note,'work_order_id',x.work_order_id) ORDER BY x.performed_on DESC,x.id DESC),'[]'::jsonb)
  INTO j_cal FROM (SELECT * FROM am_cal_records WHERE asset_id=a.id ORDER BY performed_on DESC,id DESC LIMIT 20) x;
 SELECT COALESCE(jsonb_agg((jsonb_build_object('id',x.id,'claim_no',x.claim_no,'warranty_id',x.warranty_id,'work_order_id',x.work_order_id,'failure_on',x.failure_on,
   'description',x.description,'status',x.status,'supplier_claim_ref',x.supplier_claim_ref,'decision_note',x.decision_note,'version',x.version)
   || CASE WHEN money THEN jsonb_build_object('amount_claimed',x.amount_claimed,'amount_settled',x.amount_settled) ELSE '{}'::jsonb END) ORDER BY x.id DESC),'[]'::jsonb)
  INTO j_claims FROM (SELECT * FROM am_warranty_claims WHERE asset_id=a.id ORDER BY id DESC LIMIT 50) x;
 SELECT jsonb_build_object('id',t.id,'to_site_id',t.to_site_id,'include_children',t.include_children,'reason',t.reason,'requested_by',t.requested_by,
   'requested_at',t.requested_at,'version',t.version) INTO j_tr FROM am_transfers t WHERE t.asset_id=a.id AND t.status='pending';
 RETURN jsonb_build_object('asset',j_asset,'category',jsonb_build_object('id',k.id,'code',k.code,'name',k.name,'safety_critical',k.safety_critical),
  'site',j_site,'parent',j_parent,'children',j_children,'meters',j_meters,'warranties',j_war,'movements',j_mov,'open_work_orders',j_wo,
  'plan_targets',j_pt,'open_downtime',j_dt,'cal_records',j_cal,'claims',j_claims,'pending_transfer',j_tr,
  'capabilities',jsonb_build_object('asset_write',ami_has(c,a.site_id,'asset_write'),'transfer',ami_has(c,a.site_id,'transfer'),
    'meter_write',ami_has(c,a.site_id,'meter_write'),'warranty_write',ami_has(c,a.site_id,'warranty_write'),'claim_write',ami_has(c,a.site_id,'claim_write'),
    'money',money));
END$$;

CREATE FUNCTION c10_demo.am_list_transfers_v1(p_business bigint,p_status text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; sites bigint[]; items jsonb; n int;
BEGIN
 c:=ami_read_ctx(p_business); sites:=ami_sites_with(c,'view');
 IF p_status IS NOT NULL AND p_status NOT IN('pending','applied','rejected','cancelled') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT count(*) INTO n FROM am_transfers t WHERE t.business_id=p_business AND (t.from_site_id=ANY(sites) OR t.to_site_id=ANY(sites)) AND (p_status IS NULL OR t.status=p_status);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'asset_id',x.asset_id,'asset_no',a.asset_no,'asset_name',a.name,'from_site_id',x.from_site_id,'to_site_id',x.to_site_id,
   'include_children',x.include_children,'status',x.status,'reason',x.reason,'requested_by',x.requested_by,'requested_at',x.requested_at,'decided_by',x.decided_by,
   'decided_at',x.decided_at,'decision_note',x.decision_note,'version',x.version,
   'can_decide',(x.status='pending' AND ami_has(c,x.from_site_id,'transfer') AND ami_has(c,x.to_site_id,'transfer') AND (x.requested_by<>c.user_id OR ami_is_owner(c))),
   'can_cancel',(x.status='pending' AND (x.requested_by=c.user_id OR ami_is_owner(c) OR ami_has(c,x.from_site_id,'transfer')))) ORDER BY x.id DESC),'[]'::jsonb) INTO items
 FROM (SELECT * FROM am_transfers t WHERE t.business_id=p_business AND (t.from_site_id=ANY(sites) OR t.to_site_id=ANY(sites)) AND (p_status IS NULL OR t.status=p_status)
       ORDER BY t.id DESC LIMIT 200) x JOIN am_assets a ON a.id=x.asset_id;
 RETURN jsonb_build_object('items',items,'total',n);
END$$;

CREATE FUNCTION c10_demo.am_list_claims_v1(p_business bigint,p_status text,p_limit int,p_offset int) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; sites bigint[]; msites bigint[]; items jsonb; n int; v_lim int; v_off int;
BEGIN
 c:=ami_read_ctx(p_business); sites:=ami_sites_with(c,'view'); msites:=ami_r_money_sites(c);
 IF p_status IS NOT NULL AND p_status NOT IN('draft','submitted','accepted','rejected','settled','closed') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_lim:=LEAST(GREATEST(COALESCE(p_limit,50),1),200); v_off:=GREATEST(COALESCE(p_offset,0),0);
 SELECT count(*) INTO n FROM am_warranty_claims x JOIN am_assets a ON a.id=x.asset_id
  WHERE x.business_id=p_business AND a.site_id=ANY(sites) AND (p_status IS NULL OR x.status=p_status);
 SELECT COALESCE(jsonb_agg((jsonb_build_object('id',q.id,'claim_no',q.claim_no,'warranty_id',q.warranty_id,'asset_id',q.asset_id,'asset_no',q.asset_no,'asset_name',q.asset_name,
   'work_order_id',q.work_order_id,'failure_on',q.failure_on,'description',q.description,'status',q.status,'supplier_claim_ref',q.supplier_claim_ref,
   'decision_note',q.decision_note,'created_by',q.created_by,'created_at',q.created_at,'submitted_by',q.submitted_by,'submitted_at',q.submitted_at,
   'decided_by',q.decided_by,'decided_at',q.decided_at,'version',q.version)
   || CASE WHEN q.site_id=ANY(msites) THEN jsonb_build_object('amount_claimed',q.amount_claimed,'amount_settled',q.amount_settled) ELSE '{}'::jsonb END) ORDER BY q.id DESC),'[]'::jsonb) INTO items
 FROM (SELECT x.*,a.asset_no,a.name AS asset_name,a.site_id FROM am_warranty_claims x JOIN am_assets a ON a.id=x.asset_id
       WHERE x.business_id=p_business AND a.site_id=ANY(sites) AND (p_status IS NULL OR x.status=p_status) ORDER BY x.id DESC LIMIT v_lim OFFSET v_off) q;
 RETURN jsonb_build_object('items',items,'total',n,'limit',v_lim,'offset',v_off);
END$$;

CREATE FUNCTION c10_demo.am_list_warranties_v1(p_business bigint,p_asset bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; sites bigint[]; items jsonb; n int; today date; a0 am_assets;
BEGIN
 c:=ami_read_ctx(p_business); sites:=ami_sites_with(c,'view'); today:=ami_today(p_business);
 IF p_asset IS NOT NULL THEN a0:=ami_r_asset_ro(c,p_asset); END IF;
 SELECT count(*) INTO n FROM am_warranties w JOIN am_assets a ON a.id=w.asset_id
  WHERE w.business_id=p_business AND a.site_id=ANY(sites) AND (p_asset IS NULL OR w.asset_id=p_asset);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',q.id,'asset_id',q.asset_id,'asset_no',q.asset_no,'asset_name',q.asset_name,'supplier_name',q.supplier_name,
   'supplier_ref',q.supplier_ref,'coverage',q.coverage,'starts_on',q.starts_on,'expires_on',q.expires_on,'status',q.status,
   'state',ami_r_wstate(q.status,q.expires_on,today,ami_cfg_int(p_business,q.site_id,q.category_id,'asset.warranty_warn_days')),
   'days_left',q.expires_on-today,'version',q.version) ORDER BY q.expires_on,q.id),'[]'::jsonb) INTO items
 FROM (SELECT w.*,a.asset_no,a.name AS asset_name,a.site_id,a.category_id FROM am_warranties w JOIN am_assets a ON a.id=w.asset_id
       WHERE w.business_id=p_business AND a.site_id=ANY(sites) AND (p_asset IS NULL OR w.asset_id=p_asset) ORDER BY w.expires_on,w.id LIMIT 200) q;
 RETURN jsonb_build_object('items',items,'total',n);
END$$;
