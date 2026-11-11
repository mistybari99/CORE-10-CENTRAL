-- C10-A052 | Universal Owner Intent Engine: storage, certified capability catalog, pure evaluators.
-- DISPOSABLE c10_demo ONLY. Apply AFTER A018/A020/A021/A044/A045. NEVER apply to IMG-ERP-SG without
-- snapshot, staging, real GoTrue auth/RLS tests and explicit Owner go/no-go.
-- Authority: reuses c10_demo.actor_uid()/can_tenant()/can_manage()/can_see_business() and the A045 micro-engine
-- registry (handlers + engines + assignments). NO second auth, permission, stock, workflow or audit source.
-- The NATURAL-LANGUAGE parse is a deterministic client-side rule parser (core10-owner-intent-engine.js).
-- The SERVER never trusts it: it re-validates every structured interpretation against the certified allowlist
-- below, recomputes preview/impact itself, and refuses anything else. No eval, no dynamic SQL, no permission grants.
DO $gate$ BEGIN
 IF current_database() !~ '^core10_' OR
  to_regprocedure('c10_demo.assign_engine_v1(bigint,bigint,integer,text,jsonb,text,text,bigint,text,text)') IS NULL OR
  to_regprocedure('c10_demo.engine_eval_threshold_v1(jsonb,jsonb,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'A052_REQUIRES_A045_DISPOSABLE_STACK'; END IF;
END; $gate$;

-- ---------------------------------------------------------------- certified capability catalog
CREATE TABLE c10_demo.intent_capabilities_v1(
 capability_key text PRIMARY KEY CHECK(capability_key ~ '^[a-z][a-z0-9_]{2,40}$'),
 route text NOT NULL CHECK(route IN('A045_ENGINE','A052_ADVISORY')),
 a045_handler_id text REFERENCES c10_demo.micro_engine_handlers_v1(handler_id),
 module_code text NOT NULL CHECK(module_code ~ '^[a-z][a-z0-9_]*$'),
 title jsonb NOT NULL,
 certified boolean NOT NULL,
 sample_inputs jsonb NOT NULL,
 impact jsonb NOT NULL,
 CHECK((route='A045_ENGINE')=(a045_handler_id IS NOT NULL))
);
INSERT INTO c10_demo.intent_capabilities_v1(capability_key,route,a045_handler_id,module_code,title,certified,sample_inputs,impact) VALUES
('wastage_threshold','A052_ADVISORY',NULL,'production',
 '{"en":"Wastage threshold advisory","bn":"অপচয় সীমা সতর্কতা"}',true,
 '{"produced_qty":50,"wasted_qty":3}',
 '{"entities":["production_batch.produced_qty","wastage_record.wasted_qty","item_group"],
   "formulas":[{"id":"wastage_pct","expression_en":"wastage_pct = wasted_qty ÷ produced_qty × 100","expression_bn":"অপচয়_শতাংশ = নষ্ট_পরিমাণ ÷ উৎপাদিত_পরিমাণ × ১০০","units":"percent (%); both quantities must use the same unit (kg, pcs or l)"}],
   "reports":[{"id":"production_wastage_report","status":"NOT_BUILT","note_en":"No wastage report handler exists yet; the threshold is stored and previewable only.","note_bn":"অপচয় রিপোর্ট হ্যান্ডলার এখনো তৈরি হয়নি; সীমা শুধু সংরক্ষিত ও প্রিভিউযোগ্য।"}],
   "permissions":[{"action":"submit_and_preview","required_role":"tenant_owner or business_owner"},{"action":"approve_publish_rollback","required_role":"tenant_owner"}],
   "approvals":[{"when":"outcome = approval_required","who":"Owner","enforced":false}],
   "downstream_modules":[{"module_code":"production","effect":"would read this advisory threshold once wired"},{"module_code":"stock","effect":"none now; no stock movement is written"}]}'),
('pack_discount_margin','A052_ADVISORY',NULL,'costing',
 '{"en":"Pack-size discount margin check","bn":"প্যাক সাইজ ডিসকাউন্ট মার্জিন যাচাই"}',true,
 '{"price_per_pack":3200,"cost_per_litre":600,"discount_pct":8}',
 '{"entities":["item_pack.pack_litres","price_list.price_per_pack","item_cost.cost_per_litre","discount_pct"],
   "formulas":[{"id":"net_price","expression_en":"net_price = price_per_pack × (1 − discount_pct ÷ 100)","expression_bn":"নিট_দাম = প্যাক_দাম × (১ − ছাড়_শতাংশ ÷ ১০০)","units":"currency per pack"},
               {"id":"pack_cost","expression_en":"pack_cost = cost_per_litre × pack_litres","expression_bn":"প্যাক_খরচ = লিটার_প্রতি_খরচ × প্যাক_লিটার","units":"currency per pack; litre"},
               {"id":"margin_pct","expression_en":"margin_pct = (net_price − pack_cost) ÷ net_price × 100","expression_bn":"মার্জিন_শতাংশ = (নিট_দাম − প্যাক_খরচ) ÷ নিট_দাম × ১০০","units":"percent of net price"},
               {"id":"max_discount_pct","expression_en":"max_discount_pct = (1 − pack_cost ÷ (price_per_pack × (1 − min_margin_pct ÷ 100))) × 100","expression_bn":"সর্বোচ্চ_ছাড় = (১ − প্যাক_খরচ ÷ (প্যাক_দাম × (১ − ন্যূনতম_মার্জিন ÷ ১০০))) × ১০০","units":"percent; floored at 0"}],
   "reports":[{"id":"item_margin_report","status":"NOT_BUILT","note_en":"Margin report handler is not built; this is a calculator preview.","note_bn":"মার্জিন রিপোর্ট হ্যান্ডলার তৈরি হয়নি; এটি ক্যালকুলেটর প্রিভিউ।"}],
   "permissions":[{"action":"submit_and_preview","required_role":"tenant_owner or business_owner"},{"action":"approve_publish_rollback","required_role":"tenant_owner"}],
   "approvals":[{"when":"outcome = approval_required","who":"Owner","enforced":false}],
   "downstream_modules":[{"module_code":"costing","effect":"would read the margin floor once wired"},{"module_code":"pos","effect":"none now; no price or discount is changed"}]}'),
('low_stock_alert','A045_ENGINE','threshold_rule_v1','stock',
 '{"en":"Low stock alert","bn":"কম স্টক সতর্কতা"}',true,
 '{"on_hand":8}',
 '{"entities":["stock_summary.on_hand"],
   "formulas":[{"id":"on_hand_lt_threshold","expression_en":"matched when on_hand < threshold","expression_bn":"মিলবে যখন মজুত < সীমা","units":"stock unit of the item"}],
   "reports":[{"id":"stock_position","status":"EXISTING_READ_ONLY","note_en":"Stock position reports are read-only and unchanged.","note_bn":"স্টক পজিশন রিপোর্ট শুধু পড়া যায়, বদলায় না।"}],
   "permissions":[{"action":"submit_and_preview","required_role":"tenant_owner or business_owner"},{"action":"approve_publish_rollback","required_role":"tenant_owner"}],
   "approvals":[],
   "downstream_modules":[{"module_code":"stock","effect":"advisory only; no stock movement is written"}]}'),
('margin_floor_approval','A045_ENGINE','threshold_rule_v1','costing',
 '{"en":"Margin floor needs approval","bn":"ন্যূনতম মার্জিনের নিচে অনুমোদন"}',true,
 '{"margin_pct":8}',
 '{"entities":["order_line.margin_pct"],
   "formulas":[{"id":"margin_lt_floor","expression_en":"matched when margin_pct < threshold","expression_bn":"মিলবে যখন মার্জিন_শতাংশ < সীমা","units":"percent"}],
   "reports":[{"id":"item_margin_report","status":"NOT_BUILT","note_en":"No margin report handler yet.","note_bn":"মার্জিন রিপোর্ট হ্যান্ডলার এখনো নেই।"}],
   "permissions":[{"action":"submit_and_preview","required_role":"tenant_owner or business_owner"},{"action":"approve_publish_rollback","required_role":"tenant_owner"}],
   "approvals":[{"when":"outcome = approval_required","who":"Owner","enforced":false}],
   "downstream_modules":[{"module_code":"costing","effect":"advisory only; no price is changed"}]}'),
('order_total_approval','A045_ENGINE','threshold_rule_v1','purchase',
 '{"en":"Large order/materials approval","bn":"বড় অর্ডার/মালামাল অনুমোদন"}',true,
 '{"order_total":600000}',
 '{"entities":["purchase_order.order_total","project.materials_request"],
   "formulas":[{"id":"order_total_gte_threshold","expression_en":"matched when order_total ≥ threshold","expression_bn":"মিলবে যখন অর্ডার_মোট ≥ সীমা","units":"currency amount"}],
   "reports":[{"id":"project_materials_report","status":"NOT_BUILT","note_en":"Read-only project materials report handler is not built; request it as an engineering requirement.","note_bn":"প্রকল্প মালামাল রিপোর্ট হ্যান্ডলার তৈরি হয়নি; ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট হিসেবে চাইতে হবে।"}],
   "permissions":[{"action":"submit_and_preview","required_role":"tenant_owner or business_owner"},{"action":"approve_publish_rollback","required_role":"tenant_owner"}],
   "approvals":[{"when":"outcome = approval_required","who":"Owner","enforced":false}],
   "downstream_modules":[{"module_code":"purchase","effect":"advisory flag only; no purchase order is posted or approved"}]}');

-- ---------------------------------------------------------------- guidance catalog (rows generated; see seed file)
CREATE TABLE c10_demo.intent_guidance_v1(
 control_key text PRIMARY KEY CHECK(control_key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
 module_code text NOT NULL,
 capability_key text REFERENCES c10_demo.intent_capabilities_v1(capability_key),
 content jsonb NOT NULL,
 CHECK(content ?& ARRAY['title','what','why','when','default','exception','consequence','data_formula_units','linked_report'])
);

-- ---------------------------------------------------------------- Owner intents (versioned lifecycle)
CREATE TABLE c10_demo.owner_intents_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL REFERENCES c10_demo.tenants(id),
 business_id bigint NOT NULL,
 site_id bigint,
 raw_text text NOT NULL CHECK(length(btrim(raw_text)) BETWEEN 3 AND 1000),
 locale text NOT NULL CHECK(locale IN('bn','en','mixed')),
 capability_key text REFERENCES c10_demo.intent_capabilities_v1(capability_key),
 status text NOT NULL CHECK(status IN('INTERPRETED','NEEDS_CLARIFICATION','PREVIEWED','VALIDATED','APPROVED','PUBLISHED',
   'REJECTED','UNSUPPORTED','ENGINEERING_REQUIRED')),
 params jsonb NOT NULL DEFAULT '{}'::jsonb,
 interpretation jsonb NOT NULL,
 sample jsonb,
 preview jsonb,
 preview_hash text,
 basis_version bigint,
 version int NOT NULL DEFAULT 1 CHECK(version>0),
 setting_id bigint,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,tenant_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id),
 CHECK(status NOT IN('PREVIEWED','VALIDATED','APPROVED','PUBLISHED') OR (capability_key IS NOT NULL AND preview_hash IS NOT NULL)),
 CHECK(status NOT IN('UNSUPPORTED','ENGINEERING_REQUIRED') OR capability_key IS NULL)
);
CREATE INDEX owner_intents_business_idx ON c10_demo.owner_intents_v1(business_id,id DESC);

