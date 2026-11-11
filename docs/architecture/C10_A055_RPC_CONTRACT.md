# C10-A055 — Enterprise Assets & Maintenance: RPC contract (authoritative)

Schema `c10_demo` (disposable only). Public API = `am_*_v1` / `read_asset_maintenance_business_summary_v1`, all
`SECURITY DEFINER SET search_path=c10_demo,pg_catalog`, `GRANT EXECUTE ... TO authenticated` only (lockdown file).
Internal helpers `ami_*` are NOT executable by `authenticated`/`anon`. Direct table access is revoked.

## Conventions
* **Writes**: `(p_business bigint, p_request text, ...)` → `jsonb` containing `status` (`applied` / `replayed` is transparent: a replay
  returns the *original* receipt). Begin with `ami_begin`, finish with `ami_finish`, audit with `ami_log`.
  Request key `^[A-Za-z0-9_-]{8,100}$`; same key + different payload/actor/op → `am_idempotency_conflict`.
  Per-business serialisation: `ami_begin` takes `FOR NO KEY UPDATE` on `businesses` after authorising.
* **Reads**: `(p_business bigint, ...)` → `jsonb`, STABLE, use `ami_read_ctx`; never insert rows. Lists → `{items:[...],total:n}`.
* **Optimistic concurrency**: mutable rows carry `version`; updates take `p_expected_version`, else `am_stale_version`.
* **Errors** (stable `RAISE EXCEPTION '<code>'`): `am_denied` (outsider / revoked / other tenant — also for hidden entities),
  `am_not_permitted` (member lacking capability at that site), `am_owner_required`, `am_invalid_input`, `am_stale_version`,
  `am_idempotency_conflict`, `am_invalid_request_key`, plus specific `am_*` codes documented per RPC.
* **Authority** comes only from DB state (`ami_ctx`). JWT claims/roles never elevate. Capabilities per role: see `ami_role_caps`.
  `ami_has(c,site,cap)` / `ami_need_cap(c,site,cap)`; owners = tenant owner or business_owner.
* **Policy** via `ami_cfg_*(business, site, category, key)` (category > site > business > default). Keys: `am_policy_catalog`.
* **No side effects outside module**: no stock, ledger, payroll or purchase writes. Money fields are ADVISORY.
* JSON keys are snake_case = column names unless noted. Timestamps ISO-8601 (timestamptz), dates `YYYY-MM-DD`.

## File ownership / load order
`core` (tables, helpers, policy catalog, audit) → `policy` → `registry` → `planning` → `workorders` → `reports` → `lockdown`.
Cross-file internals (plpgsql, so definition order is not validated, but names/signatures are fixed here):
* `ami_create_wo(c am_ctx_t, p_request text, p_asset bigint, p_kind text, p_title text, p_description text, p_priority text,
   p_source text, p_target bigint, p_due date, p_checklist_code text, p_extra jsonb) RETURNS bigint` — owned by **planning**;
  inserts the work order (status `DRAFT`, or `SUBMITTED` when `p_extra->>'submit'='true'`), numbers it, computes SLA due times from policy,
  snapshots the active checklist template into `am_wo_checklist`, writes the `am_wo_history` row; no audit/receipt (caller does).
* `ami_complete_target(p_target bigint, p_done_on date, p_reading numeric) RETURNS void` — owned by **planning**; re-anchors the plan
  target (`last_done_*`, `next_due_*` by policy `schedule.anchor`/plan anchor), called by workorders on completion of plan-sourced WOs.

## policy file (core owner)
`am_whoami_v1(p_business)` · `am_policy_catalog_v1(p_business)` · `am_get_policy_v1(p_business,p_site,p_category)` ·
`am_save_policy_v1(p_business,p_request,p_expected_rev,p_scope_type,p_scope_id,p_changes jsonb,p_reason)` ·
`am_reset_policy_v1(p_business,p_request,p_expected_rev,p_scope_type,p_scope_id,p_keys text[],p_reason)` ·
`am_apply_preset_v1(p_business,p_request,p_expected_rev,p_preset,p_scope_type,p_scope_id,p_reason)` ·
`am_preview_policy_v1(p_business,p_scope_type,p_scope_id,p_changes jsonb)` (simulation, no writes) ·
`am_simulate_schedule_v1(p_business,p_params jsonb)` (pure) · `am_policy_history_v1(p_business,p_limit)` · `am_bootstrap_v1(p_business,p_request)`.

