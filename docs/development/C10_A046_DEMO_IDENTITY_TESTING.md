# C10-A046 — Temporary Demo Identity & Permission Testing Program

**Owner directive 2026-11-11:** Until the ERP build approaches verified completion, use reusable TEST-ONLY Owner, Manager, Staff, Investor, Reviewer, Partner, Revoked, Unassigned and independent-Tenant identities to run permission checks without requiring real Owner/staff accounts or passwords. Remove disposable stage users and data before actual onboarding. This authorizes testing, NOT writes to the live Supabase project or existing real staff identities.

**Authoritative roster:** `internal/demo-identity-program/demo-identity-manifest-v1.json` contains 16 deterministic, inert UUIDs. It is **NOT** an Auth service, email/password directory, login screen or actual signed GoTrue identity. The independent database contains 2 synthetic tenants, 3 synthetic businesses and 4 sites. Existing A018 demo IDs are preserved.

**Run list:** `node internal/demo-identity-program/index.js list`.
**Run offline checks:** `node tests/c10_a046_demo_matrix.test.js`.
**Run SQL (only a disposable PG17 database named core10_a046_ci/core10_a046_local with A018 installed and seeded):**

```sh
psql -X -v ON_ERROR_STOP=1 -f internal/enterprise-sql/c10_a018_demo_backend.sql
psql -X -v ON_ERROR_STOP=1 -f tests/c10_a018_demo_seed.sql
psql -X -v ON_ERROR_STOP=1 -v c10_demo_ack=I_CONFIRM_DISPOSABLE_A046 -f internal/enterprise-sql/c10_a046_demo_personas_v1.sql
node internal/demo-identity-program/index.js sql > /tmp/c10-a046-matrix.sql
psql -X -v ON_ERROR_STOP=1 -f /tmp/c10-a046-matrix.sql
```

Set up disposable `authenticated` and `anon` database roles before A018; GitHub Actions does this. The seed refuses an Auth users table, non-fixture database name, unexpected tenants, businesses or existing stock transactions. It only adds two business memberships and two scoped staff grants, retaining old fixture records.

## Role coverage (use the stable keys for future tests)

| Persona | Intended scenario |
|---|---|
| TENANT_OWNER_A | Master/tenant owner, both authorized businesses in tenant A |
| BUSINESS_OWNER_A / BUSINESS_OWNER_B | Different local owners under same tenant |
| MANAGER_A / MANAGER_BUSINESS_B | Distinct business managers |
| COUNTER_STAFF_A | Showroom read/post fixture |
| FACTORY_STAFF_A | Factory read-only, negative post |
| BRANCH_STAFF_B | Separate business read-only, negative post |
| TENANT_OWNER_B / INDEPENDENT_STAFF_B | Independent tenant cross-leak negatives |
| INVESTOR_A / PARTNER_NO_GRANT | Financial relationship does not create ERP operational grant |
| REVOKED_MANAGER_A | Inactive member must see nothing |
| PLATFORM_OPERATOR | Software vendor may not read tenant data by default |
| REVIEWER_NOT_ASSIGNED / UNASSIGNED_USER | Role labels without server grant cannot access business |
| ANONYMOUS | No login/no c10_demo schema privileges |

### Important security gap surfaced, not hidden

The historical A018 `can_site` implementation grants managers every site action through `can_business`, including `stock.post` without a per-site `stock.post` grant. A046 models **observed legacy behavior**, not a claim that it is acceptable for production. A034 integration must close this permission inheritance gap and adjust expected tests. No bypassing A021/A034 by a UI role dropdown.

### Real signed staging later (no personal IDs needed)

Real authenticated testing needs an **isolated non-production Supabase staging project** with stage-only GoTrue test accounts, generated unique emails and securely stored passwords, explicit User IDs verified by `/auth/v1/user`, reviewed bindings to the fixture roles, and real PostgREST/RPC/RLS negative checks. The UUIDs in this registry are NOT assigned to those GoTrue users. Never copy service_role/secret keys to clients or repo; do not run the SQL against IMG-ERP-SG. Until real staging verification the verdict remains **SYNTHETIC_PG_ONLY**, not `REAL_GOTRUE_STAGE_PASS`.

### Cleanup contract before live business use

Disable/disconnect demo logins; destroy the disposable test database/project and stage-only Auth users, validate no demo membership remains in any operational tenant, then onboard real users with independent authorization. Never run broad deletes against existing Islamia stock, accounts, historical records or staff tables. Source files and CI may stay in git for future regression testing. Real data unaffected by this development branch.

**Parallel scope:** Claude owns C10-A045 micro-engine branch. ChatGPT owns ONLY C10-A046 fixtures and its CI. No changes in A045 code, legacy UI or A034 grants.