CREATE TABLE c10_demo.intent_settings_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 setting_key text NOT NULL REFERENCES c10_demo.intent_capabilities_v1(capability_key),
 version int NOT NULL CHECK(version>0),
 state text NOT NULL CHECK(state IN('ACTIVE','SUPERSEDED')),
 params jsonb NOT NULL,
 payload_hash text NOT NULL,
 source_intent_id bigint,
 rollback_of_version int,
 engine_id bigint,
 engine_version int,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 superseded_at timestamptz,
 UNIQUE(business_id,setting_key,version),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 CHECK(payload_hash=md5(params::text))
);
CREATE UNIQUE INDEX intent_settings_one_active ON c10_demo.intent_settings_v1(business_id,setting_key) WHERE state='ACTIVE';

CREATE TABLE c10_demo.engineering_requirements_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 intent_id bigint NOT NULL UNIQUE,
 status text NOT NULL CHECK(status IN('NEEDS_HANDLER_BUILD','NOT_ALLOWED_BY_POLICY')),
 category text NOT NULL CHECK(category ~ '^[a-z][a-z0-9_]{2,40}$'),
 a045_handler_id text REFERENCES c10_demo.micro_engine_handlers_v1(handler_id),
 requirement jsonb NOT NULL CHECK(length(requirement::text)<=6000),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(intent_id,tenant_id) REFERENCES c10_demo.owner_intents_v1(id,tenant_id)
);