## registry file
Writes: `am_grant_role_v1(p_business,p_request,p_user uuid,p_role,p_site bigint,p_note,p_reason)` (owner) ·
`am_revoke_role_v1(p_business,p_request,p_grant bigint,p_reason)` (owner) ·
`am_save_category_v1(p_business,p_request,p_id,p_expected_version,p_data jsonb,p_reason)` (owner) ·
`am_save_code_v1(p_business,p_request,p_kind,p_code,p_label,p_label_bn,p_active,p_reason)` (owner) ·
`am_create_asset_v1(p_business,p_request,p_data jsonb,p_reason)` (cap `asset_write` at data.site_id; data may embed `meters:[{code,unit,reading}]`, `warranty:{...}`) ·
`am_update_asset_v1(p_business,p_request,p_asset,p_expected_version,p_changes jsonb,p_reason)` (not site/status/asset_no) ·
`am_set_asset_status_v1(p_business,p_request,p_asset,p_expected_version,p_status,p_reason)` (active/idle/retired/disposed guarded; retire/dispose blocked by open WO/downtime/children) ·
`am_request_transfer_v1(p_business,p_request,p_asset,p_to_site,p_include_children,p_reason)` · `am_decide_transfer_v1(p_business,p_request,p_transfer,p_expected_version,p_decision,p_note)` (`approve|reject|cancel`) ·
`am_add_meter_v1(p_business,p_request,p_asset,p_code,p_unit,p_initial_reading)` · `am_record_meter_reading_v1(p_business,p_request,p_meter,p_reading,p_read_at,p_kind,p_note)` ·
`am_save_warranty_v1(p_business,p_request,p_id,p_expected_version,p_data jsonb,p_reason)` · `am_save_claim_v1(p_business,p_request,p_id,p_expected_version,p_data jsonb)` ·
`am_claim_transition_v1(p_business,p_request,p_claim,p_expected_version,p_action,p_data jsonb)` (`submit|accept|reject|settle|close`).
Reads: `am_list_grants_v1(p_business)` (owner) · `am_list_catalog_v1(p_business)` → `{categories,codes,sites,assets_brief?}` · `am_list_assets_v1(p_business,p_filters jsonb,p_limit,p_offset)`
(filters: `search,status,category_id,site_id,parent_asset_id,ownership`) · `am_get_asset_v1(p_business,p_asset)` · `am_list_transfers_v1(p_business,p_status)` ·
`am_list_claims_v1(p_business,p_status,p_limit,p_offset)` · `am_list_warranties_v1(p_business,p_asset)`.

## planning file
Writes: `am_save_checklist_template_v1(p_business,p_request,p_code,p_name,p_category_id,p_items jsonb,p_reason)` (new immutable version each save) ·
`am_save_plan_v1(p_business,p_request,p_id,p_expected_version,p_data jsonb,p_reason)` · `am_generate_work_orders_v1(p_business,p_request,p_target_ids bigint[],p_site,p_horizon_days)` ·
`am_defer_target_v1(p_business,p_request,p_target,p_until,p_reason)`.
Reads: `am_list_checklists_v1(p_business,p_include_inactive)` · `am_list_plans_v1(p_business,p_filters jsonb)` · `am_due_suggestions_v1(p_business,p_site,p_horizon_days)` ·
`am_calendar_v1(p_business,p_from,p_to,p_site)` → `{days:[{date,items:[...]}]}`.
Due states: `upcoming|due|overdue|meter_missing|deferred|has_open_wo`; `escalation_level` 0/1/2. Suggestions are computed on demand (no background job).

## workorders file
Writes: `am_create_work_order_v1(p_business,p_request,p_data jsonb)` · `am_update_work_order_v1(p_business,p_request,p_wo,p_expected_version,p_changes jsonb,p_reason)` ·
`am_assign_work_order_v1(p_business,p_request,p_wo,p_expected_version,p_assigned_to uuid,p_assignee_ref,p_team_ref,p_reason)` ·
`am_wo_transition_v1(p_business,p_request,p_wo,p_expected_version,p_action,p_reason,p_data jsonb)` (`submit|approve|return|start|complete|verify|close|cancel|reopen`) ·
`am_wo_checklist_result_v1(p_business,p_request,p_wo,p_seq,p_result,p_value,p_note)` · `am_wo_add_labor_v1(p_business,p_request,p_wo,p_data)` ·
`am_wo_add_spares_v1(p_business,p_request,p_wo,p_data)` · `am_wo_add_attachment_v1(p_business,p_request,p_wo,p_data)` · `am_acknowledge_safety_v1(p_business,p_request,p_wo)` ·
`am_merge_work_orders_v1(p_business,p_request,p_keep,p_merge,p_reason)` · `am_report_breakdown_v1(p_business,p_request,p_asset,p_data)` ·
`am_start_downtime_v1(p_business,p_request,p_asset,p_data)` · `am_end_downtime_v1(p_business,p_request,p_downtime,p_ended_at,p_note)`.
Reads: `am_list_work_orders_v1(p_business,p_filters jsonb,p_limit,p_offset)` (filters: `status[],kind,site_id,asset_id,priority,assigned_to('me'),overdue,search`) ·
`am_get_work_order_v1(p_business,p_wo)` (includes `available_actions[]` computed server-side for the caller) · `am_my_work_v1(p_business)` · `am_list_downtime_v1(p_business,p_filters,p_limit,p_offset)`.

## reports file
`am_overview_v1(p_business,p_site)` · `am_downtime_report_v1(p_business,p_from,p_to,p_site)` · `am_kpi_report_v1(p_business,p_from,p_to,p_site)` ·
`am_asset_health_report_v1(p_business,p_site)` · `am_warranty_report_v1(p_business,p_horizon_days)` · `am_reconciliation_v1(p_business,p_from,p_to)` ·
`am_export_csv_v1(p_business,p_request,p_kind,p_params jsonb)` (`assets|work_orders|downtime|schedule|warranty|audit`) · `am_integrity_report_v1(p_business)` ·
`am_audit_log_v1(p_business,p_entity,p_entity_id,p_limit,p_offset)` · `read_asset_maintenance_business_summary_v1(p_business,p_period date)` (A050 adapter, owner only, aggregate, no personal data).
