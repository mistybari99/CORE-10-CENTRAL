# B-018 hosted signed-auth verification (staging only)

Project `rhrqhbyzrhaafynfhdaf` (CORE10 staging, synthetic data). Trunk `c2cc661`. Run `1794844697`. Migrations applied on staging: 12 (max version 12).

Real GoTrue sessions of 8 synthetic personas against the real PostgREST API. No migration applied by this run.

**Result: 48 of 48 checks passed.**

| ID | Check | Result | Evidence |
| --- | --- | --- | --- |
| A1 | no API key at all is rejected | PASS | 401 |
| A2 | anon key (no user session) cannot call the access context | PASS | 401 permission denied for schema core10 |
| A3 | anon key cannot read business rows | PASS | 401 |
| A4 | token with a swapped subject and the old signature is rejected | PASS | 401 No suitable key or wrong key type |
| A5 | token signed with a random secret is rejected | PASS | 401 No suitable key or wrong key type |
| A6 | unsigned (alg none) token is rejected | PASS | 401 Wrong or unsupported encoding algorithm |
| B-owner_a | owner_a sees [9821] as tenant_owner | PASS | 200 {9821: 'tenant_owner'} |
| B-biz_owner | biz_owner sees [9821] as business_owner | PASS | 200 {9821: 'business_owner'} |
| B-manager | manager sees [9821] as manager | PASS | 200 {9821: 'manager'} |
| B-staff | staff sees [9821] as site_staff | PASS | 200 {9821: 'site_staff'} |
| B-owner_b | owner_b sees [9822] as tenant_owner | PASS | 200 {9822: 'tenant_owner'} |
| B-investor | investor sees no business | PASS | 200 {} |
| B-expired | expired sees no business | PASS | 200 {} |
| B-none | none sees no business | PASS | 200 {} |
| B-manager-nomanage | manager cannot manage the business | PASS |  |
| B-staff-sites | site-granted staff sees only its showroom with stock.read | PASS | [{'id': 9831, 'kind': 'showroom', 'label': 'Showroom', 'tenant_id': 9801, 'business_id': 9821, 'allowed_actions': ['stock.read']}] |
| B-mode | context states synthetic mode and not production-certified | PASS |  |
| C-read-owner_a | owner_a reads only own business rows | PASS | 200 [9821] |
| C-read-owner_b | owner_b reads only own business rows | PASS | 200 [9822] |
| C-read-none | none reads only own business rows | PASS | 200 [] |
| C-write | owner cannot insert a business row directly | PASS | 403 permission denied for table businesses |
| C-delete | owner cannot delete memberships directly | PASS | 403 permission denied for table business_members |
| C-audit | manager cannot read the audit journal | PASS | 200 |
| D1 | owner publishes an approval policy | PASS | 200  |
| D2 | manager submits an approval request | PASS | 200 1 |
| D3 | same request replayed returns the same request | PASS | 200 1 |
| D4 | same key with another payload is refused | PASS | 400 approval_submit_replay_conflict |
| D5 | maker cannot approve own request | PASS | 400 approval_not_authorized |
| D6 | foreign tenant owner cannot approve | PASS | 400 approval_not_authorized |
| D7 | investor cannot approve | PASS | 400 approval_not_authorized |
| D8 | site staff cannot approve | PASS | 400 approval_not_authorized |
| D9 | expired business owner cannot approve | PASS | 400 approval_not_authorized |
| D10 | site staff cannot submit an approval request | PASS | 400 approval_submit_denied |
| D11 | owner approves | PASS | 200 1 |
| D12 | approval replay returns the same receipt | PASS | 200 |
| D13 | owner sees the request as approved | PASS | 200 |
| D14 | audit hash chain verifies for the owner | PASS | 200 {'ok': True, 'reason': None, 'checked': 1} |
| D15 | foreign tenant owner cannot verify or read tenant A audit | PASS | 400 canonical_audit_read_denied |
| E1 | owner revokes the manager | PASS | 200  |
| E2 | the manager's still-valid token loses access at once | PASS | 200 [] |
| E3 | the revoked manager cannot submit | PASS | 400 approval_submit_denied |
| E4 | owner restores the manager | PASS | 200  |
| E5 | the restored manager sees the business again | PASS | [9821] |
| E6 | an owner cannot change their own access | PASS | 400 self_access_change_forbidden |
| E7 | manager cannot change access of tenant A | PASS | 400 access_change_not_authorized |
| E8 | expired cannot change access of tenant A | PASS | 400 access_change_not_authorized |
| E9 | owner_b cannot change access of tenant A | PASS | 400 access_change_not_authorized |
| E10 | none cannot change access of tenant A | PASS | 400 access_change_not_authorized |