CREATE TABLE c10_demo.owner_intent_events_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 intent_id bigint,
 setting_key text,
 event text NOT NULL CHECK(event ~ '^[a-z_]{3,40}$'),
 before_state jsonb,
 after_state jsonb,
 actor_uid uuid NOT NULL,
 request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE INDEX owner_intent_events_biz_idx ON c10_demo.owner_intent_events_v1(business_id,id DESC);

CREATE TABLE c10_demo.intent_receipts_v1(
 tenant_id bigint NOT NULL,
 request_key text NOT NULL,
 actor_uid uuid NOT NULL,
 payload jsonb NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,request_key)
);

CREATE FUNCTION c10_demo.intent_events_immutable_v1() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'intent_audit_immutable'; END$$;
CREATE TRIGGER intent_events_no_mutation_v1 BEFORE UPDATE OR DELETE ON c10_demo.owner_intent_events_v1
 FOR EACH ROW EXECUTE FUNCTION c10_demo.intent_events_immutable_v1();
CREATE TRIGGER intent_events_no_truncate_v1 BEFORE TRUNCATE ON c10_demo.owner_intent_events_v1
 FOR EACH STATEMENT EXECUTE FUNCTION c10_demo.intent_events_immutable_v1();
-- published setting versions: payload immutable; only the supersede flag may flip.
CREATE FUNCTION c10_demo.intent_settings_guard_v1() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'intent_setting_immutable'; END IF;
 IF NEW.params IS DISTINCT FROM OLD.params OR NEW.version<>OLD.version OR NEW.business_id<>OLD.business_id OR
    NEW.setting_key<>OLD.setting_key OR NEW.created_by<>OLD.created_by OR OLD.state='SUPERSEDED'
 THEN RAISE EXCEPTION 'intent_setting_immutable'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER intent_settings_row_guard_v1 BEFORE UPDATE OR DELETE ON c10_demo.intent_settings_v1
 FOR EACH ROW EXECUTE FUNCTION c10_demo.intent_settings_guard_v1();
