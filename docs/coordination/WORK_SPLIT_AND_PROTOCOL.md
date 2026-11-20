# CORE10 — two-builder work split, shared control and the Owner Control rule

Status: in force from 2026-11-16 by Owner instruction. Adds DEC-08 and DEC-09 to the
Owner-delegated decisions (C10-AUDIT-CG-01-DEC). The Master Decision Book stays the authority.

## 1. Branches

| Branch | Role | Who pushes |
| --- | --- | --- |
| `ccr-15ed11dd-n3hw5h` (Draft PR #106) | **Trunk**: the one integrated line everybody builds from | Claude only |
| `build/chatgpt-np01` | ChatGPT's working branch, forked from trunk | ChatGPT only |
| `main`, `preview/c10-integrated-20261111-v1`, legacy IMG-ERP-SG | Untouched without a separate Owner GO | nobody |

Rules:

1. Nobody pushes to the other builder's branch. Work reaches trunk only by integration.
2. ChatGPT opens one Draft PR from `build/chatgpt-np01` **into the trunk branch** and keeps it green.
3. Integration: when a lane's PR is green and its board row says `READY_FOR_INTEGRATION`, Claude
   verifies it (static contract, up → down → up, the lane's tests, security catalog checks) and
   merges it into trunk. Findings go back on the board row; nothing is silently rewritten.
4. Each builder merges trunk into its own branch before starting a new task and before asking
   for integration. No rebase or force-push of shared history.
5. A red CI job is fixed, never skipped or disabled.

## 2. Shared control centre

The board is the single place both builders read before work and write after work:

**CORE10 BUILD COORDINATION BOARD** (Google Sheet, link in section 7).

| When | What to write on the board |
| --- | --- |
| Before starting | A row: lane, pack/step, task, branch, reserved migration numbers, `CLAIMED` |
| While working | Status `IN_PROGRESS`, current head SHA |
| When done | `READY_FOR_INTEGRATION`, head SHA, CI result, evidence link, what is NOT done |
| After integration | Trunk owner sets `INTEGRATED` and the trunk SHA, or `RETURNED` with findings |
| When stuck | `BLOCKED` and what is needed from whom |

A task that is not on the board is not claimed. A file or pack claimed by one lane is not edited
by the other; needs go on the board as a request. The Master Decision Book continues to record
decisions; the board records who is doing what right now.

## 3. Lanes

| Lane | Owner | Scope now | Migration block |
| --- | --- | --- | --- |
| NP01 access, approval, audit, setup | ChatGPT | Finish S1-c: GOV-002 thresholds, exception, escalation; GOV-003 from PR #85 on the canonical audit stream; setup profiles PR #94; GOV-001 partials; locale and legacy-import preview; TRUNCATE guard on audit and approval journals | 0001–0099 |
| NP02 master data + Owner Control port | Claude | Party/supplier, item, variant, UOM, barcode, price list; the Owner Control port of section 5 | 0100–0199 |
| NP03A procurement, inventory, lot/QC | Claude (after NP02) | PO → GRN → QC → stock → transfer | 0200–0299 |
| NP03B sales core, POS | open — claim on the board | Order → invoice → collection → return | 0300–0399 |
| NP06 finance | ChatGPT (after NP01) | Chart of accounts, source-linked journal, AP/AR, valuation, close | 0400–0499 |
| NP05A manufacturing (sweets slice first) | open | BOM, batch, yield, waste, costing | 0500–0599 |
| NP07 HR, NP05B assets, CRM, reports, industry adapters, integration | open | Claimed one at a time on the board | 0600 onward, reserved on the board |
| Trunk infrastructure | Claude | `internal/migrations/run.sh`, `tests/migrations/migration-contract.test.js`, shared CI, `docs/coordination/`, legacy-versus-migration drift test | — |

Migration numbers: unique, contiguous inside a block, each with a rollback. Blocks are in
dependency order, so numeric order is a valid apply order. A lane never uses another block.

## 4. What every feature must deliver (definition of done)

1. Reaches engines only through the ports: Auth, Master, Stock, Money, Approval + Audit, and Control.
2. Numbered migration with rollback; RLS; no PUBLIC/anon rights; pinned `search_path`.
3. Registered in the Owner Control catalog (section 5).
4. Reachable from the Central shell under signed context, 390 px and 1440 px, Bangla and English.
5. Positive and negative tests with synthetic data and the demo personas; honest "not done" list.

## 5. DEC-08 — the Owner Control rule

Owner requirement: for any feature at all, the Owner can approve, switch off, switch on and
adjust it from the app; an option the Owner thinks of in real business must not be missing.

So every feature (every Detail ID, existing and future) is built with these controls, held in one
Control port (the existing control catalog/settings engine A044, rule engine A045 and owner
intent engine A052, moved onto `core10`), never as code constants:

| Control | Meaning | Enforced where |
| --- | --- | --- |
| On / off | Per business, and per site where it makes sense; default comes from the template | Server: the RPC refuses with a clear "switched off by Owner" result; the menu hides it |
| Approval required | None, or a 1–5 stage route with amount/quantity thresholds, per action | Approval port (GOV-002); the action waits for the decision |
| Who may do it | Roles/people per action, with expiry and explicit deny | Auth port |
| Limits and parameters | Amounts, quantities, percentages, tolerances, time windows, numbering, required fields | Control settings, typed and versioned |
| Effective date and scope | From when, for which business/site; scheduled changes | Control settings versions |
| Owner override | Owner can approve an exception once, with reason | Approval port, recorded |
| History and undo | Who changed which control, when, previous value; revert | Canonical audit |

Three guarantees:

1. **Nothing hard-coded.** A rule that a business could reasonably want different (a limit, a
   required step, a default, a rounding, who approves) is a control, not a constant.
2. **One Owner Control Centre.** Every registered feature appears in one screen in the Central
   app with its switches, approval route and parameters, searchable in Bangla and English.
3. **No dead end.** When the Owner wants an option that does not exist yet, the app takes the
   request in plain language (owner intent, A052), shows what can be done now with existing
   controls, and files the rest as a numbered engineering requirement that appears on the board.

Test that keeps this honest (trunk infrastructure): a CI check lists every state-changing RPC in
`core10` and fails when one is not mapped to a feature key in the control catalog with an on/off
control and an approval binding (which may be "none"). A feature without its controls is not done.

## 6. DEC-09 — order of work from here

1. ChatGPT: finish NP01 (S1-c) on its branch. Claude: Control port + NP02 master data on trunk.
2. Claude: NP03A. ChatGPT: NP06 journal core. NP03B claimed by whoever is free first.
3. NP05A sweets slice, then **sweets_bakery end to end** with all demo personas — the first full
   walkthrough for the Owner (Owner ID only).
4. Remaining templates one at a time: restaurant, retail_wholesale, paint_hardware,
   general_manufacturing, construction, import_export, ecommerce, services, technology_digital.
5. HR, assets, CRM, reports and integration lanes run beside this, claimed on the board.

## 7. Links

- Board: see `docs/coordination/BOARD_LINK.md`
- Plan: Final Decisions, Change Register, 520-row sheet, Code Gap Audit (links in `docs/development/HANDOFF_S1_2026-11-16.md`)

## 8. DEC-10 — push and preview cadence (Owner instruction 2026-11-16)

1. **No held work.** Every builder pushes to its own branch at the end of each working step, and
   at the latest after two to four substantial pieces of work. Unpushed local work does not count
   as done and is not reported as done. The board row gets the pushed SHA the same day.
2. **Integration follows quickly.** A green lane PR marked `READY_FOR_INTEGRATION` is verified and
   merged into trunk before the trunk owner starts new work of its own.
3. **Preview for the Owner after every two to four substantial pieces of integrated work** (this
   tightens the earlier "every two verified major builds" rhythm). Each preview states exactly
   what is real and what is synthetic, and comes with a short Bangla "where to click, what to
   see" list.
4. Preview levels, in the order they become available:
   - Level 1 — synthetic click-through of the trunk UI, no sign-in, no database.
   - Level 2 — Owner signs in with the Owner ID against a separate staging database that holds
     synthetic data only. Needs a staging project that is not IMG-ERP-SG.
   Publishing either level outside GitHub is a deployment and needs the Owner's GO for that level once.
