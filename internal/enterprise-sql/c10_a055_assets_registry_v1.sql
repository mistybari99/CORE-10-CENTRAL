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