CREATE TRIGGER intent_settings_no_truncate_v1 BEFORE TRUNCATE ON c10_demo.intent_settings_v1
 FOR EACH STATEMENT EXECUTE FUNCTION c10_demo.intent_events_immutable_v1();

-- ---------------------------------------------------------------- RLS: defense in depth + no direct writes
ALTER TABLE c10_demo.intent_capabilities_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.intent_guidance_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.owner_intents_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.intent_settings_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.engineering_requirements_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.owner_intent_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.intent_receipts_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON c10_demo.intent_capabilities_v1,c10_demo.intent_guidance_v1,c10_demo.owner_intents_v1,
 c10_demo.intent_settings_v1,c10_demo.engineering_requirements_v1,c10_demo.owner_intent_events_v1,
 c10_demo.intent_receipts_v1 FROM PUBLIC,authenticated,anon;
-- READ-ONLY direct access for tenant Owner / Business Owner of the same business only (RLS-scoped).
GRANT SELECT ON c10_demo.owner_intents_v1,c10_demo.intent_settings_v1,c10_demo.engineering_requirements_v1,
 c10_demo.owner_intent_events_v1 TO authenticated;
CREATE POLICY intents_manage_read ON c10_demo.owner_intents_v1 FOR SELECT TO authenticated
 USING(c10_demo.can_manage(tenant_id,business_id));
