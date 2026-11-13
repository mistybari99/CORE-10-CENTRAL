## CORE 10 CENTRAL · Implementation & release evidence

- **Owner Decision / Action ID:** 
- **Exact base, branch, SHA, files:** 
- **What really works vs synthetic-only:** 
- **Tests, CI links, 390px/1440px:** 
- **Tenant/scope/security & data-write impact:** 
- **Decision Book row / evidence:** 
- **Merge/deployment status (do not imply release):** 

### Mandatory language review — every UI/UX change

- [ ] Read `AGENTS.md` + `docs/ux/C10_LANGUAGE_CONTRACT.md` + `C10_BN_FIRST_GLOSSARY.md`.
- [ ] **Bengali** `bn-BD`: natural Bangla script with familiar loanwords স্টক/প্ল্যান/সেলস; not stiff dictionary translations.
- [ ] **Eng/Bng** `bn-BD-mixed`: natural Bengali grammar with Stock/Plan/Sales in Latin script.
- [ ] **English** `en`: fully idiomatic English.
- [ ] All new UI copy uses shared semantic translation keys in all 3 modes; no competing module translator, runtime AI, or hardcoded English-only labels.
- [ ] Check nav, forms, errors, helper text, reports, aria labels and empty states at 390px + 1440px; note remaining legacy translation gaps.
- [ ] Language switch never changes permission, business/tenant scope, stock/money, or real data.
- [ ] `node scripts/verify-language-contract.mjs` + relevant browser/unit checks pass, or explain **NOT RUN / FAIL**.
- [ ] Draft PR only until explicit Owner release approval; **no unverified deployment claim**.
