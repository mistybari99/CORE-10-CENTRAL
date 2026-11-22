# CORE-10-CENTRAL — App organization review (2026-11-22)

Read-only review of trunk `ccr-15ed11dd-n3hw5h` @ `98384ab` and live preview source
`preview/core10-central-level2` @ `e9dd90d`. No application code, staging, Supabase or Cloudflare was changed.
Screenshots of the public live app (390 px and 1440 px, 11 routes): `docs/development/app-organization-review/`.

**Verdict:** the *database* is well organized (numbered, ranged, ledgered). The *repository* and the *app shell*
are scattered: about 360 files sit at the repo root, the old IMG-ERP and the new CORE10 are mixed together, and
the live app is put together from 5 pinned commits (2 of them Draft PRs) by a bundler on a separate branch.
The UI has a flat 11-item menu with no Group → Business → Site context, 4 separate sign-in forms and 3 visual themes.

---

## 1. Current state: findings with evidence

### 1.1 Code layout

| Area | Evidence (counts on trunk) | Assessment |
|---|---|---|
| Repo root | **361 entries**: 270 `.js`, 44 `.html`, 26 `.css`, plus svg/webmanifest/json | Scattered |
| Legacy IMG-ERP (Islamia) at root | `index.html` (title "ইসলামিয়া মিষ্টি ঘর"), `owner.html`, `business.html`, `sw.js`, `manifest.json`, `config.js` (`BOS_CONFIG` → old project `kbuhnpqooycqbzrfejcs`), **201 non-`core10-*` JS** (`pos.js`, `payroll.js`, `books85.js` …), 7 legacy CSS (`app.css`, `styles.css`, `theme*.css`, `desktop.css`, `controls.css`, `business-tenant.css`) | Legacy, frozen by REV-009; mixed in with live code |
| `v2/` | **242 files**: 226 have the same name as a root file, **220 are byte-identical**, 6 differ (`index.html`, `owner.html`, `business.html`, `sw.js`, `core10-business-owner.js`, `core10-owner-inbox.js`), plus `v2/data`, `v2/vendor` | Full duplicate copy of the legacy app |
| CORE10 front-end at root | **131 `core10-*` files** in 23 prefix families (owner 26, workforce 16, crm 13, asset 10, operational 7, business 7, engine 6, control 6, build01 6, …) | Flat; module = file-name prefix only |
| …of which live | About **23 root files** are in the live bundle `LIVE` list (owner-control-centre ×5, master-data ×3, owner-dashboard ×5, build01 ×4, pack02 ×3, enterprise-client, control-studio.css, build01-pack02). Sales (5 files) and Manufacturing come from **Draft PR #109 / #112 heads, not trunk** | Less than 20% of `core10-*` is shipped |
| Unported module UIs | Workforce (16), CRM (13), Assets (10), Owner intent/portfolio, Site topology… still at root. Their backends are in `internal/enterprise-sql/` (49 unnumbered A0xx SQL files), **not** in numbered migrations (handover §7.B) | Orphan front-ends; look "done", are not on staging |
| Legacy config leak | **25 `core10-*.html` pages load `./config.js`** (the old IMG-ERP config), e.g. all `core10-workforce-*.html`, `core10-asset-maintenance-*.html`, `core10-business-builder.html`, `core10-site-topology.html` | Risk: CORE10 pages carry the forbidden old project config. `build.mjs` `FORBIDDEN` blocks it from the live bundle today, but only because those pages are not in `LIVE` |
| `modules/` | 1 module only: `modules/manufacturing/` (5 files, from PR #112) | The right pattern, used once |
| `internal/` | 239 files: `migrations/` (106), `enterprise-sql/` (49), `sqlparts/` (20), **27 `setup-run-*.html`/`setup-sql*.html`/`audit-a.html`** one-off pages, plus 10 sub-packages | Mix of tooling, SQL and throw-away pages |
| `experimental/owner-console/` | 10 files (separate console, own `i18n.js`) | Parallel prototype |
| Live shell | lives only on branch `preview/core10-central-level2` (`preview/core10-central-owner-app/site/`: `index.html`, `app.js` 52 lines, `app.css`, 18 `view/*` adapters); trunk has a different `preview/` (3 files) | The real app shell is not on trunk |
| Naming | 4 styles side by side: `core10-<module>-<part>.js`, legacy `name85.js`/`books96.js`/`cheques127.js` (17 files with build numbers in the name), `snake_case` (`crm_360.js`, `forms_cash.js`), `.mjs` in `modules/` | Inconsistent |
| Docs | 129 files; `docs/development/` has 40 `.md`, of which **9 are handover/handoff files** (`AGENT_HANDOVER_CURRENT.md`, `CURRENT_HANDOFF.md`, `CLAUDE_TRUNK_HANDOFF.md`, `CODEX_MASTER_EXECUTION_HANDOVER_…`, …) | Single source of truth is only by convention |
| No `package.json` | Node tests run as bare `node --test …`; no lint/format | No shared toolchain |

### 1.2 Database

| Item | Evidence | Assessment |
|---|---|---|
| Numbered migrations | `internal/migrations/`: **53 up + 53 down**, runner `run.sh` with OUT_OF_ORDER guard, checksum ledger `core10.schema_migrations` | Well organized |
| Ranges | `MIGRATION_RESERVATIONS.json`: 0001–0099 NP01 access/approval/audit/setup; 0100–0109 Control; 0110–0149 NP01-on-Control; 0150–0199 Master; 0200–0299 Stock/Procurement; 0300–0399 Sales; 0400–0499 Finance; 0500–0599 Manufacturing | Clear module boundaries |
| On trunk vs staging | Trunk: 0001–0019, 0100–0106, 0110–0118, 0150–0153, 0200–0206, **0400–0401, 0500–0504**. Staging: 46 rows, max 0206 | Matches ledger |
| Ordering hazard | **No 030x on trunk** but 0400/0401 and 0500–0504 are. Applying Finance/Mfg to staging before Sales makes every later 030x OUT_OF_ORDER | Plan must keep "Sales first" (handover §5.3) or re-range Sales above 0504 |
| Schema | one schema `core10`, 64 tables. Module = table prefix: `master_*`, `stock_*`/`inventory_*`/`purchase_*`/`goods_*`, `finance_*`, `bom_*`/`production_*`/`mfg_*`, `approval_*`, `control_*` | OK; but prefixes are not uniform (stock lane uses 4 prefixes) |
| Naming drift | 0002 core tables have no `_v1` (`tenants`, `businesses`, `sites`, `items`, `stock_movements`); later ones do (`master_uoms_v1`, `finance_journals_v1`). `core10.items` (0002) and `master_*_v1` (0150) both describe items | Document `items` as canonical item header that `master_*` extends, or plan a forward-only rename |
| Second SQL tree | `internal/enterprise-sql/` 49 unnumbered files; still referenced by **31 workflows** | Two database "truths"; new work must only go to `migrations/` |

### 1.3 App / UX structure (live app)

Evidence: screenshots in `docs/development/app-organization-review/<route>-<390|1440>.png`; automated check: no
horizontal overflow at 390 or 1440 on all 11 routes.

| Topic | Found | Professional ERP norm (SAP B1 / Odoo / ERPNext / Zoho) |
|---|---|---|
| Hierarchy | Flat menu of **11 routes** (`home, business, setup, master, stock, sales, manufacturing, control, features, approvals, staff`). No visible current Group / Business / Site; business is chosen inside each page | Persistent **company/branch switcher** in the top bar (Odoo multi-company, ERPNext Company, Zoho Organization); every screen filtered by it |
| Module menu | Mix of modules (Master, Stock, Sales, Manufacturing), admin (Setup, Control, Features) and personas (Owner home, Staff) in one list | App launcher by **module** (Inventory, Sales, Purchase, Manufacturing, Accounting, HR); Settings/Admin separate; persona = home page, not a menu item |
| Role home pages | `home` = owner workspace sample, `staff` = staff sample, `business` = signed owner dashboard. No Business-owner / Manager home | One role-based **home dashboard** per role after login (Odoo Discuss/Dashboard, ERPNext Workspace per role) |
| Sign-in | Shell has no session. **4 routes each show their own sign-in form** (`setup`, `control`, `master`, `stock`), in different styles | Single sign-in once; shell holds session and tenant context |
| Design system | 3 looks in one app: light green shell; dark navy `build01`/`control`/`stock`; dark mfg workbench with amber chips. Only `core10-owner.css` has a real token set (23 CSS variables, 313 lines); 20 other CSS files have 0–4 variables | One token set (color, spacing, type, radius) + component library |
| Language | Shell toggle বাংলা/EN works, but in bn mode `setup` H1 is English ("Business Setup, Login & Permissions Integration"), `approvals` H1 "Approval Desk"; mixed bn/en labels in cards ("Portfolio", "tenant", "engine"). 17 pages `lang="bn"`, 24 `lang="en"` | All UI strings from one dictionary per language |
| Responsive | 390 px: menu becomes a horizontal scroll strip of 11 items (only 5 visible); inner pages do not overflow | Bottom tab bar (4–5 items) + "More" on Android |
| Status honesty | Good: banner states "sample data / signed staging"; Draft-only routes (sales, manufacturing) show a yellow "not connected" notice | Keep |
| Iframe shell | Each route loads a separate HTML page in `#c10-frame` | Acceptable now; blocks shared session/context, deep links and back button inside modules |

### 1.4 Tests / CI

| Item | Evidence | Assessment |
|---|---|---|
| Workflows | **65** files (63 active, 2 `.disabled`) | Too many to reason about |
| Overlap | 62 have `paths:` filters, 61 run on `pull_request`, 61 have `workflow_dispatch`; 37 start their own Postgres (`postgres:17` ×47 refs plus `postgres:ci`/`postgres:demo` images); 27 install Chromium; only **8** run the canonical `internal/migrations/run.sh`; **24** trigger on pushes to old `feature/c10-a0*` branches only; only **1** names the trunk branch | Many lane-per-file workflows; most guard pre-trunk code |
| Tests | 289 files: 59 Node tests, 95 SQL, 42 shell, 2 Python; **103 files loose at `tests/` root** (`c10_a0xx_*`, `core10-*`), rest in 17 sub-folders (`migrations/` 56, `np05a/` 24, `pack02/` 19…) | Same scattering as the source |
| Node versions | 22 everywhere (3 quoting styles) | OK |
| Live verification | `verify.cjs` 56/56 local + public PASS (handover §3) | Good gate, but on the preview branch only |

---

## 2. Target structure

### 2.1 Folder layout (target, reached by moves, not rewrites)

```
apps/
  central/                 # the one app shell (today: preview/core10-central-owner-app/site on preview branch)
    shell/                 # top bar, context switcher, nav, session, i18n loader
    routes.json            # route → module view, roles, live/draft status
modules/                   # one folder per business module, same shape each
  control/  master/  stock/  procurement/  sales/  finance/  manufacturing/
  workforce/  assets/  crm/  setup/  approvals/  owner-dashboard/
    ui/ (html, view js)   client/ (RPC client)   i18n/ (bn.json, en.json)   tests/
packages/
  design-system/           # tokens.css, components.css, icons
  i18n/                    # loader + shared glossary (bn/en)
  rpc/                     # signed Supabase client wrapper (one session)
db/ (or keep internal/migrations/)   # numbered migrations only; README per range
tools/                     # build.mjs, verify.cjs, staging scripts, setup-run pages
legacy/
  islamia-erp/             # root legacy JS/HTML/CSS + v2/ — frozen (REV-009), never bundled
  enterprise-sql/          # A0xx unnumbered SQL kept for porting reference
docs/  (handover/, architecture/, coordination/, strategy/, reviews/)
tests/ (cross-module e2e + migrations only; unit tests live in modules/*/tests)
.github/workflows/  (≈8 workflows, see §3 step 9)
```

### 2.2 Navigation / information architecture

```
Platform (Goal 2, later: customers, plans, audited support mode)
 └─ Group / Tenant  (Owner's group)          ← top-bar switcher level 1
     └─ Business  (Sweets, Paint, …)         ← level 2
         └─ Site  (branch / factory / warehouse, 100–400) ← level 3, searchable, grouped by region/type
```

- **Top bar:** logo · `Group ▸ Business ▸ Site` breadcrumb switcher (search, recent, favourites) · global search · approvals bell · বাংলা/EN · user menu.
- **Left menu (desktop) / bottom bar + "More" (Android):** module launcher filtered by role and by modules enabled for the business.
- **Admin area** (separate entry, gear icon): Setup, Owner Control, Features/permissions, Users & roles.

| Role | Lands on | Sees |
|---|---|---|
| Owner (group) | Group dashboard: all businesses KPIs, pending decisions | Everything; can enter any business |
| Business owner | Business dashboard: sites, stock, sales, approvals | Own business, all sites |
| Site manager | Site dashboard: today's tasks, stock alerts, approvals queue | Own site(s) |
| Staff | "My work": tasks, entry forms (sale, receive, attendance) | Only assigned actions |

### 2.3 Module map

| Module | DB range | Trunk migrations | Live route | Status |
|---|---|---|---|---|
| Access / Setup / Approvals / Audit | 0001–0099, 0110–0149 | 0001–0019, 0110–0118 | `setup`, `approvals` | signed / offline preview |
| Control | 0100–0109 | 0100–0106 | `control`, `features` | signed / sample |
| Master data | 0150–0199 | 0150–0153 | `master` | signed |
| Stock + Procurement (+QC/lot) | 0200–0299 | 0200–0206 | `stock`, `business` | signed |
| Sales / POS | 0300–0399 | none | `sales` | replay from Draft PR #109 |
| Finance | 0400–0499 | 0400–0401 | none | not on staging |
| Manufacturing | 0500–0599 | 0500–0504 | `manufacturing` | replay from Draft PR #112 |
| Workforce/Payroll, Assets, CRM, Paint tint | to be allocated (e.g. 0600–0899) | none | none | UI exists at root, backend unported |

### 2.4 Design system

- One `packages/design-system/tokens.css` (start from the 23 variables in `core10-owner.css`): colors (brand green, surface, text, status ok/warn/error/draft), spacing 4/8/12/16/24, radius, type scale with a Bangla-capable font stack, light + dark.
- Components: top bar, context switcher, nav, card, KPI tile, table/list (virtualized for 400 sites), form field, button, status chip (LIVE/SIGNED/SAMPLE/DRAFT), empty/error state, sign-in.
- i18n: every visible string by key in `modules/*/i18n/{bn,en}.json`; a test fails if a bn page renders Latin-only headings.
- Mobile rules: 390 px first, 44 px touch targets, bottom bar ≤ 5 items, no horizontal page scroll (already checked per route).

---

## 3. Reorganization plan (prioritized, small safe steps)

Rules: one step = one small PR into trunk; `git mv` only (no content change in the same commit); live bundle pins
are commit-addressed, so moves on trunk never change the running Worker until `build.mjs` pins are bumped.

| # | Step | Why | Test / gate |
|---|---|---|---|
| 1 | **Add `docs/coordination/FILE_CLASSIFICATION.json`**: every root file tagged `LIVE`, `TRUNK_UNSHIPPED`, `LEGACY_FROZEN`, `TOOLING` (generated from `build.mjs` LIVE list + `core10-*` prefix + legacy list) | Makes the mess visible without moving anything | New Node test: every root file is classified; every `LIVE` path exists at its pinned commit |
| 2 | **Guard the legacy config:** test that no file in `LIVE`/`modules/` references `config.js`, `v2/`, `BOS_CONFIG` or `kbuhnpqooycqbzrfejcs`; list the 25 `core10-*.html` that load `./config.js` as known debt | Stops the old IMG-ERP project leaking in when those pages are later shipped | Node test + reuse `build.mjs` `FORBIDDEN` regex |
| 3 | **Bring the shell onto trunk:** copy `preview/core10-central-owner-app/{site,build.mjs,verify.cjs,worker-runtime.mjs}` to `apps/central/` on trunk (preview branch unchanged and still deploys) | One source of truth for the real app | `node apps/central/build.mjs` output byte-equal to preview branch `dist/worker.mjs`; `verify.cjs` 56/56 local |
| 4 | **Design tokens:** extract `packages/design-system/tokens.css` from `core10-owner.css`; shell and the 4 signed views (`setup`, `control`, `master`, `stock`) import it; no layout change | Ends the 3-theme look | Screenshot diff at 390/1440 for 11 routes (this review's script); verify.cjs PASS |
| 5 | **Single sign-in + context bar in the shell:** shell owns the Supabase session and `Group ▸ Business ▸ Site` selection, passes it to frames via `postMessage`; signed views stop showing their own form when a session exists | Biggest UX gap vs SAP B1/Odoo | Browser test: one login then visit `setup`, `control`, `master`, `stock` with no 2nd form; cross-tenant denial tests unchanged |
| 6 | **Regroup the menu:** Modules (Dashboard, Master, Stock, Sales, Manufacturing, Finance) / Admin (Setup, Control, Features, Approvals); persona routes become role home pages; Android bottom bar | IA per §2.2 | Route-map test; 390 px screenshot shows ≤ 5 bottom items |
| 7 | **i18n sweep:** move strings of the 4 signed views + shell to `bn/en` JSON; fix English H1s in bn mode | Owner works in Bangla | Test: bn mode has no Latin-only `h1`/`h2`/nav labels |
| 8 | **Move live modules into `modules/<name>/`** one at a time (master → stock → control → setup), `git mv` + import path edits, bump pins | Module folders like `modules/manufacturing/` | Module tests + migration tests + verify.cjs PASS before pin bump; rollback = old pin |
| 9 | **CI consolidation:** keep ≈8 workflows (`db-migrations` PG17 up/down/up + lane SQL, `node-unit`, `browser-390-1440`, `live-verify`, `security/forbidden-files`, `legacy-preservation`, `docs-lint`, `release-gate`); move the 24 `feature/c10-a0*`-only workflows to `.github/workflows-archive/` (not run) | 65 → ≈8, one Postgres image | Run old and new side by side on trunk for one week; same PASS set |
| 10 | **Legacy quarantine (Owner approval):** `git mv` root legacy JS/HTML/CSS + `v2/` into `legacy/islamia-erp/`, update `internal/core10-pages-package.js` `REQUIRED` and the legacy-preservation test paths | Root shrinks from 361 to ~20 entries; REV-009 preserved byte-for-byte | `core10-legacy-preservation.test.js` + `forbidden-files.test.js` PASS; sha256 manifest of moved files equal before/after |
| 11 | **Docs:** one `docs/handover/CURRENT.md`; move the 8 other handoff files to `docs/handover/archive/` | One entry point | Link check |
| 12 | **Port backlog by module** (Sales fix → Finance → Paint → Procurement/QC → Workforce → Assets → CRM) into `modules/<name>/` + numbered migrations; allocate 0600+ ranges in `MIGRATION_RESERVATIONS.json` | Turns orphan root UIs into real modules | Existing lane gates (PG17, signed staging rehearsal, backup) |

**Top 5 to do first:** 1 (classify), 2 (legacy config guard), 3 (shell on trunk), 5 (single sign-in + context bar), 4 (tokens).

---

## 4. Risks

| Risk | Mitigation |
|---|---|
| Moving files breaks pinned live bundle | Live pins are commit SHAs; moves only take effect after a pin bump with verify.cjs 56/56 and the recorded rollback version |
| Moving legacy breaks REV-009 preservation, the A040 Pages package (`REQUIRED` = root `index.html`, `owner.html`, `business.html`, `sw.js`, `v2/index.html`, `v2/sw.js`) and ~24 old workflows | Step 10 last, with Owner approval and a sha256 before/after manifest; update `REQUIRED` in the same PR |
| Shipping a root `core10-*` page that loads `./config.js` would put the old IMG-ERP project into the CORE10 app | Step 2 test; `FORBIDDEN` already in `build.mjs` |
| Applying 0400/0500 to staging before Sales 030x locks Sales out (OUT_OF_ORDER) | Keep "Sales 030x first" (handover §5.3) or have the Board move Sales above 0504 before any Finance/Mfg hosting |
| Shared session across frames widens attack surface | `postMessage` with exact origin check; token stays in shell; existing signed RPC + RLS remain the authority; cross-tenant negative tests in each step |
| 400-site switcher performance on Android | Server-side search + paging RPC; test with the 400-site staging fixture before enabling |
| Parallel agents editing the same root files during moves | Announce each move in Issue #110 / `WORK_SPLIT_AND_PROTOCOL.md`; one module per PR; respect Claude-owned A052–A055 namespaces |
| CI consolidation hides a lost check | Run old and new workflows in parallel until both show the same PASS set on the same SHA |