CREATE POLICY settings_manage_read ON c10_demo.intent_settings_v1 FOR SELECT TO authenticated
 USING(c10_demo.can_manage(tenant_id,business_id));
CREATE POLICY requirements_manage_read ON c10_demo.engineering_requirements_v1 FOR SELECT TO authenticated
 USING(c10_demo.can_manage(tenant_id,business_id));
CREATE POLICY events_manage_read ON c10_demo.owner_intent_events_v1 FOR SELECT TO authenticated
 USING(c10_demo.can_manage(tenant_id,business_id));

-- ---------------------------------------------------------------- pure validation / evaluation (no table writes)
CREATE FUNCTION c10_demo.intent_num_v1(j jsonb,k text,lo numeric,hi numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN j IS NOT NULL AND jsonb_typeof(j)='object' AND jsonb_typeof(j->k)='number'
   AND (j->>k)::numeric BETWEEN lo AND hi THEN (j->>k)::numeric END
$$;
CREATE FUNCTION c10_demo.intent_keys_ok_v1(j jsonb,allowed text[]) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
 SELECT j IS NOT NULL AND jsonb_typeof(j)='object'
   AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(j) k WHERE k<>ALL(allowed))
$$;
CREATE FUNCTION c10_demo.intent_params_valid_v1(p_cap text,p jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p_cap IS NULL OR p IS NULL OR jsonb_typeof(p)<>'object' THEN RETURN false; END IF;
 RETURN CASE p_cap
 WHEN 'wastage_threshold' THEN
  c10_demo.intent_keys_ok_v1(p,ARRAY['threshold_pct','outcome','unit','item_group'])
  AND c10_demo.intent_num_v1(p,'threshold_pct',0.0001,100) IS NOT NULL
  AND jsonb_typeof(p->'outcome')='string' AND p->>'outcome' IN('warn','approval_required')
  AND jsonb_typeof(p->'unit')='string' AND p->>'unit' IN('kg','pcs','l')
  AND (NOT p?'item_group' OR (jsonb_typeof(p->'item_group')='string' AND length(p->>'item_group')<=40
       AND p->>'item_group' ~ '^[A-Za-z0-9 _-]*$'))
 WHEN 'pack_discount_margin' THEN
  c10_demo.intent_keys_ok_v1(p,ARRAY['pack_litres','min_margin_pct','outcome','currency'])
  AND c10_demo.intent_num_v1(p,'pack_litres',0.001,1000) IS NOT NULL
  AND c10_demo.intent_num_v1(p,'min_margin_pct',0,99.99) IS NOT NULL
  AND jsonb_typeof(p->'outcome')='string' AND p->>'outcome' IN('warn','approval_required','block')
  AND jsonb_typeof(p->'currency')='string' AND p->>'currency' ~ '^[A-Z]{3}$'
 WHEN 'low_stock_alert' THEN
  c10_demo.intent_keys_ok_v1(p,ARRAY['threshold','outcome'])
  AND c10_demo.intent_num_v1(p,'threshold',0,1000000000) IS NOT NULL
  AND jsonb_typeof(p->'outcome')='string' AND p->>'outcome' IN('allow','warn','block','approval_required')
 WHEN 'margin_floor_approval' THEN
  c10_demo.intent_keys_ok_v1(p,ARRAY['threshold','outcome'])
  AND c10_demo.intent_num_v1(p,'threshold',0,99.99) IS NOT NULL
  AND jsonb_typeof(p->'outcome')='string' AND p->>'outcome' IN('allow','warn','block','approval_required')
 WHEN 'order_total_approval' THEN
  c10_demo.intent_keys_ok_v1(p,ARRAY['threshold','outcome','currency'])
  AND c10_demo.intent_num_v1(p,'threshold',0.01,1000000000) IS NOT NULL
  AND jsonb_typeof(p->'outcome')='string' AND p->>'outcome' IN('allow','warn','block','approval_required')
  AND jsonb_typeof(p->'currency')='string' AND p->>'currency' ~ '^[A-Z]{3}$'
 ELSE false END;
END$$;
-- A045 threshold descriptor for the A045_ENGINE capabilities (data only, no code).
CREATE FUNCTION c10_demo.intent_descriptor_v1(p_cap text,p jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE p_cap
  WHEN 'low_stock_alert' THEN jsonb_build_object('field','on_hand','op','lt','threshold',p->'threshold',
     'outcome',p->>'outcome','message','A052 advisory: stock below owner threshold')
  WHEN 'margin_floor_approval' THEN jsonb_build_object('field','margin_pct','op','lt','threshold',p->'threshold',
     'outcome',p->>'outcome','message','A052 advisory: margin below owner floor')
  WHEN 'order_total_approval' THEN jsonb_build_object('field','order_total','op','gte','threshold',p->'threshold',
     'outcome',p->>'outcome','message','A052 advisory: order total reaches owner approval limit')
 END
$$;
-- ADVISORY evaluation only. Exact numeric arithmetic. canAuthorizeOperation is always false.
CREATE FUNCTION c10_demo.intent_eval_v1(p_cap text,p jsonb,inp jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE r jsonb; a numeric; b numeric; c numeric; pct numeric; net numeric; cost numeric; mg numeric; maxd numeric; hit boolean; oc text;
 f text; e jsonb;
BEGIN
 IF NOT c10_demo.intent_params_valid_v1(p_cap,p) THEN RAISE EXCEPTION 'invalid_params'; END IF;
 IF inp IS NULL OR jsonb_typeof(inp)<>'object' THEN RAISE EXCEPTION 'invalid_input'; END IF;
 IF p_cap='wastage_threshold' THEN
  IF NOT c10_demo.intent_keys_ok_v1(inp,ARRAY['produced_qty','wasted_qty']) THEN RAISE EXCEPTION 'invalid_input'; END IF;
  a:=c10_demo.intent_num_v1(inp,'produced_qty',0.0001,1000000000);
  b:=c10_demo.intent_num_v1(inp,'wasted_qty',0,1000000000);
  IF a IS NULL OR b IS NULL OR b>a THEN RAISE EXCEPTION 'invalid_input'; END IF;
  pct:=round(b/a*100,4); hit:=pct>(p->>'threshold_pct')::numeric; oc:=p->>'outcome';
  RETURN jsonb_build_object('capability_key',p_cap,'advisory',true,'mutates',false,'canAuthorizeOperation',false,
   'matched',hit,'outcome',CASE WHEN hit THEN oc ELSE 'allow' END,
   'computed',jsonb_build_object('wastage_pct',pct),'inputs',inp,
   'formula',jsonb_build_object('expression_en','wastage_pct = wasted_qty ÷ produced_qty × 100; matched when wastage_pct > threshold_pct',
     'expression_bn','অপচয়_শতাংশ = নষ্ট ÷ উৎপাদিত × ১০০; অপচয়_শতাংশ > সীমা হলে মিলবে',
     'units',jsonb_build_object('quantity',p->>'unit','result','percent'),
     'steps',jsonb_build_array(format('%s ÷ %s × 100 = %s %%',b,a,pct),format('%s %% > %s %% → %s',pct,p->>'threshold_pct',hit))));
 ELSIF p_cap='pack_discount_margin' THEN
  IF NOT c10_demo.intent_keys_ok_v1(inp,ARRAY['price_per_pack','cost_per_litre','discount_pct']) THEN RAISE EXCEPTION 'invalid_input'; END IF;
  a:=c10_demo.intent_num_v1(inp,'price_per_pack',0.01,1000000000);
  b:=c10_demo.intent_num_v1(inp,'cost_per_litre',0,1000000000);
  c:=c10_demo.intent_num_v1(inp,'discount_pct',0,99.99);
  IF a IS NULL OR b IS NULL OR c IS NULL THEN RAISE EXCEPTION 'invalid_input'; END IF;
  net:=a*(1-c/100); cost:=b*(p->>'pack_litres')::numeric;
  mg:=round((net-cost)/net*100,4);
  maxd:=round(greatest(0,(1-cost/(a*(1-(p->>'min_margin_pct')::numeric/100)))*100),4);
  hit:=mg<(p->>'min_margin_pct')::numeric; oc:=p->>'outcome';
  RETURN jsonb_build_object('capability_key',p_cap,'advisory',true,'mutates',false,'canAuthorizeOperation',false,
   'matched',hit,'outcome',CASE WHEN hit THEN oc ELSE 'allow' END,
   'computed',jsonb_build_object('net_price',round(net,4),'pack_cost',round(cost,4),'margin_pct',mg,'max_discount_pct',maxd),
   'inputs',inp,
   'formula',jsonb_build_object('expression_en','margin_pct = (net_price − pack_cost) ÷ net_price × 100; matched when margin_pct < min_margin_pct',
     'expression_bn','মার্জিন_শতাংশ = (নিট_দাম − প্যাক_খরচ) ÷ নিট_দাম × ১০০; মার্জিন < ন্যূনতম হলে মিলবে',
     'units',jsonb_build_object('money',p->>'currency'||' per pack','volume','litre','result','percent of net price'),
     'steps',jsonb_build_array(format('net_price = %s × (1 − %s ÷ 100) = %s',a,c,round(net,4)),
       format('pack_cost = %s × %s L = %s',b,p->>'pack_litres',round(cost,4)),
       format('margin_pct = (%s − %s) ÷ %s × 100 = %s %%',round(net,4),round(cost,4),round(net,4),mg),
       format('max discount keeping margin ≥ %s %% is %s %%',p->>'min_margin_pct',maxd))));
 ELSE
  f:=CASE p_cap WHEN 'low_stock_alert' THEN 'on_hand' WHEN 'margin_floor_approval' THEN 'margin_pct' WHEN 'order_total_approval' THEN 'order_total' END;
  IF f IS NULL OR NOT c10_demo.intent_keys_ok_v1(inp,ARRAY[f]) THEN RAISE EXCEPTION 'invalid_input'; END IF;
  e:=c10_demo.engine_eval_threshold_v1(c10_demo.intent_descriptor_v1(p_cap,p),'{}'::jsonb,inp);
  RETURN jsonb_build_object('capability_key',p_cap,'advisory',true,'mutates',false,'canAuthorizeOperation',false,
   'matched',e->'matched','outcome',e->'outcome','computed',jsonb_build_object(f,inp->f),'inputs',inp,'a045',e,
   'formula',jsonb_build_object('expression_en',f||' '||CASE p_cap WHEN 'order_total_approval' THEN '≥' ELSE '<' END||' threshold',
     'expression_bn',f||' '||CASE p_cap WHEN 'order_total_approval' THEN '≥' ELSE '<' END||' সীমা',
     'units',jsonb_build_object('value',CASE f WHEN 'margin_pct' THEN 'percent' WHEN 'order_total' THEN COALESCE(p->>'currency','amount') ELSE 'stock unit' END),
     'steps',jsonb_build_array(format('%s %s %s → %s',inp->>f,CASE p_cap WHEN 'order_total_approval' THEN '≥' ELSE '<' END,p->>'threshold',e->>'matched'))));
 END IF;
END$$;
