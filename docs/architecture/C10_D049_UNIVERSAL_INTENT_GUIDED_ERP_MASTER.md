# CORE 10 CENTRAL — Universal Owner Intent → ERP Engineering & Guided Experience
**MASTER OWNER DECISION: C10-D049 / REQUIREMENT: R128 / DELIVERY EPIC: C10-A052**
**Date:** 2026-11-11 (Asia/Dhaka)  
**Status:** Owner-approved, **architecture and implementation mandate**; NOT equivalent to working universal engineering engine or completed all-industry ERP.

> বাংলা মূলনীতি: একজন ব্যবসার Owner-কে কোডিং, ডেটাবেস, ক্যালকুলেশন বা সফটওয়্যার-লজিক জানতে হবে না। তিনি নিজের ভাষায় বলবেন, “এইভাবে করতে চাই”, “এই হিসাব/রিপোর্ট চাই”, “এই permission বা approval চাই”, “এভাবে দেখতে চাই”—CORE 10 CENTRAL-কে সেই চাহিদার জন্য কোন data, business rules, formula, access, workflow, feature, UI, integration, report ও tests প্রয়োজন তা নির্ধারণ ও বাস্তবায়ন করার ব্যবস্থা রাখতে হবে। পুরো ERP-এর যেকোনো বিভাগে এটি প্রযোজ্য, শুধু কয়েকটি প্যাকেজে নয়।

**Owner's additional mandatory guidance:** Every relevant button, control, field, workflow, report and calculation should communicate in short, context-specific, accessible language:
- **What:** এটা কী ও কেন আছে?
- **When:** কোন পরিস্থিতিতে সাধারণত এটি ব্যবহার করা উচিত?
- **Effect:** এখন ক্লিক করলে ঠিক কী বদলাবে? কি বদলাবে না?
- **Result:** ফলাফল/রিপোর্ট কোথায় দেখা যাবে; কোন business/site/role-এ?
- **Logic:** হিসাব কীভাবে হলো? সূত্র, input, unit, date window, discount, rounding, exceptions ও source কী?
- **Typical vs exceptional:** সুপারিশকৃত সাধারণ পদ্ধতি কী? ব্যতিক্রম চাইলে অনুমোদিত বিকল্প এবং তার পরিণতি কী?
- **Try:** নিরাপদ ছোট demo example, sample-data walkthrough বা isolated preview থাকলে দেখাবে; না থাকলে কার্যকর নির্দেশনাই বাধ্যতামূলক।
- **Trust:** এটি অনুমান, simulation, draft, বাস্তব transaction নাকি posted/certified result—কোনটি?

## Scope and authority
This decision is **ERP-wide, universal, business-neutral, multi-tenant, multi-industry and cross-module**. It builds on, rather than replacing, the existing approved D033/D045/R123/R124 (Universal Studio / certified engine registry), D046/R125 (synthetic personas), D047/R126 (demo-first end-to-end structure), D048/R127 (all A048/A049/A050 built). Not a request to create a separate AI application, another database of users, shadow ledger, second Decision Book or unauthorized live release.

