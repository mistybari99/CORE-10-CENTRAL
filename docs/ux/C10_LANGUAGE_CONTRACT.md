# CORE 10 CENTRAL — Permanent three-mode language contract

**Policy:** Owner directive, 2026-11-13 · **Applies to:** every present and future ERP UI module, independently built business app, report screen, onboarding, modal, toast, form, settings page, mobile/PWA/desktop surface and extension under **the same** CORE-10-CENTRAL.
**Owner Decision Book:** https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit (C10-A064, change log C087). This file is an engineering implementation guide, **not a competing Owner decision register**.

## The selector is exactly

| Display | Locale ID | Familiar everyday text example | Principle |
| --- | --- | --- | --- |
| **Bengali** (default) | `bn-BD` | **স্টকের হিসাব মিলিয়ে নিন।** **নতুন প্ল্যান তৈরি করুন।** | Natural Bangladesh Bengali sentences, in Bangla script. Common loanwords in Bangla script: **স্টক, প্ল্যান, সেলস, রিপোর্ট, সেটিংস, ড্যাশবোর্ড** |
| **Eng/Bng** | `bn-BD-mixed` | **Stock-এর হিসাব মিলিয়ে নিন।** **নতুন Plan তৈরি করুন।** | Bengali sentence structure + genuinely familiar Latin-script English business words: **Stock, Plan, Sales, Report, Settings, Dashboard** |
| **English** | `en` | **Reconcile stock. Create a new plan.** | Plain, idiomatic English; not word-for-word Bengali |

The **Bengali** option is not “formal dictionary Bengali”. Avoid forcing **মজুদ**, **কার্যপরিকল্পনা**, **সমন্বিত তথ্যফলক** instead of familiar **স্টক**, **প্ল্যান**, **ড্যাশবোর্ড** in everyday UI. However, use a clear simple Bangla meaning for a truly unfamiliar technical concept, with short contextual guidance on first use (for example, **অ্যাপ্রুভাল (অনুমোদনের ধাপ)**). Avoid awkward grammar, excess English, mandatory transliterations, or invented jargon.

**Copy examples:** Bengali: “আজকের সেলস দেখুন”, “স্টকের হিসাব মিলিয়ে নিন”, “রিপোর্ট দেখুন”, “প্ল্যান বদলান”; Eng/Bng: “আজকের Sales দেখুন”, “Stock-এর হিসাব মিলিয়ে নিন”, “Report দেখুন”, “Plan বদলান”; English: “View today's sales”, “Reconcile stock”, “View reports”, “Edit the plan”.

## Obligations for future agents, screens and PRs

1. **Discover first:** read root `AGENTS.md`, this contract, `C10_BN_FIRST_GLOSSARY.md`, current shared implementation, and latest Owner Decision Book before building UI. Other agents and fresh chats should not make the Owner restate this preference.
2. **One semantic-key contract:** add each new UI string to the approved shared translation catalogue with all **three independently reviewed user-facing versions**. Do not implement a private translator per business/module. Example: `stock.reconcile` → Bengali “স্টকের হিসাব মিলিয়ে নিন”, Eng/Bng “Stock-এর হিসাব মিলিয়ে নিন”, English “Reconcile stock”.
3. **Register entire experience:** navigation and buttons, action feedback, errors, filters, form labels and placeholders, tooltips/help, printable UI/report titles, empty/loading states and accessible `aria-label` text. Technical database keys, SKU codes, policies, formulas, company names and aliases are **never translated**.
4. **Language changes presentation only:** NEVER change authorization, tenant scope, identity, calculations, units, real data, audit, sales or stock state as a side effect. Keep each business theme and visibility rights intact. No server/network/AI translation at runtime.
5. **Default & persistence:** Current *Preview* defaults Bengali on fresh page; its selection is local to the page and refresh resets it. Any new cross-page/role/tenant persisted-language preference requires a separately approved, scoped design. Do not invent a persistence policy.
6. **Test three modes:** verify copy, action messages, screen-reader labels, 390px Android and 1440px desktop layouts, overflow, user interactions, and no unexpected network/data changes. For more complex pages include a locale-switch test for changed data grids and reports.
7. **Treat source truth correctly:** `preview/i18n.mjs` is the currently coded three-mode preview adapter in isolated **Draft PR #103**. Its exact-text legacy bridge is temporary and can leave unmatched copy in English. Do not say all existing modules have passed localization; move legacy strings to named keys during scoped integration.
8. **CI guard:** `scripts/verify-language-contract.mjs` validates the three required modes and, on future PRs, requires newly introduced HTML/component frontend files to reference an i18n mechanism. It cannot prove fluent copy or guarantee every old screen is translated; reviewers must verify language quality and coverage explicitly.
9. **Release truth:** the Owner's existing independent merge/production rules remain. A Draft PR, passing CI, or documentation is **not** an approved main merge, signed production build or public deployment.

## Engineering acceptance examples

```js
// Concept only: implement in the shared language catalogue, not as a new independent service.
const stockReconcile = {
  "bn-BD": "স্টকের হিসাব মিলিয়ে নিন",
  "bn-BD-mixed": "Stock-এর হিসাব মিলিয়ে নিন",
  "en": "Reconcile stock"
};
```

**Before closing any future UI task:** the implementation report must include its catalog keys, which of the three modes were tested (PASS/FAIL/NOT RUN), mobile/desktop checks, remaining untranslated copy and exact PR/SHA. Any feature lacking required language coverage stays Draft / NOT COMPLETE until fixed or explicitly exception-approved by the Owner.
