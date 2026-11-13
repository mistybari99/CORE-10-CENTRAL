# CORE 10 CENTRAL — Bangla-first language & UX writing guide

**Action:** C10-A064 · **Scope:** existing integrated Preview Worker and Build01/Build02A walkthrough · **Languages:** `bn-BD` Bengali (default), `bn-BD-mixed` Eng/Bng, `en` English · **Status:** Draft PR implementation; not a release approval.

## How we write

Use short, natural, conversational Bangla. Bengali uses the **Bangla script even for natural English loanwords**, for example **স্টক, প্ল্যান, সেলস, রিপোর্ট**. Eng/Bng uses the **same flowing Bengali grammar with familiar Latin-script business words**, for example **Stock, Plan, Sales, Report**. English is a natural all-English rewrite. Do not use stiff Bengali alternatives like মজুদ or পরিকল্পনা merely to sound more translated. Keep everyday business words familiar. Do **not** translate technical identifiers, permission codes, tenant/site IDs, API names, SQL objects, demo aliases or report identifiers internally.

| Idea | Preferred Bangla UI | English UI | Avoid in ordinary UI |
| --- | --- | --- | --- |
| Plan / next action | কাজের প্ল্যান / পরের ধাপ | Plan / Next step | কার্যপরিকল্পনা, পরবর্তী কার্যক্রম |
| Dashboard / overview | এক নজরে / Dashboard | Overview / Dashboard | সমন্বিত তথ্যফলক |
| Report | রিপোর্ট | Report | প্রতিবেদন-উৎপাদন ব্যবস্থাপনা |
| Stock / inventory | স্টক | Stock / Inventory | পণ্য-মজুদ ব্যবস্থাপনা-সংক্রান্ত দীর্ঘ অনুবাদ |
| Approval | অ্যাপ্রুভাল (অনুমোদনের ধাপ), পরে অ্যাপ্রুভাল | Approval | অনুমোদন-প্রক্রিয়াকরণ ব্যবস্থা |
| Sales | সেলস / বিক্রি | Sales | বিক্রয়-কার্যক্রম পরিচালনা |
| Settings | সেটিংস | Settings | বিন্যাস-সমন্বয় ব্যবস্থা |
| Factory / branch | ফ্যাক্টরি / শাখা | Factory / Branch | উৎপাদন-উপকেন্দ্র |
| Demo | ডেমো / শুধু দেখার জন্য | Demo | পরীক্ষামূলক মডেল-অনুমিত |
| Read-only | শুধু দেখা যাবে; ডাটা বদলাবে না | Read-only; no write | পঠনমাত্র (without explanation) |

Every first-use specialist term needs a **brief meaning in context**—e.g., “অ্যাপ্রুভাল (অনুমোদনের ধাপ)” for Bengali and “Approval (অনুমোদনের ধাপ)” for Eng/Bng—then use the common term on later screens. For a blocked action, say *what cannot happen* and *what is needed next*, not just `ERROR`. Keep hard boundaries visible: synthetic demo is not real login, real stock, payment or production access.

## Three-option selector contract

| UI option | Locale | Stock copy | Plan copy | English loanword policy |
| --- | --- | --- | --- | --- |
| Bengali | `bn-BD` (default) | স্টকের হিসাব মিলিয়ে নিন | নতুন প্ল্যান তৈরি করুন | Natural Bangladesh Bengali; common loanwords in **Bangla script** |
| Eng/Bng | `bn-BD-mixed` | Stock-এর হিসাব মিলিয়ে নিন | নতুন Plan তৈরি করুন | Bengali grammar plus familiar **Latin-script English** business words |
| English | `en` | Reconcile stock | Create a new plan | Fully idiomatic English |

Codes, product brands, SHA, API identifiers and person aliases remain verbatim in every mode. Only user-facing copy changes. The two preview surfaces share one local i18n catalog. `lang` is `bn-BD` in both Bengali-based modes and `en` in English mode. Refresh resets to Bengali as before. Some legacy inline copy and upstream snapshots still need semantic-key cleanup; this PR does not claim full ERP translation.

The ERP-wide mandatory rule for every new future module is in [C10_LANGUAGE_CONTRACT.md](./C10_LANGUAGE_CONTRACT.md); all agents must read it before designing new user-facing UI. This Preview file is not a claim that the whole ERP is localized.

## Shared implementation contract

- One catalog: `preview/i18n.mjs` exports `PHRASES`, `NAMED_MESSAGES`, `CATALOG`, `NAMED_CATALOG`, `DEFAULT_LOCALE`, `SUPPORTED_LOCALES`, `createI18n`, `BROWSER_I18N_JS`.
- New UI modules **must** use a semantic named key (e.g., `C10I18N.t("common.approval")` or `<span data-i18n="common.language"></span>`), not hardcode visible copy or generate runtime AI translation.
- The existing static preview has a documented *legacy exact-text bridge* from reviewed `PHRASES` so the existing stable HTML/JS can be localized without duplicating backend engines. Migrate its legacy strings to namespaced keys on later scoped cleanup. Unmatched strings remain unchanged, **not automatically guessed**.
- Both local Preview pages load `/preview-i18n.js` from the **same origin**, served directly by the existing Worker; no external dictionary, token, cookies, API calls, network translation, storage or database writes.
- Language is **page-local**: `bn-BD` every fresh load. Choosing Eng/Bng or English updates DOM text and `document.documentElement.lang` only. No `localStorage`, `sessionStorage`, requests or cross-tab synchronization. Refresh resets to Bangla.
- Codes such as `approval.submit`, `T1`, `MANAGER_A`, `c10_*` and SHA evidence are never translated; only explanatory human copy and UI labels are localized.
- UI text is separate from access logic. Language must never influence tenant selection, permissions, stock, payroll, monetary results or authorization checks.

## UI test contract / safety

Unit tests prove canonical default, three-mode switching, finite key coverage, prohibited literal wording guard, static CSP `connect-src 'none'`, read-only HTTP semantics and absence of translation fetch/storage. Local Playwright checks at 390px and 1440px prove labels, toggle, no overflow, stock +5 in-memory demo and Build01/02A synthetic resolver with **no external requests**.

The public Preview URL is only considered updated after a separate verified deployment; a Draft PR by itself does **not** update Cloudflare.

## Remaining coverage outside C10-A064

The original A045 workshop, CRM and inventory/operations regression snapshot assets are pinned upstream separately. Their full screen copy, original Islamia ERP, signed backend applications and any future non-Preview modules are not localized by this first Preview slice. They must adopt the shared reviewed-key contract during their own scoped integration, without modifying Claude-owned branches or original business data.