### Owner journey: describe → understand → configure/extend → safely apply
1. **Plain-language intent:** Owner says or types a need in their own words, in Bangla or English, from any relevant screen or Central Studio, without naming a technical module. Allow screenshots/examples when a supported media input exists; do not require screenshots.
2. **Context capture:** Resolve authorized tenant, business, location/site/group, user role, product/service, units, dates, target output and purpose using existing data. Do not demand information the app already has. Ask only essential missing details.
3. **Interpretation card:** Show "You asked for", assumptions, what input is necessary, intended effect/result, selected business/site scope, confidence/uncertainty and a human-editable confirmation. AI suggestions do not themselves change real data.
4. **Dependency and compatibility graph:** Match intent to canonical records, module registry, calculation/report engine, approved handlers, API events and downstream consumers. Show conflicts: missing sales records → cannot produce reliable net profit; stock transfer does not imply sale; payroll approval does not imply payout; hidden menu does not grant/deny backend permission.
5. **Feasibility classification:** \`CONFIGURABLE_NOW\` (supported certified handler) / \`NEEDS_HANDLER_BUILD\` (new implementation/test required) / \`BLOCKED_SAFETY_OR_DATA\` / \`ADVISORY_PREVIEW_ONLY\` / \`RELEASE_GATED\`. No misleading generic green "Ready."
6. **Blueprint:** Translate to versioned typed requirements: data inputs/schema references, business rules, formula, output mapping, permission/approval, state transitions, UI placement, report definition, edge cases, tests, migration/dependency and rollback strategy; identify impacted modules and domain owners. The Owner sees an understandable preview, not raw code.
7. **Execution path:** Supported owner-configurable choices go through the one canonical A045 Micro-Engine registry and existing A034 signed permission contract. A new handler must be designed/implemented/tested/certified before execution; no free-form SQL, JS \`eval\`, code execution or arbitrary RPC triggered from an Owner prompt. Changes audited, approved where needed, scoped and reversible only as safe configuration.
8. **Proof and result:** Safe preview, before/after impact, expected reports + location, formula trace, server denial/acceptance, demo cases, integrity/role tests, activity history. User should always know what happened and where the result is visible.

## Canonical architecture (no shadow engines)
\`\`\`
Owner Intent / Any Screen / Guided Help
        ↓   Captured Intent + Context + Assumptions
Requirement Interpreter & Typed Blueprint
        ↓
Capability + Domain + Dependency/Compatibility Registry
        ├── Data Contracts / Canonical Entity Resolver
        ├── Certified Rule, Workflow, Calculator, Report & Approval Handlers
        ├── A045 Micro-Engine Workshop + A044 Owner Control Studio
        ├── A034/A021 Effective Authorization & Revocation
        ├── A018/A020/A047 Tenant→Business→Site→Location graph
        ├── A048 Canonical Stock Posting / A027 Production
        ├── A049 Purchase/Sales/COGS/Finance (only as certified)
        ├── A050 Owner Portfolio / A051 Workforce/Payroll
        └── UI placement + Contextual Explanation Registry
        ↓
Validation → Simulation/Impact → Authorized Approval → Commit
        ↓
Canonical Transaction/Setting + Audit + Explainable Report
\`\`\`
This diagram describes **target design**, not implemented end-to-end code.

### Registry/contracts per capability
Each module feature should have an immutable ID and version, tenant/business/site applicability, authorized roles/actions (effective permissions, not UI label), supported implementation handler, typed input/output schema, unit/currency/timezone/precision, source entity/record references, preconditions, downstream dependencies, state transitions, side effects, audit events, applicable report calculators, visual route, localized explanation metadata, demo scenarios and independent feature status. Reference existing D033 registry; do not build an unrelated competing control store.

### Business logic and computation standards
- Use decimal-safe monetary math, correct unit dimensions/conversion, explicit timezone (Bangladesh default Asia/Dhaka, business-configurable where valid), tax/discount order, effective-dated policy, immutable posted records, idempotency/retry, negative stock protection and permission-filtered data.
- Every calculation shows source values, formula version, inclusion/exclusion rules, timing, rounding and any missing/unverified source data; distinguish estimated figures from certified results.
- Reports must specify \`subject\`, \`measures\`, \`dimensions\`, \`filters\`, \`aggregation\`, \`join paths\`, \`period\`, \`grouping\`, \`formula/version\`, \`row-level authorization\`, \`drilldown\`, \`export\` and \`reconciliation\`. The reported number must match the same canonical events/records, never independent client-side bookkeeping.
- Dependencies and conflicts must be explained before enabling or disabling a control. A visual preference never grants permission; a typed rule never edits a posted transaction retroactively; a sample result never becomes an actual sale/expense/salary.

### Help, recommendations and demo UX policy (every supported module)
Implement a **Contextual Guidance Contract** for every significant action/control/calculation/report:
\`id, version, locale, title, purpose, inPlainLanguage, useWhen, requiredInputs, normalRecommendation, alternativeOrException, actionEffects, dependentFeatures, permissions, resultLocation, sampleWalkthrough, formulaTrace, dataSafety, relatedHelp, readinessStatus\`.

**Presentation:** small inline \`ⓘ\`/“এটা কী?”, “কেন?”, “উদাহরণ দেখুন”, “আগে ফলাফল দেখুন” and step-by-step assistance near the control itself. Short help first, optional expandable detailed guidance; a link to a full Help/Knowledge Center can supplement but **cannot replace** the local explanation. For risky writes, show before/after and require clear confirmation/authorized approval. Accessible on mobile and desktop (keyboard navigation, screen-reader labels, focus state); Bangla-first for relevant customers with English localization. The Owner can request an exception and see permitted alternatives; unsupported or unsafe paths are visibly blocked with what to do next, not simply disappearing.

**Recommendations must be grounded:** default "usual method" is a transparent, editable proposal rather than a universal correct answer. Explain assumptions, why that choice is normally suitable, and what changes when the Owner selects another validated option. Do not pretend AI-generated operational advice is binding legal/accounting guidance. Examples use realistic but synthetic values and cannot write to canonical business tables.

### Concrete cross-sector examples
1. **Sweet factory:** "Factory A may waste 3% of ingredients; branch B only 1%." Resolve recipe/BOM, material issue, batch yield, site inventory, wastage valuation, COGS, reports and role approval. Show how quantity/value changes and where the wastage report appears; if COGS is not built, show estimate/unavailable rather than claim final profit.
2. **Paint dealer:** "Purchase in cartons, stock in litres, sell by can, and reorder below a configurable threshold." Use exact units/conversions, inventory events, pricing and supplier context, low-stock notifications and product/site reports; explain impact and sample conversion.
3. **Construction contractor:** "Material sent to Project B requires approval over a threshold." Resolve project/site, requester/approver, stock transfer/issue, cost-to-project source and audit; do not treat approved material request as a posted expense unless the finance contract exists.
4. **Workforce/payroll:** "Sunday overtime paid differently at one branch." Resolve work calendar, shift, attendance, effective payroll rate, approval and payslip; explain formula and test frozen payroll protection.
5. **Owner report:** "Show daily margin, plus a 7-day trend, only for Site X." Explain sale revenue source, returned quantities, COGS basis, grouping, filters, currency, permission, trend chart, export, and limits if required source data absent.
6. **Exception request:** "Let one supervisor bypass a normal approval for a small amount." Only expose an explicitly authorized, bounded, audited exception if an existing effective grant and safety policy allow it. Never silently bypass invariant server checks.

### Implementation and QA plan (all packages, not only A048/A049/A050)
- **Blueprint foundation:** typed capability/dependency/guide registries tied to canonical modules, a read-only intent interpretation contract and conflict classifications. Reuse A045 where applicable.
- **Reusable UI/help layer:** localized metadata mapping on every new/reworked screen with consistent tooltips, recommendation/help/preview, input explanations and output trace. Build examples per feature in synthetic environment; mark unsupported paths.
- **Safe engine construction:** expand certified handlers one class at a time; domain owners implement secure backend and tests; permission/cost posting cannot be user-scripted.
- **Coverage/mapping:** maintain A–Z feature coverage matrix with status \`NOT_BUILT / DESCRIPTOR_ONLY / SOURCE_BUILT / ISOLATED_TESTED / REAL_AUTH_TESTED / DEPLOYED / OPERATIONALLY_CERTIFIED\`, required source, config, guidance, exception, demo, report and negative permission tests. Apply to each supported industry and module. Any missing capability becomes a tracked implementation task rather than a false completion.
- **Test matrix:** normal path and exceptions; two tenants, multiple businesses/sites, synthetic Owner/Staff and role revocation, incorrect input/units, stale version, replay, cross-tenant attempt, disabled handler, missing dependencies, conflicting rules, report mismatch, localization, keyboard/mobile/desktop; real GoTrue as a separate stage gate when available.
- **Changes and handoff:** One Book controls decisions, one A044/A045 control plane, one A018 stock ledger and A034 effective grants. Never change production SG, merge main, or rewrite legacy Islamia modules as part of documentation. Merge/rebase separate Draft PRs only after verified integration.

## Status as of this decision
Existing A045 Draft PR #42 certifies **one** advisory \`threshold_rule_v1\` handler and a Workshop first slice; remaining handler classes are not yet implemented. A048, A049, A050 first tested code slices are Draft PRs #49/#50/#51 and not universally integrated/released. A051 is Claude-assigned Issue #52. **D049/R128/A052 records Owner's mandatory system-wide architecture**, not a claim that the request compiler, all calculations or cross-module contextual demos have already been built. No real GoTrue staging or production deployment is claimed.

**References:** [Master Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit) · [GitHub Epic #53](https://github.com/mistybari99/CORE-10-CENTRAL/issues/53) · [Google Drive Companion Spec](https://docs.google.com/document/d/1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg/edit)
