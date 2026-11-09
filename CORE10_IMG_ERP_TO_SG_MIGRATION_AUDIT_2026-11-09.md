# IMG-ERP (Sydney) → IMG-ERP-SG (Singapore): read-only migration verification

**Audit date:** 2026-11-09 (Bangladesh time)
**Decision:** **IMG-ERP-SG is the active app database. HOLD any deletion or pausing of IMG-ERP until an independently verified external backup and remaining differences are resolved.**
**Audit method:** Supabase connected management project reads + PostgreSQL SELECT-only aggregates and hashed keys; GitHub `config.js` verified. No SQL writes, project pausing, deletion, or data migration performed.

## 1. Exact project identities

- Old: `IMG-ERP`, project ref `bammboumqbbdfhspmear`, region `ap-southeast-2` (Sydney), status `ACTIVE_HEALTHY`.
- Current: `IMG-ERP-SG`, project ref `kbuhnpqooycqbzrfejcs`, region `ap-southeast-1` (Singapore), status `ACTIVE_HEALTHY`.
- Live GitHub app: `mistybari99/islamia-bos-app`, `config.js` points to `https://kbuhnpqooycqbzrfejcs.supabase.co`.
- These are **two different Supabase databases**, but the frontend is configured for **SG**. The earlier paused `Core-10` project is a separate resource; do not mix it with either IMG ERP.

## 2. Structure inventory (read-only)

| Object type | Old IMG-ERP | SG IMG-ERP-SG | Old missing in SG |
|---|---:|---:|---:|
| Public tables | 479 | 489 | 0 |
| Public table primary-key definitions | 479 | 489 | 0 among shared tables |
| Shared table column schemas | 479 | 479 | No old table missing; `locations` schema intentionally differs |
| Public function signatures | 2,908 | 2,932 | 0 |
| Public policies | 486 | 486 | 0 |
| User-defined table triggers | 1,044 | 1,053 | 0 |
| Public indexes | 1,164 | 1,175 | 0 |
| Edge functions deployed | 0 | 0 | 0 |

Implementation difference (not necessarily loss): 145 common function bodies, 4 common trigger definitions, and 1 RLS policy `quick_expenses_sel` differ in SG. These changes require behavior/security regression before wider multi-business rollout.

SG adds 10 public tables, including cost and stock extensions, night count operations, form-code migration and backup table.

## 3. Content and record preservation

- Exact row counts across **all 479 original public tables**: old `4,859`, SG `5,591` across 489 total tables.
- Old nonempty public tables: **75**. No original public table has a **lower row count** in SG.
- Whole-table canonical JSONB row fingerprint: **442 of 479 shared tables identical**; **37 differ**. This includes many empty tables; do not interpret 442 as 442 tables with user data.
- Complete primary-key membership check performed over **every row in all 75 nonempty original public tables**, using hashed keys, not raw personal records. Five source tables originally had key differences:

| Table | Old keys not found unchanged | Explanation |
|---|---:|---|
| `forms` | 41 | 41 form codes intentionally resequenced |
| `form_rollout` | 287 | All matched after old→new form-code mapping |
| `role_form_perms` | 102 | All matched after form-code mapping; permissions for mapped rows matched |
| `forms_ledger_cfg` | 5 | All matched after form-code mapping; `is_on` flags matched |
| `user_favourites` | 4 | One resolved by form-code mapping; **3 old route shortcuts remain absent in SG** |

- All 46 original forms match SG by both Bengali/English labels. 41 were renamed; SG's `form_code_migration_560` explicitly records `forms_changed=41`, `form_rows_changed=394`, `functions_changed=132`, `triggers_changed=4`, `policies_changed=1`.
- The remaining 3 missing favourites use UI route keys `itemimg`, `rules`, `logs`. They were unpinned/unhidden in old user settings. Treat as a small UI-preference discrepancy, **not a verified transfer**. Confirm desired handling before calling migration 100%.
- Rows with matching primary keys can still have different field values: SG has newer edits, and 37 table fingerprints differ. This audit **does not prove every original column value is preserved**. Do not overwrite SG with old values.

### Critical operational records

- `audit_log` old 1,996 IDs, SG 2,327: **all 1,996 old IDs present**.
- `items` old 57, SG 57: **all 57 old IDs present**.
- `locations` old 7, SG 8: **all 7 old IDs present**.
- `org_units` old 3, SG 4: **all 3 old IDs present**.
- `profiles` old 2, SG 4: **all 2 old IDs present**.
- `auth.users` old 2, SG 4: **all 2 old user IDs present**.
- `auth.identities` old 2, SG 4: **all 2 old identity IDs present**.
- `storage.objects` 0 in both; 4 bucket names in both match.
- Old last audit event 2026-10-30 02:22 UTC; SG audit events extend to 2026-11-09 08:24 UTC.

## 4. Project activity, backups, and security

- Both projects currently report `ACTIVE_HEALTHY`.
- Both have `cron.job` `web-holds-expire` active every five minutes. When old is retired, this background job should stop with the old project.
- Old project `backup_runs`: 0. SG project has 11 app backup-run logs (10 `ok`, 1 failed), latest `ok` entry on 2026-11-09. **A successful log row does not prove that a full restorable off-site backup exists**.
- Supabase security advisors report 11 anon-executable SECURITY DEFINER function findings on old, 26 on SG; two mutable-search-path warnings only on SG. Warnings need manual authorization review before cross-business staff rollout; these counts do NOT alone prove exploitability.
- One `quick_expenses_sel` policy differs between old and SG. No original policy, public function signature, trigger, or index name was missing in SG.
- Supabase Free plan project pause documentation describes a **90-day dashboard restore window**; do not treat a paused free project as indefinite archival backup. See https://supabase.com/docs/guides/platform/free-project-pausing .
- Supabase advises off-site database exports for free-tier projects: https://supabase.com/docs/guides/platform/backups .
- Permanent project deletion permanently removes database, auth, storage and backups: https://supabase.com/docs/guides/platform/delete-project .

## 5. Final decision and safe next actions

**KEEP:** IMG-ERP-SG as the one and only **active application** database. Continue all CORE 10 / Islamia ERP development against this project ref, never the old Sydney ref.

**HOLD:** Old IMG-ERP remains unchanged: not paused or deleted during this audit, despite prior request to retire it conditionally. This is because exact preservation is not fully certified (3 missing old shortcuts, updated row values), a full independent off-site backup and restore test have not been verified, and free-tier pause has a time-bounded restore window.

Before decommissioning:
1. Export **a full separate, restorable** backup including schema, public data, Auth identities/users, storage configuration, and required roles/functions; store outside both projects.
2. Confirm an actual restore and login smoke test in an isolated nonproduction environment; do not overwrite SG.
3. Resolve or consciously waive the 3 old favourites; verify form-code migration/permissions and any intentionally changed business values.
4. Review SG SECURITY DEFINER advisories and direct Staff/Owner API authorization, especially when activating multi-business accounts.
5. Only then decide to **pause old** to free a Free-plan active slot, acknowledging the 90-day restore window; irreversible delete requires an explicit final destructive-action decision and backup confirmation.

**Release gate:** The new CORE 10 multi-business Approval Inbox remains frontend read-only until the actual SG RLS and RPC security audit passes. Prior frontend/mock tests must not be mistaken for production API evidence.
