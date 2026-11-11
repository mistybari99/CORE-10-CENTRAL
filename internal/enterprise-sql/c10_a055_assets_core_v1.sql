-- C10-A055 Enterprise Assets & Maintenance (1/7): COMPLETE data model, policy catalog, authority helpers, audit.
-- DISPOSABLE c10_demo ONLY. Apply AFTER A018 (c10_a018_demo_backend.sql). NEVER apply to production IMG-ERP-SG.
-- Reuses A018 tenants/businesses/sites + business_members + can_tenant. Introduces NO login, NO stock/ledger table,
-- NO payroll/employee copy. Maintenance authority is a SEPARATE, explicit grant (am_grants): stock.read/site_grants,
-- investor, payroll and employee roles never imply maintenance authority.
-- All am_* tables: RLS on, zero direct grants to anon/authenticated. Every read/write is a guarded SECURITY DEFINER RPC
-- (public API am_*_v1). Internal helpers are ami_* and are NOT executable by authenticated/anon (see lockdown file).
-- Error codes are stable strings: am_denied (no access / not visible), am_not_permitted (inside but capability missing).

-- ===================== configuration & authority =====================
CREATE TABLE c10_demo.am_settings(
 business_id bigint PRIMARY KEY, tenant_id bigint NOT NULL,
 policy_rev bigint NOT NULL DEFAULT 1,
 version bigint NOT NULL DEFAULT 1,
 bootstrapped_at timestamptz NOT NULL DEFAULT now(),
 updated_by uuid, updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.am_counters(
 business_id bigint NOT NULL, tenant_id bigint NOT NULL, kind text NOT NULL CHECK(kind ~ '^[a-z_]{2,24}$'),
 next_val bigint NOT NULL DEFAULT 1,
 PRIMARY KEY(business_id,kind),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
-- Static rule catalog (type/range/default/scope). Help text (Bangla/English) lives in the client catalog; a test keeps keys equal.
CREATE TABLE c10_demo.am_policy_catalog(
 key text PRIMARY KEY, grp text NOT NULL, vtype text NOT NULL CHECK(vtype IN('bool','int','num','text','enum')),
 default_value jsonb NOT NULL, min_num numeric, max_num numeric, enum_values text[], pattern text,
 scopes text[] NOT NULL DEFAULT ARRAY['business','site','category'] CHECK(scopes <@ ARRAY['business','site','category']),
 level text NOT NULL DEFAULT 'owner' CHECK(level IN('owner','tenant_owner')),
 sort int NOT NULL DEFAULT 0
);
CREATE TABLE c10_demo.am_policy(
 business_id bigint NOT NULL, tenant_id bigint NOT NULL,
 scope_type text NOT NULL CHECK(scope_type IN('business','site','category')),
 scope_id bigint NOT NULL DEFAULT 0 CHECK((scope_type='business' AND scope_id=0) OR (scope_type<>'business' AND scope_id>0)),
 key text NOT NULL REFERENCES c10_demo.am_policy_catalog(key),
 value jsonb NOT NULL,
 updated_by uuid NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,scope_type,scope_id,key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
-- Preset bundles ("recommended" per site mode). Applying a preset writes ordinary versioned policy rows.
CREATE TABLE c10_demo.am_policy_presets(
 preset text NOT NULL CHECK(preset IN('recommended','showroom','factory','godown','project','office')),
 key text NOT NULL REFERENCES c10_demo.am_policy_catalog(key), value jsonb NOT NULL,
 PRIMARY KEY(preset,key)
);
CREATE TABLE c10_demo.am_policy_history(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 business_id bigint NOT NULL, tenant_id bigint NOT NULL, scope_type text NOT NULL, scope_id bigint NOT NULL, key text NOT NULL,
 old_value jsonb, new_value jsonb, rev bigint NOT NULL, reason text NOT NULL,
 actor_uid uuid NOT NULL, request_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE INDEX am_policy_history_ix ON c10_demo.am_policy_history(business_id,id DESC);
-- Maintenance role assignment (explicit; NULL site_id = every site of this business).
CREATE TABLE c10_demo.am_grants(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, user_id uuid NOT NULL,
 role text NOT NULL CHECK(role IN('supervisor','technician','reporter','auditor')),
 site_id bigint, active boolean NOT NULL DEFAULT true,
 note text CHECK(note IS NULL OR length(note)<=200),
 granted_by uuid NOT NULL, granted_at timestamptz NOT NULL DEFAULT now(),
 revoked_by uuid, revoked_at timestamptz,
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE UNIQUE INDEX am_grants_uq ON c10_demo.am_grants(business_id,user_id,role,COALESCE(site_id,0));
CREATE INDEX am_grants_user_ix ON c10_demo.am_grants(user_id) WHERE active;

-- ===================== codes, categories =====================
CREATE TABLE c10_demo.am_codes(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 kind text NOT NULL CHECK(kind IN('failure','cause','action','downtime_reason','service_category')),
 code text NOT NULL CHECK(code ~ '^[A-Z0-9][A-Z0-9_-]{0,23}$'),
 label text NOT NULL CHECK(length(btrim(label)) BETWEEN 2 AND 80),
 label_bn text CHECK(label_bn IS NULL OR length(btrim(label_bn)) BETWEEN 1 AND 80),
 active boolean NOT NULL DEFAULT true, is_system boolean NOT NULL DEFAULT false,
 UNIQUE(business_id,kind,code),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.am_categories(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Z0-9][A-Z0-9_-]{0,23}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 name_bn text CHECK(name_bn IS NULL OR length(btrim(name_bn)) BETWEEN 1 AND 80),
 parent_id bigint,
 asset_kind text NOT NULL DEFAULT 'equipment' CHECK(asset_kind IN('fixed_asset','equipment','tool','vehicle','it','facility','other')),
 default_criticality smallint NOT NULL DEFAULT 3 CHECK(default_criticality BETWEEN 1 AND 5),
 default_meter_unit text CHECK(default_meter_unit IS NULL OR default_meter_unit IN('hours','km','cycles','units')),
 safety_critical boolean NOT NULL DEFAULT false,
 useful_life_months int CHECK(useful_life_months IS NULL OR useful_life_months BETWEEN 1 AND 600),
 salvage_pct numeric(5,2) CHECK(salvage_pct IS NULL OR salvage_pct BETWEEN 0 AND 100),
 active boolean NOT NULL DEFAULT true, is_system boolean NOT NULL DEFAULT false,
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(business_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(parent_id,tenant_id,business_id) REFERENCES c10_demo.am_categories(id,tenant_id,business_id)
);

-- ===================== asset registry =====================
CREATE TABLE c10_demo.am_assets(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 asset_no text NOT NULL,                    -- durable canonical ID, unique per business, never reused
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 120),
 category_id bigint NOT NULL,
 status text NOT NULL DEFAULT 'active' CHECK(status IN('planned','active','under_maintenance','breakdown','idle','retired','disposed')),
 criticality smallint NOT NULL DEFAULT 3 CHECK(criticality BETWEEN 1 AND 5),
 site_id bigint NOT NULL, location_note text CHECK(location_note IS NULL OR length(location_note)<=200),
 serial_no text CHECK(serial_no IS NULL OR serial_no ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'),
 model text CHECK(model IS NULL OR length(btrim(model)) BETWEEN 1 AND 80),
 manufacturer text CHECK(manufacturer IS NULL OR length(btrim(manufacturer)) BETWEEN 1 AND 80),
 ownership text NOT NULL DEFAULT 'owned' CHECK(ownership IN('owned','leased','rented','client_owned','consignment')),
 provenance text CHECK(provenance IS NULL OR length(provenance)<=300),
 supplier_name text CHECK(supplier_name IS NULL OR length(supplier_name)<=120),
 supplier_ref text CHECK(supplier_ref IS NULL OR length(supplier_ref)<=60),
 purchase_order_ref text CHECK(purchase_order_ref IS NULL OR purchase_order_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$'), -- read-only A049 reference, no FK
 custodian_ref text CHECK(custodian_ref IS NULL OR custodian_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$'),         -- stable A051 employee reference, no FK/copy
 acquisition_date date, commission_date date,
 acquisition_cost numeric(18,2) CHECK(acquisition_cost IS NULL OR acquisition_cost>=0), -- ADVISORY only, never posted
 quantity numeric(14,3) NOT NULL DEFAULT 1 CHECK(quantity>0),
 parent_asset_id bigint,
 custom_attrs jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(custom_attrs)='object' AND pg_column_size(custom_attrs)<=4096),
 retired_at timestamptz, version bigint NOT NULL DEFAULT 1,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,asset_no), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id),
 FOREIGN KEY(category_id,tenant_id,business_id) REFERENCES c10_demo.am_categories(id,tenant_id,business_id),
 FOREIGN KEY(parent_asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 CHECK(parent_asset_id IS NULL OR parent_asset_id<>id),
 CHECK(commission_date IS NULL OR acquisition_date IS NULL OR commission_date>=acquisition_date)
);
-- Duplicate serial race guard (same manufacturer+serial inside one business, live assets only).
CREATE UNIQUE INDEX am_assets_serial_uq ON c10_demo.am_assets(business_id,lower(COALESCE(manufacturer,'')),lower(serial_no))
 WHERE serial_no IS NOT NULL AND status NOT IN('retired','disposed');
CREATE INDEX am_assets_site_ix ON c10_demo.am_assets(business_id,site_id,status);
CREATE INDEX am_assets_cat_ix ON c10_demo.am_assets(category_id);
CREATE INDEX am_assets_parent_ix ON c10_demo.am_assets(parent_asset_id) WHERE parent_asset_id IS NOT NULL;
CREATE TABLE c10_demo.am_asset_movements(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, asset_id bigint NOT NULL,
 from_site_id bigint, to_site_id bigint NOT NULL,
 kind text NOT NULL CHECK(kind IN('initial','transfer')),
 transfer_id bigint, reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 moved_by uuid NOT NULL, moved_at timestamptz NOT NULL DEFAULT now(), request_key text NOT NULL,
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(to_site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE INDEX am_mov_asset_ix ON c10_demo.am_asset_movements(asset_id,id DESC);
CREATE TABLE c10_demo.am_transfers(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, asset_id bigint NOT NULL,
 from_site_id bigint NOT NULL, to_site_id bigint NOT NULL CHECK(to_site_id<>from_site_id),
 include_children boolean NOT NULL DEFAULT true,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','applied','rejected','cancelled')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 requested_by uuid NOT NULL, requested_at timestamptz NOT NULL DEFAULT now(),
 decided_by uuid, decided_at timestamptz, decision_note text,
 version bigint NOT NULL DEFAULT 1,
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(to_site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE UNIQUE INDEX am_transfers_pending_uq ON c10_demo.am_transfers(asset_id) WHERE status='pending';
CREATE TABLE c10_demo.am_meters(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, asset_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
 unit text NOT NULL CHECK(unit IN('hours','km','cycles','units')),
 current_reading numeric(18,3) NOT NULL DEFAULT 0 CHECK(current_reading>=0),
 last_reading_at timestamptz, active boolean NOT NULL DEFAULT true, version bigint NOT NULL DEFAULT 1,
 UNIQUE(asset_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.am_meter_readings(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, meter_id bigint NOT NULL, asset_id bigint NOT NULL,
 reading numeric(18,3) NOT NULL CHECK(reading>=0),
 kind text NOT NULL DEFAULT 'reading' CHECK(kind IN('reading','reset')),
 read_at timestamptz NOT NULL, note text CHECK(note IS NULL OR length(note)<=300),
 recorded_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), request_key text NOT NULL,
 FOREIGN KEY(meter_id,tenant_id,business_id) REFERENCES c10_demo.am_meters(id,tenant_id,business_id)
);
CREATE INDEX am_readings_meter_ix ON c10_demo.am_meter_readings(meter_id,read_at DESC,id DESC);

-- ===================== warranty =====================
CREATE TABLE c10_demo.am_warranties(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, asset_id bigint NOT NULL,
 supplier_name text NOT NULL CHECK(length(btrim(supplier_name)) BETWEEN 2 AND 120),
 supplier_ref text CHECK(supplier_ref IS NULL OR length(supplier_ref)<=60),
 coverage text CHECK(coverage IS NULL OR length(coverage)<=500),
 starts_on date NOT NULL, expires_on date NOT NULL CHECK(expires_on>=starts_on),
 status text NOT NULL DEFAULT 'active' CHECK(status IN('active','void')),
 version bigint NOT NULL DEFAULT 1, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id)
);
CREATE INDEX am_warranty_asset_ix ON c10_demo.am_warranties(asset_id,expires_on);

-- ===================== checklists & plans =====================
CREATE TABLE c10_demo.am_checklist_templates(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
 version int NOT NULL DEFAULT 1, name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 120),
 category_id bigint, active boolean NOT NULL DEFAULT true, superseded_at timestamptz,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,code,version), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(category_id,tenant_id,business_id) REFERENCES c10_demo.am_categories(id,tenant_id,business_id)
);
CREATE UNIQUE INDEX am_checklist_active_uq ON c10_demo.am_checklist_templates(business_id,code) WHERE active;
CREATE TABLE c10_demo.am_checklist_items(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, template_id bigint NOT NULL,
 seq int NOT NULL CHECK(seq BETWEEN 1 AND 200),
 text text NOT NULL CHECK(length(btrim(text)) BETWEEN 2 AND 300),
 kind text NOT NULL DEFAULT 'check' CHECK(kind IN('check','measure','safety')),
 required boolean NOT NULL DEFAULT true,
 min_value numeric(18,4), max_value numeric(18,4), unit text CHECK(unit IS NULL OR length(unit)<=16),
 CHECK(min_value IS NULL OR max_value IS NULL OR min_value<=max_value),
 UNIQUE(template_id,seq),
 FOREIGN KEY(template_id,tenant_id,business_id) REFERENCES c10_demo.am_checklist_templates(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.am_plans(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 120),
 plan_type text NOT NULL CHECK(plan_type IN('preventive','inspection','calibration','certification')),
 asset_id bigint, category_id bigint, site_id bigint,
 CHECK(asset_id IS NOT NULL OR category_id IS NOT NULL),
 frequency_kind text NOT NULL CHECK(frequency_kind IN('daily','weekly','monthly','yearly','usage')),
 interval_n int NOT NULL DEFAULT 1 CHECK(interval_n BETWEEN 1 AND 3650),
 meter_code text CHECK(meter_code IS NULL OR meter_code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
 usage_interval numeric(18,3) CHECK(usage_interval IS NULL OR usage_interval>0),
 CHECK((frequency_kind='usage' AND meter_code IS NOT NULL AND usage_interval IS NOT NULL) OR (frequency_kind<>'usage')),
 checklist_code text, priority text NOT NULL DEFAULT 'medium' CHECK(priority IN('low','medium','high','critical')),
 est_labor_hours numeric(8,2) CHECK(est_labor_hours IS NULL OR est_labor_hours>=0),
 est_cost numeric(18,2) CHECK(est_cost IS NULL OR est_cost>=0),
 anchor text CHECK(anchor IS NULL OR anchor IN('from_completion','from_due_date')),
 start_on date NOT NULL, end_on date CHECK(end_on IS NULL OR end_on>=start_on),
 lead_days int CHECK(lead_days IS NULL OR lead_days BETWEEN 0 AND 90),
 team_ref text CHECK(team_ref IS NULL OR team_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$'),
 active boolean NOT NULL DEFAULT true, version bigint NOT NULL DEFAULT 1,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(category_id,tenant_id,business_id) REFERENCES c10_demo.am_categories(id,tenant_id,business_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.am_plan_targets(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, plan_id bigint NOT NULL, asset_id bigint NOT NULL,
 next_due_on date, next_due_reading numeric(18,3),
 last_done_on date, last_done_reading numeric(18,3), last_wo_id bigint,
 deferred_until date, defer_reason text,
 status text NOT NULL DEFAULT 'scheduled' CHECK(status IN('scheduled','suspended')),
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(plan_id,asset_id), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(plan_id,tenant_id,business_id) REFERENCES c10_demo.am_plans(id,tenant_id,business_id),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id)
);

-- ===================== work orders =====================
CREATE TABLE c10_demo.am_work_orders(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 wo_no text NOT NULL,
 kind text NOT NULL CHECK(kind IN('preventive','corrective','breakdown','inspection','calibration')),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED','VERIFIED','CLOSED','CANCELLED')),
 source text NOT NULL DEFAULT 'manual' CHECK(source IN('manual','plan','breakdown_report')),
 asset_id bigint NOT NULL, site_id bigint NOT NULL, plan_target_id bigint,
 title text NOT NULL CHECK(length(btrim(title)) BETWEEN 3 AND 160),
 description text CHECK(description IS NULL OR length(description)<=2000),
 priority text NOT NULL DEFAULT 'medium' CHECK(priority IN('low','medium','high','critical')),
 service_category text, safety_critical boolean NOT NULL DEFAULT false,
 requested_by uuid NOT NULL, requested_at timestamptz NOT NULL DEFAULT now(),
 submitted_at timestamptz, approved_by uuid, approved_at timestamptz,
 assigned_to uuid, assignee_ref text CHECK(assignee_ref IS NULL OR assignee_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$'),
 team_ref text CHECK(team_ref IS NULL OR team_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$'),
 needs_reassignment boolean NOT NULL DEFAULT false,
 due_on date, responded_at timestamptz, started_at timestamptz, started_by uuid,
 completed_at timestamptz, completed_by uuid, verified_at timestamptz, verified_by uuid, closed_at timestamptz, closed_by uuid,
 sla_response_due_at timestamptz, sla_resolve_due_at timestamptz,
 failure_code text, cause_code text, action_code text, corrective_action text CHECK(corrective_action IS NULL OR length(corrective_action)<=2000),
 safety_ack_by uuid, safety_ack_at timestamptz,
 est_labor_hours numeric(8,2) CHECK(est_labor_hours IS NULL OR est_labor_hours>=0),
 est_labor_cost numeric(18,2) CHECK(est_labor_cost IS NULL OR est_labor_cost>=0),
 est_spares_cost numeric(18,2) CHECK(est_spares_cost IS NULL OR est_spares_cost>=0),
 actual_labor_hours numeric(8,2) CHECK(actual_labor_hours IS NULL OR actual_labor_hours>=0),
 actual_labor_cost numeric(18,2) CHECK(actual_labor_cost IS NULL OR actual_labor_cost>=0),
 actual_spares_cost numeric(18,2) CHECK(actual_spares_cost IS NULL OR actual_spares_cost>=0),
 meter_reading_at_start numeric(18,3), meter_reading_at_end numeric(18,3),
 merged_into_id bigint, reopen_count int NOT NULL DEFAULT 0, cancel_reason text, last_reason text,
 version bigint NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,wo_no), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id),
 FOREIGN KEY(plan_target_id,tenant_id,business_id) REFERENCES c10_demo.am_plan_targets(id,tenant_id,business_id),
 FOREIGN KEY(merged_into_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id),
 CHECK(completed_at IS NULL OR started_at IS NULL OR completed_at>=started_at)
);
-- One OPEN work order per plan target (recurrence can never create duplicate tasks, even under races).
CREATE UNIQUE INDEX am_wo_target_open_uq ON c10_demo.am_work_orders(plan_target_id)
 WHERE plan_target_id IS NOT NULL AND status NOT IN('CLOSED','CANCELLED');
CREATE INDEX am_wo_asset_ix ON c10_demo.am_work_orders(asset_id,status);
CREATE INDEX am_wo_site_ix ON c10_demo.am_work_orders(business_id,site_id,status);
CREATE INDEX am_wo_assigned_ix ON c10_demo.am_work_orders(assigned_to) WHERE assigned_to IS NOT NULL;
ALTER TABLE c10_demo.am_plan_targets ADD FOREIGN KEY(last_wo_id,tenant_id,business_id)
 REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id);
CREATE TABLE c10_demo.am_wo_history(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, work_order_id bigint NOT NULL,
 from_status text, to_status text NOT NULL, action text NOT NULL, reason text,
 actor_uid uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), request_key text NOT NULL,
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
CREATE INDEX am_wo_hist_ix ON c10_demo.am_wo_history(work_order_id,id);
CREATE TABLE c10_demo.am_wo_checklist(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, work_order_id bigint NOT NULL,
 seq int NOT NULL, text text NOT NULL, kind text NOT NULL CHECK(kind IN('check','measure','safety')), required boolean NOT NULL,
 min_value numeric(18,4), max_value numeric(18,4), unit text,
 result text NOT NULL DEFAULT 'pending' CHECK(result IN('pending','pass','fail','na')),
 value numeric(18,4), note text CHECK(note IS NULL OR length(note)<=500),
 done_by uuid, done_at timestamptz,
 UNIQUE(work_order_id,seq),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.am_wo_labor(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, work_order_id bigint NOT NULL,
 labor_kind text NOT NULL DEFAULT 'internal' CHECK(labor_kind IN('internal','contractor')),
 worker_ref text CHECK(worker_ref IS NULL OR worker_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$'),
 hours numeric(8,2) NOT NULL CHECK(hours>0 AND hours<=1000), rate numeric(18,2) CHECK(rate IS NULL OR rate>=0),
 note text CHECK(note IS NULL OR length(note)<=300), phase text NOT NULL DEFAULT 'actual' CHECK(phase IN('estimate','actual')),
 recorded_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
-- Spares are INFORMATIONAL lines. No stock is read or moved (A048 consumes a future documented ISSUE adapter).
CREATE TABLE c10_demo.am_wo_spares(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, work_order_id bigint NOT NULL,
 item_ref text CHECK(item_ref IS NULL OR item_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$'),
 description text NOT NULL CHECK(length(btrim(description)) BETWEEN 2 AND 200),
 phase text NOT NULL DEFAULT 'estimate' CHECK(phase IN('estimate','actual')),
 qty numeric(14,3) NOT NULL CHECK(qty>0), unit_cost numeric(18,2) CHECK(unit_cost IS NULL OR unit_cost>=0),
 stock_effect boolean NOT NULL DEFAULT false CHECK(stock_effect=false),
 recorded_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
-- Attachment METADATA only (no file upload, no public URL).
CREATE TABLE c10_demo.am_wo_attachments(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, work_order_id bigint NOT NULL,
 file_name text NOT NULL CHECK(file_name ~ '^[A-Za-z0-9][A-Za-z0-9._ -]{0,99}$'),
 mime text NOT NULL CHECK(mime IN('image/jpeg','image/png','image/webp','application/pdf','text/plain')),
 size_bytes bigint NOT NULL CHECK(size_bytes BETWEEN 1 AND 26214400),
 sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 storage_ref text NOT NULL CHECK(storage_ref ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$'),
 kind text NOT NULL DEFAULT 'photo' CHECK(kind IN('photo','document','certificate','report')),
 caption text CHECK(caption IS NULL OR length(caption)<=200),
 recorded_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(work_order_id,sha256),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.am_downtime(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, asset_id bigint NOT NULL, site_id bigint NOT NULL,
 work_order_id bigint, kind text NOT NULL CHECK(kind IN('breakdown','planned','other')),
 reason_code text, impact text CHECK(impact IS NULL OR length(impact)<=500),
 started_at timestamptz NOT NULL, ended_at timestamptz,
 started_by uuid NOT NULL, ended_by uuid, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(ended_at IS NULL OR ended_at>=started_at),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
-- At most ONE open downtime window per asset (race-proof); closed windows are checked for overlap by the RPC under asset lock.
CREATE UNIQUE INDEX am_downtime_open_uq ON c10_demo.am_downtime(asset_id) WHERE ended_at IS NULL;
CREATE INDEX am_downtime_asset_ix ON c10_demo.am_downtime(asset_id,started_at DESC);
CREATE INDEX am_downtime_site_ix ON c10_demo.am_downtime(business_id,site_id,started_at DESC);
CREATE TABLE c10_demo.am_cal_records(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, asset_id bigint NOT NULL, work_order_id bigint,
 plan_kind text NOT NULL CHECK(plan_kind IN('calibration','inspection','certification')),
 performed_on date NOT NULL, next_due_on date CHECK(next_due_on IS NULL OR next_due_on>=performed_on),
 result text NOT NULL CHECK(result IN('pass','fail','adjusted')),
 certificate_ref text CHECK(certificate_ref IS NULL OR length(certificate_ref)<=80),
 standard_ref text CHECK(standard_ref IS NULL OR length(standard_ref)<=80),
 vendor text CHECK(vendor IS NULL OR length(vendor)<=120), note text CHECK(note IS NULL OR length(note)<=500),
 recorded_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.am_warranty_claims(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, claim_no text NOT NULL,
 warranty_id bigint NOT NULL, asset_id bigint NOT NULL, work_order_id bigint,
 failure_on date NOT NULL, description text NOT NULL CHECK(length(btrim(description)) BETWEEN 3 AND 1000),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','submitted','accepted','rejected','settled','closed')),
 amount_claimed numeric(18,2) CHECK(amount_claimed IS NULL OR amount_claimed>=0),
 amount_settled numeric(18,2) CHECK(amount_settled IS NULL OR amount_settled>=0), -- ADVISORY, never posted to any ledger
 supplier_claim_ref text CHECK(supplier_claim_ref IS NULL OR length(supplier_claim_ref)<=60), decision_note text,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 submitted_by uuid, submitted_at timestamptz, decided_by uuid, decided_at timestamptz, version bigint NOT NULL DEFAULT 1,
 UNIQUE(business_id,claim_no),
 FOREIGN KEY(warranty_id,tenant_id,business_id) REFERENCES c10_demo.am_warranties(id,tenant_id,business_id),
 FOREIGN KEY(asset_id,tenant_id,business_id) REFERENCES c10_demo.am_assets(id,tenant_id,business_id),
 FOREIGN KEY(work_order_id,tenant_id,business_id) REFERENCES c10_demo.am_work_orders(id,tenant_id,business_id)
);

-- ===================== idempotency receipts & hash-chained audit =====================
CREATE TABLE c10_demo.am_receipts(
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 actor_uid uuid NOT NULL, op text NOT NULL, payload jsonb NOT NULL, result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.am_audit(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 entity text NOT NULL, entity_id text NOT NULL, event text NOT NULL,
 before_state jsonb, after_state jsonb, reason text,
 actor_uid uuid NOT NULL, request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 prev_hash text, row_hash text NOT NULL,
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE INDEX am_audit_biz_ix ON c10_demo.am_audit(business_id,id);
CREATE INDEX am_audit_entity_ix ON c10_demo.am_audit(business_id,entity,entity_id,id);
CREATE FUNCTION c10_demo.ami_audit_hash(p_prev text,r c10_demo.am_audit) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
 SELECT encode(sha256(convert_to(concat_ws('|',COALESCE(p_prev,'GENESIS'),r.tenant_id,r.business_id,
  r.entity,r.entity_id,r.event,COALESCE(r.before_state::text,''),COALESCE(r.after_state::text,''),
  COALESCE(r.reason,''),r.actor_uid,r.request_key,r.created_at::text),'UTF8')),'hex') $$;
CREATE FUNCTION c10_demo.ami_audit_chain() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 SELECT row_hash INTO NEW.prev_hash FROM c10_demo.am_audit WHERE business_id=NEW.business_id ORDER BY id DESC LIMIT 1;
 NEW.row_hash:=c10_demo.ami_audit_hash(NEW.prev_hash,NEW);
 RETURN NEW;
END$$;
CREATE TRIGGER am_audit_chain BEFORE INSERT ON c10_demo.am_audit FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_audit_chain();
CREATE FUNCTION c10_demo.ami_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'am_append_only_record'; END$$;
CREATE TRIGGER am_audit_no_row_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_audit FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_audit_no_truncate BEFORE TRUNCATE ON c10_demo.am_audit FOR EACH STATEMENT EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_receipts_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_receipts FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_mov_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_asset_movements FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_readings_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_meter_readings FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_wo_hist_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_wo_history FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_policy_hist_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_policy_history FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_cal_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_cal_records FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();
CREATE TRIGGER am_wo_attach_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.am_wo_attachments FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();

-- ===================== DB-level invariants (hold even if an RPC is buggy) =====================
-- Work-order state machine: only these edges exist. Reopen = COMPLETED/VERIFIED/CLOSED -> IN_PROGRESS (RPC demands reason).
CREATE FUNCTION c10_demo.ami_wo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
   (OLD.status='DRAFT' AND NEW.status IN('SUBMITTED','CANCELLED')) OR
   (OLD.status='SUBMITTED' AND NEW.status IN('APPROVED','DRAFT','CANCELLED')) OR
   (OLD.status='APPROVED' AND NEW.status IN('IN_PROGRESS','CANCELLED')) OR
   (OLD.status='IN_PROGRESS' AND NEW.status IN('COMPLETED','CANCELLED')) OR
   (OLD.status='COMPLETED' AND NEW.status IN('VERIFIED','CLOSED','IN_PROGRESS')) OR
   (OLD.status='VERIFIED' AND NEW.status IN('CLOSED','IN_PROGRESS')) OR
   (OLD.status='CLOSED' AND NEW.status IN('IN_PROGRESS'))) THEN
  RAISE EXCEPTION 'am_wo_illegal_transition'; END IF;
 IF OLD.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER am_wo_state_guard BEFORE UPDATE ON c10_demo.am_work_orders FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_wo_guard();
-- Assembly graph: parent must be same business (FK) and acyclic, depth <= 12.
CREATE FUNCTION c10_demo.ami_asset_cycle_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cur bigint:=NEW.parent_asset_id; d int:=0;
BEGIN
 WHILE cur IS NOT NULL LOOP
  d:=d+1;
  IF cur=NEW.id OR d>12 THEN RAISE EXCEPTION 'am_assembly_cycle_or_too_deep'; END IF;
  SELECT parent_asset_id INTO cur FROM c10_demo.am_assets WHERE id=cur;
 END LOOP;
 RETURN NEW;
END$$;
CREATE TRIGGER am_asset_cycle BEFORE INSERT OR UPDATE OF parent_asset_id ON c10_demo.am_assets FOR EACH ROW
 WHEN (NEW.parent_asset_id IS NOT NULL) EXECUTE FUNCTION c10_demo.ami_asset_cycle_guard();
-- Canonical asset identity (asset_no / business / tenant) never changes after creation.
CREATE FUNCTION c10_demo.ami_asset_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.asset_no<>OLD.asset_no OR NEW.business_id<>OLD.business_id OR NEW.tenant_id<>OLD.tenant_id THEN
  RAISE EXCEPTION 'am_asset_identity_immutable'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER am_asset_identity BEFORE UPDATE ON c10_demo.am_assets FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_asset_identity_guard();

-- ===================== policy catalog (rules; help text is in the client catalog) =====================
INSERT INTO c10_demo.am_policy_catalog(key,grp,vtype,default_value,min_num,max_num,enum_values,pattern,scopes,level,sort) VALUES
 ('wo.approval_min_priority','work_order','enum','"low"',NULL,NULL,ARRAY['never','low','medium','high','critical'],NULL,ARRAY['business','site','category'],'owner',10),
 ('wo.approval_cost_threshold','work_order','num','0',0,1000000000,NULL,NULL,ARRAY['business','site','category'],'owner',11),
 ('wo.maker_checker','work_order','bool','true',NULL,NULL,NULL,NULL,ARRAY['business'],'tenant_owner',12),
 ('wo.verify_required','work_order','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',13),
 ('wo.require_checklist_complete','work_order','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',14),
 ('wo.evidence_required_for','work_order','enum','"breakdown"',NULL,NULL,ARRAY['none','breakdown','all'],NULL,ARRAY['business','site','category'],'owner',15),
 ('wo.require_cause_code','work_order','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',16),
 ('wo.require_safety_ack','work_order','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',17),
 ('wo.require_actual_labor','work_order','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',18),
 ('wo.technician_can_create','work_order','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site'],'owner',19),
 ('wo.technician_can_claim_unassigned','work_order','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site'],'owner',20),
 ('wo.overlap_policy','work_order','enum','"block"',NULL,NULL,ARRAY['block','allow'],NULL,ARRAY['business','site','category'],'owner',21),
 ('wo.reopen_window_days','work_order','int','30',0,365,NULL,NULL,ARRAY['business','site','category'],'owner',22),
 ('breakdown.auto_approve','work_order','enum','"critical"',NULL,NULL,ARRAY['never','critical','high_and_above','all'],NULL,ARRAY['business','site','category'],'owner',23),
 ('sla.response_hours.low','sla','int','72',1,2160,NULL,NULL,ARRAY['business','site','category'],'owner',30),
 ('sla.response_hours.medium','sla','int','24',1,2160,NULL,NULL,ARRAY['business','site','category'],'owner',31),
 ('sla.response_hours.high','sla','int','8',1,2160,NULL,NULL,ARRAY['business','site','category'],'owner',32),
 ('sla.response_hours.critical','sla','int','1',1,2160,NULL,NULL,ARRAY['business','site','category'],'owner',33),
 ('sla.resolve_hours.low','sla','int','336',1,8760,NULL,NULL,ARRAY['business','site','category'],'owner',34),
 ('sla.resolve_hours.medium','sla','int','120',1,8760,NULL,NULL,ARRAY['business','site','category'],'owner',35),
 ('sla.resolve_hours.high','sla','int','48',1,8760,NULL,NULL,ARRAY['business','site','category'],'owner',36),
 ('sla.resolve_hours.critical','sla','int','8',1,8760,NULL,NULL,ARRAY['business','site','category'],'owner',37),
 ('schedule.due_lead_days','schedule','int','7',0,90,NULL,NULL,ARRAY['business','site','category'],'owner',40),
 ('schedule.grace_days','schedule','int','3',0,60,NULL,NULL,ARRAY['business','site','category'],'owner',41),
 ('schedule.escalation_days','schedule','int','3',0,60,NULL,NULL,ARRAY['business','site','category'],'owner',42),
 ('schedule.anchor','schedule','enum','"from_due_date"',NULL,NULL,ARRAY['from_completion','from_due_date'],NULL,ARRAY['business','site','category'],'owner',43),
 ('schedule.max_defer_days','schedule','int','14',0,90,NULL,NULL,ARRAY['business','site','category'],'owner',44),
 ('schedule.auto_submit_generated','schedule','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',45),
 ('downtime.min_counted_minutes','downtime','int','0',0,1440,NULL,NULL,ARRAY['business','site','category'],'owner',50),
 ('downtime.max_open_hours','downtime','int','720',1,8760,NULL,NULL,ARRAY['business','site','category'],'owner',51),
 ('downtime.planned_counts','downtime','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',52),
 ('downtime.end_on','downtime','enum','"completed"',NULL,NULL,ARRAY['completed','verified'],NULL,ARRAY['business','site','category'],'owner',53),
 ('meter.allow_decrease','meter','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',60),
 ('meter.stale_days','meter','int','30',1,365,NULL,NULL,ARRAY['business','site','category'],'owner',61),
 ('asset.transfer_requires_approval','asset','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site'],'owner',70),
 ('asset.allow_transfer_with_active_wo','asset','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site'],'owner',71),
 ('asset.require_serial','asset','bool','false',NULL,NULL,NULL,NULL,ARRAY['business','site','category'],'owner',72),
 ('asset.warranty_warn_days','asset','int','60',0,365,NULL,NULL,ARRAY['business','site','category'],'owner',73),
 ('asset.warranty_claim_grace_days','asset','int','0',0,180,NULL,NULL,ARRAY['business','site','category'],'owner',74),
 ('risk.high_threshold','risk','int','10',1,25,NULL,NULL,ARRAY['business'],'owner',80),
 ('risk.critical_threshold','risk','int','16',2,25,NULL,NULL,ARRAY['business'],'owner',81),
 ('analytics.min_sample_mttr','analytics','int','3',1,50,NULL,NULL,ARRAY['business'],'owner',90),
 ('analytics.min_sample_mtbf','analytics','int','3',2,50,NULL,NULL,ARRAY['business'],'owner',91),
 ('analytics.recurring_window_days','analytics','int','90',7,730,NULL,NULL,ARRAY['business'],'owner',92),
 ('analytics.recurring_min_count','analytics','int','3',2,20,NULL,NULL,ARRAY['business'],'owner',93),
 ('finance.depreciation_method','finance','enum','"straight_line"',NULL,NULL,ARRAY['none','straight_line','declining_balance'],NULL,ARRAY['business','category'],'owner',100),
 ('finance.default_useful_life_months','finance','int','60',1,600,NULL,NULL,ARRAY['business','category'],'owner',101),
 ('finance.default_salvage_pct','finance','num','10',0,100,NULL,NULL,ARRAY['business','category'],'owner',102),
 ('finance.declining_rate_pct','finance','num','20',1,100,NULL,NULL,ARRAY['business','category'],'owner',103),
 ('access.manager_acts_as_supervisor','access','bool','false',NULL,NULL,NULL,NULL,ARRAY['business'],'owner',110),
 ('access.supervisor_can_manage_assets','access','bool','true',NULL,NULL,NULL,NULL,ARRAY['business'],'owner',111),
 ('access.technician_can_record_meter','access','bool','true',NULL,NULL,NULL,NULL,ARRAY['business','site'],'owner',112),
 ('general.timezone','general','text','"Asia/Dhaka"',NULL,NULL,NULL,'^[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}$',ARRAY['business'],'owner',120),
 ('general.currency','general','text','"BDT"',NULL,NULL,NULL,'^[A-Z]{3}$',ARRAY['business'],'owner',121),
 ('general.wo_prefix','general','text','"WO"',NULL,NULL,NULL,'^[A-Z0-9]{1,6}$',ARRAY['business'],'owner',122),
 ('general.asset_prefix','general','text','"AST"',NULL,NULL,NULL,'^[A-Z0-9]{1,6}$',ARRAY['business'],'owner',123),
 ('export.csv_enabled','general','bool','true',NULL,NULL,NULL,NULL,ARRAY['business'],'owner',124),
 ('export.max_rows','general','int','5000',100,50000,NULL,NULL,ARRAY['business'],'owner',125);
-- Recommended-per-mode bundles (a preset is only a convenience; every value stays individually editable).
INSERT INTO c10_demo.am_policy_presets(preset,key,value) VALUES
 ('recommended','wo.approval_min_priority','"low"'),('recommended','wo.maker_checker','true'),('recommended','wo.verify_required','true'),
 ('recommended','wo.evidence_required_for','"breakdown"'),('recommended','schedule.due_lead_days','7'),('recommended','schedule.grace_days','3'),
 ('showroom','wo.approval_min_priority','"medium"'),('showroom','wo.evidence_required_for','"breakdown"'),('showroom','schedule.due_lead_days','5'),
 ('showroom','sla.resolve_hours.high','24'),('showroom','sla.response_hours.critical','1'),('showroom','wo.verify_required','false'),
 ('factory','wo.approval_min_priority','"low"'),('factory','wo.evidence_required_for','"all"'),('factory','wo.verify_required','true'),
 ('factory','schedule.due_lead_days','14'),('factory','schedule.grace_days','1'),('factory','wo.require_safety_ack','true'),('factory','sla.resolve_hours.critical','4'),
 ('godown','wo.approval_min_priority','"medium"'),('godown','wo.evidence_required_for','"breakdown"'),('godown','schedule.due_lead_days','10'),
 ('godown','schedule.grace_days','5'),('godown','wo.verify_required','false'),
 ('project','wo.approval_min_priority','"high"'),('project','schedule.due_lead_days','3'),('project','schedule.grace_days','1'),
 ('project','wo.evidence_required_for','"all"'),('project','breakdown.auto_approve','"high_and_above"'),('project','sla.resolve_hours.critical','6'),
 ('office','wo.approval_min_priority','"high"'),('office','wo.verify_required','false'),('office','schedule.due_lead_days','14'),('office','schedule.grace_days','7');
CREATE TRIGGER am_catalog_ro BEFORE UPDATE OR DELETE ON c10_demo.am_policy_catalog FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_immutable();

-- ===================== internal helpers =====================
CREATE TYPE c10_demo.am_ctx_t AS(
 tenant_id bigint, business_id bigint, user_id uuid, is_tenant_owner boolean, is_business_owner boolean,
 manager_as_supervisor boolean, grants jsonb);

CREATE FUNCTION c10_demo.ami_role_caps(p_role text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE p_role
  WHEN 'owner' THEN ARRAY['view','report','execute','assign','approve','verify','asset_write','plan_write','meter_write',
    'warranty_write','transfer','downtime_write','reports','export','audit_read','policy_read','claim_write','cancel','reopen']
  WHEN 'supervisor' THEN ARRAY['view','report','execute','assign','approve','verify','asset_write','plan_write','meter_write',
    'warranty_write','transfer','downtime_write','reports','export','policy_read','claim_write','cancel','reopen']
  WHEN 'technician' THEN ARRAY['view','report','execute','meter_write','policy_read']
  WHEN 'reporter' THEN ARRAY['view','report','policy_read']
  WHEN 'auditor' THEN ARRAY['view','reports','export','audit_read','policy_read']
  ELSE ARRAY[]::text[] END $$;

-- Policy resolution: category override > site override > business value > catalog default.
CREATE FUNCTION c10_demo.ami_cfg(p_business bigint,p_site bigint,p_category bigint,p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
DECLARE v jsonb;
BEGIN
 IF p_category IS NOT NULL THEN
  SELECT value INTO v FROM c10_demo.am_policy WHERE business_id=p_business AND scope_type='category' AND scope_id=p_category AND key=p_key;
  IF FOUND THEN RETURN v; END IF; END IF;
 IF p_site IS NOT NULL THEN
  SELECT value INTO v FROM c10_demo.am_policy WHERE business_id=p_business AND scope_type='site' AND scope_id=p_site AND key=p_key;
  IF FOUND THEN RETURN v; END IF; END IF;
 SELECT value INTO v FROM c10_demo.am_policy WHERE business_id=p_business AND scope_type='business' AND scope_id=0 AND key=p_key;
 IF FOUND THEN RETURN v; END IF;
 SELECT default_value INTO v FROM c10_demo.am_policy_catalog WHERE key=p_key;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_unknown_policy_key'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_cfg_int(p_business bigint,p_site bigint,p_category bigint,p_key text) RETURNS int LANGUAGE sql STABLE AS
$$ SELECT (c10_demo.ami_cfg(p_business,p_site,p_category,p_key) #>> '{}')::numeric::int $$;
CREATE FUNCTION c10_demo.ami_cfg_num(p_business bigint,p_site bigint,p_category bigint,p_key text) RETURNS numeric LANGUAGE sql STABLE AS
$$ SELECT (c10_demo.ami_cfg(p_business,p_site,p_category,p_key) #>> '{}')::numeric $$;
CREATE FUNCTION c10_demo.ami_cfg_bool(p_business bigint,p_site bigint,p_category bigint,p_key text) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT (c10_demo.ami_cfg(p_business,p_site,p_category,p_key) #>> '{}')::boolean $$;
CREATE FUNCTION c10_demo.ami_cfg_text(p_business bigint,p_site bigint,p_category bigint,p_key text) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT c10_demo.ami_cfg(p_business,p_site,p_category,p_key) #>> '{}' $$;

CREATE FUNCTION c10_demo.ami_today(p_business bigint) RETURNS date LANGUAGE sql STABLE AS
$$ SELECT (now() AT TIME ZONE c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.timezone'))::date $$;

-- Server-derived authority. stock grants / investor / payroll / employee links NEVER grant maintenance access.
CREATE FUNCTION c10_demo.ami_ctx(p_business bigint) RETURNS c10_demo.am_ctx_t LANGUAGE plpgsql STABLE AS $$
DECLARE c c10_demo.am_ctx_t; uid uuid:=c10_demo.actor_uid(); is_mgr boolean;
BEGIN
 IF uid IS NULL OR p_business IS NULL THEN RAISE EXCEPTION 'am_denied'; END IF;
 SELECT tenant_id INTO c.tenant_id FROM c10_demo.businesses WHERE id=p_business;
 IF c.tenant_id IS NULL THEN RAISE EXCEPTION 'am_denied'; END IF;
 c.business_id:=p_business; c.user_id:=uid;
 c.is_tenant_owner:=c10_demo.can_tenant(c.tenant_id);
 c.is_business_owner:=EXISTS(SELECT 1 FROM c10_demo.business_members m WHERE m.user_id=uid AND m.tenant_id=c.tenant_id
   AND m.business_id=p_business AND m.active AND m.role='business_owner');
 is_mgr:=EXISTS(SELECT 1 FROM c10_demo.business_members m WHERE m.user_id=uid AND m.tenant_id=c.tenant_id
   AND m.business_id=p_business AND m.active AND m.role='manager');
 c.manager_as_supervisor:=is_mgr AND c10_demo.ami_cfg_bool(p_business,NULL,NULL,'access.manager_acts_as_supervisor');
 SELECT COALESCE(jsonb_agg(jsonb_build_object('role',role,'site_id',site_id)),'[]'::jsonb) INTO c.grants
  FROM c10_demo.am_grants WHERE business_id=p_business AND user_id=uid AND active;
 IF NOT (c.is_tenant_owner OR c.is_business_owner OR c.manager_as_supervisor OR jsonb_array_length(c.grants)>0) THEN
  RAISE EXCEPTION 'am_denied'; END IF;
 RETURN c;
END$$;
CREATE FUNCTION c10_demo.ami_is_owner(c c10_demo.am_ctx_t) RETURNS boolean LANGUAGE sql IMMUTABLE AS
$$ SELECT c.is_tenant_owner OR c.is_business_owner $$;
-- Capabilities held at one site (p_site NULL = only business-wide grants/ownership count).
CREATE FUNCTION c10_demo.ami_caps(c c10_demo.am_ctx_t,p_site bigint) RETURNS text[] LANGUAGE plpgsql STABLE AS $$
DECLARE caps text[]:=ARRAY[]::text[]; g jsonb;
BEGIN
 IF c.is_tenant_owner OR c.is_business_owner THEN RETURN c10_demo.ami_role_caps('owner'); END IF;
 IF c.manager_as_supervisor THEN caps:=caps||c10_demo.ami_role_caps('supervisor'); END IF;
 FOR g IN SELECT * FROM jsonb_array_elements(c.grants) LOOP
  IF (g->>'site_id') IS NULL OR (p_site IS NOT NULL AND (g->>'site_id')::bigint=p_site) THEN
   caps:=caps||c10_demo.ami_role_caps(g->>'role'); END IF;
 END LOOP;
 RETURN ARRAY(SELECT DISTINCT unnest(caps));
END$$;
CREATE FUNCTION c10_demo.ami_has(c c10_demo.am_ctx_t,p_site bigint,p_cap text) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT p_cap=ANY(c10_demo.ami_caps(c,p_site)) $$;
CREATE FUNCTION c10_demo.ami_need_cap(c c10_demo.am_ctx_t,p_site bigint,p_cap text) RETURNS void LANGUAGE plpgsql STABLE AS
$$ BEGIN IF NOT c10_demo.ami_has(c,p_site,p_cap) THEN RAISE EXCEPTION 'am_not_permitted'; END IF; END$$;
-- Sites where the actor holds a capability (owner/business-wide = all sites of the business).
CREATE FUNCTION c10_demo.ami_sites_with(c c10_demo.am_ctx_t,p_cap text) RETURNS bigint[] LANGUAGE sql STABLE AS
$$ SELECT COALESCE(array_agg(s.id),ARRAY[]::bigint[]) FROM c10_demo.sites s
   WHERE s.business_id=c.business_id AND p_cap=ANY(c10_demo.ami_caps(c,s.id)) $$;
CREATE FUNCTION c10_demo.ami_need(p_ok boolean,p_code text) RETURNS void LANGUAGE plpgsql IMMUTABLE AS
$$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION '%',p_code; END IF; END$$;
CREATE FUNCTION c10_demo.ami_need_owner(c c10_demo.am_ctx_t) RETURNS void LANGUAGE plpgsql IMMUTABLE AS
$$ BEGIN IF NOT (c.is_tenant_owner OR c.is_business_owner) THEN RAISE EXCEPTION 'am_owner_required'; END IF; END$$;
CREATE FUNCTION c10_demo.ami_log(p_tenant bigint,p_business bigint,p_entity text,p_entity_id text,p_event text,
 p_before jsonb,p_after jsonb,p_reason text,p_request text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO c10_demo.am_audit(tenant_id,business_id,entity,entity_id,event,before_state,after_state,reason,actor_uid,request_key)
   VALUES(p_tenant,p_business,p_entity,p_entity_id,p_event,p_before,p_after,p_reason,c10_demo.actor_uid(),p_request) $$;
-- Per-business monotonic numbering (row lock serialises; numbers are never reused).
CREATE FUNCTION c10_demo.ami_next_no(p_business bigint,p_kind text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n bigint; t bigint; pre text;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 INSERT INTO c10_demo.am_counters(business_id,tenant_id,kind) VALUES(p_business,t,p_kind) ON CONFLICT DO NOTHING;
 UPDATE c10_demo.am_counters SET next_val=next_val+1 WHERE business_id=p_business AND kind=p_kind RETURNING next_val-1 INTO n;
 pre:=CASE p_kind WHEN 'asset' THEN c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.asset_prefix')
  WHEN 'wo' THEN c10_demo.ami_cfg_text(p_business,NULL,NULL,'general.wo_prefix')
  WHEN 'claim' THEN 'CLM' ELSE upper(p_kind) END;
 RETURN pre||'-'||lpad(n::text,6,'0');
END$$;
-- First write to a business bootstraps its settings row and neutral multi-industry defaults (idempotent).
CREATE FUNCTION c10_demo.ami_ensure_business(p_business bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t bigint; ins int;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 INSERT INTO c10_demo.am_settings(business_id,tenant_id) VALUES(p_business,t) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS ins=ROW_COUNT;
 IF ins=0 THEN RETURN; END IF;
 INSERT INTO c10_demo.am_codes(tenant_id,business_id,kind,code,label,label_bn,is_system) VALUES
  (t,p_business,'failure','MECH','Mechanical failure','যান্ত্রিক ত্রুটি',true),(t,p_business,'failure','ELEC','Electrical failure','বৈদ্যুতিক ত্রুটি',true),
  (t,p_business,'failure','LEAK','Leak / fluid loss','লিক / তরল ক্ষয়',true),(t,p_business,'failure','OVERHEAT','Overheating','অতিরিক্ত গরম',true),
  (t,p_business,'failure','CTRL','Control / software fault','কন্ট্রোল / সফটওয়্যার ত্রুটি',true),(t,p_business,'failure','WEAR','Wear and tear','ক্ষয়ক্ষতি',true),
  (t,p_business,'failure','OTHER','Other','অন্যান্য',true),
  (t,p_business,'cause','AGE','Normal wear / age','স্বাভাবিক ক্ষয়',true),(t,p_business,'cause','MISUSE','Operator misuse','অপব্যবহার',true),
  (t,p_business,'cause','NOPM','Missed preventive maintenance','প্রতিরোধমূলক রক্ষণাবেক্ষণ বাদ',true),
  (t,p_business,'cause','SUPPLY','Power / utility supply','বিদ্যুৎ / সরবরাহ সমস্যা',true),
  (t,p_business,'cause','DEFECT','Manufacturing defect','নির্মাণ ত্রুটি',true),(t,p_business,'cause','UNKNOWN','Unknown','অজানা',true),
  (t,p_business,'action','REPAIR','Repaired','মেরামত',true),(t,p_business,'action','REPLACE','Part replaced','যন্ত্রাংশ বদল',true),
  (t,p_business,'action','ADJUST','Adjusted / calibrated','সমন্বয় / ক্যালিব্রেশন',true),(t,p_business,'action','CLEAN','Cleaned / lubricated','পরিষ্কার / লুব্রিকেশন',true),
  (t,p_business,'action','VENDOR','Vendor service','ভেন্ডর সার্ভিস',true),
  (t,p_business,'downtime_reason','BREAKDOWN','Breakdown','বিকল',true),(t,p_business,'downtime_reason','PM','Planned maintenance','পরিকল্পিত রক্ষণাবেক্ষণ',true),
  (t,p_business,'downtime_reason','WAIT_PARTS','Waiting for spares','যন্ত্রাংশের অপেক্ষা',true),(t,p_business,'downtime_reason','SAFETY','Safety stop','নিরাপত্তা বন্ধ',true),
  (t,p_business,'service_category','ROUTINE','Routine service','নিয়মিত সার্ভিস',true),(t,p_business,'service_category','REPAIR','Repair','মেরামত',true),
  (t,p_business,'service_category','INSPECT','Inspection','পরিদর্শন',true),(t,p_business,'service_category','CALIB','Calibration','ক্যালিব্রেশন',true),
  (t,p_business,'service_category','SAFETY','Safety / compliance','নিরাপত্তা / কমপ্লায়েন্স',true);
 INSERT INTO c10_demo.am_categories(tenant_id,business_id,code,name,name_bn,asset_kind,default_criticality,default_meter_unit,safety_critical,useful_life_months,salvage_pct,is_system) VALUES
  (t,p_business,'PROD-EQ','Production equipment','উৎপাদন যন্ত্র','equipment',4,'hours',false,120,10,true),
  (t,p_business,'COLD','Refrigeration / cold chain','রেফ্রিজারেশন','equipment',5,'hours',false,96,10,true),
  (t,p_business,'POWER','Power generation','বিদ্যুৎ উৎপাদন','equipment',5,'hours',true,120,10,true),
  (t,p_business,'LIFT','Lifting / construction equipment','উত্তোলন / নির্মাণ যন্ত্র','equipment',5,'hours',true,120,10,true),
  (t,p_business,'VEHICLE','Vehicle','যানবাহন','vehicle',3,'km',false,96,15,true),
  (t,p_business,'POS','POS / retail terminal','পিওএস টার্মিনাল','it',2,NULL,false,48,0,true),
  (t,p_business,'IT','IT / office equipment','আইটি / অফিস সরঞ্জাম','it',2,NULL,false,36,0,true),
  (t,p_business,'TOOL','Tools and instruments','যন্ত্রপাতি','tool',2,NULL,false,36,0,true),
  (t,p_business,'FACILITY','Facility / building service','ভবন / ফ্যাসিলিটি','facility',3,NULL,false,240,0,true),
  (t,p_business,'GENERAL','General asset','সাধারণ সম্পদ','fixed_asset',3,NULL,false,60,10,true);
END$$;
CREATE FUNCTION c10_demo.ami_begin(p_business bigint,p_request text,p_op text,p_payload jsonb,
 OUT o_ctx c10_demo.am_ctx_t,OUT o_replay jsonb) LANGUAGE plpgsql AS $$
DECLARE r c10_demo.am_receipts;
BEGIN
 IF p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,100}$' THEN RAISE EXCEPTION 'am_invalid_request_key'; END IF;
 IF c10_demo.actor_uid() IS NULL THEN RAISE EXCEPTION 'am_denied'; END IF;
 -- Authorise BEFORE taking the per-business lock (outsiders cannot contend); re-derive after it (revocation race).
 PERFORM c10_demo.ami_ctx(p_business);
 PERFORM 1 FROM c10_demo.businesses WHERE id=p_business FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 o_ctx:=c10_demo.ami_ctx(p_business);
 PERFORM c10_demo.ami_ensure_business(p_business);
 SELECT * INTO r FROM c10_demo.am_receipts WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF r.actor_uid<>c10_demo.actor_uid() OR r.op<>p_op OR r.payload<>p_payload THEN RAISE EXCEPTION 'am_idempotency_conflict'; END IF;
  o_replay:=r.result;
 END IF;
END$$;
CREATE FUNCTION c10_demo.ami_finish(p_business bigint,p_tenant bigint,p_request text,p_op text,
 p_payload jsonb,p_result jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO c10_demo.am_receipts(tenant_id,business_id,request_key,actor_uid,op,payload,result)
 VALUES(p_tenant,p_business,p_request,c10_demo.actor_uid(),p_op,p_payload,p_result);
 RETURN p_result;
END$$;
-- Report-style reads: authorise without taking locks or creating rows.
CREATE FUNCTION c10_demo.ami_read_ctx(p_business bigint) RETURNS c10_demo.am_ctx_t LANGUAGE sql STABLE AS
$$ SELECT c10_demo.ami_ctx(p_business) $$;
