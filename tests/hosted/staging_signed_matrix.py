#!/usr/bin/env python3
"""B-018: signed-auth verification against the CORE10 STAGING Supabase project only.

Real GoTrue sessions for eight synthetic personas call the real PostgREST API of the staging
project. Nothing here touches the live business project or IMG-ERP-SG: the project reference is
pinned and any other value is refused. API keys are read from the Management API at run time and
never printed or stored; synthetic passwords live only in a 0600 state file in the home directory.

Usage: staging_signed_matrix.py rhrqhbyzrhaafynfhdaf [--report PATH]
Needs the Management API credential of the environment (injected by the network proxy).
Applies no migration. Creates only synthetic users and synthetic fixture rows (ids 98xx).
"""
import base64, hashlib, hmac, json, os, secrets, subprocess, sys, time, urllib.error, urllib.request

STAGING_REF = "rhrqhbyzrhaafynfhdaf"
if len(sys.argv) < 2 or sys.argv[1] != STAGING_REF:
    sys.exit("refusing: this harness runs only against the CORE10 staging project " + STAGING_REF)
REF, HOST = STAGING_REF, "https://%s.supabase.co" % STAGING_REF
STATE = os.path.expanduser(os.environ.get("CORE10_STAGING_STATE", "~/.core10-staging-personas.json"))
RUN = str(int(time.time()))
REPORT = sys.argv[sys.argv.index("--report") + 1] if "--report" in sys.argv else None
PERSONAS = ["owner_a", "biz_owner", "manager", "investor", "staff", "owner_b", "none", "expired"]
BIZ_A, BIZ_B, SITE_A1 = 9821, 9822, 9831


def http(method, url, headers=None, body=None):
    h = {"Content-Type": "application/json"}
    h.update(headers or {})
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw, st = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        raw, st = e.read().decode(), e.code
    try:
        return st, (json.loads(raw) if raw else None)
    except ValueError:
        return st, raw


def mgmt(method, path, body=None):
    return http(method, "https://api.supabase.com/v1/projects/%s/%s" % (REF, path), None, body)


def sql(q):
    st, js = mgmt("POST", "database/query", {"query": q})
    if st not in (200, 201):
        sys.exit("sql failed %s %s" % (st, str(js)[:300]))
    return js


st, keys = http("GET", "https://api.supabase.com/v1/projects/%s/api-keys?reveal=true" % REF)
if st != 200 or not isinstance(keys, list):
    sys.exit("cannot read project keys: %s" % st)
ANON = next((k["api_key"] for k in keys if k.get("name") == "anon"), None)
SVC = next((k["api_key"] for k in keys if k.get("name") == "service_role"), None)
if not ANON or not SVC:
    sys.exit("anon/service_role keys not found (names: %s)" % [k.get("name") for k in keys])
del keys

# 1. expose the core10 schema to the API of the staging project (configuration, not a migration)
st, pg = mgmt("GET", "postgrest")
schemas = [s.strip() for s in pg["db_schema"].split(",")]
if "core10" not in schemas:
    mgmt("PATCH", "postgrest", {"db_schema": ",".join(schemas + ["core10"])})
    sql("NOTIFY pgrst, 'reload schema'")
    time.sleep(8)

# 2. synthetic users
state = json.load(open(STATE)) if os.path.exists(STATE) else {}
H_SVC = {"apikey": SVC, "Authorization": "Bearer " + SVC}
for n in PERSONAS:
    email = "np-%s@core10-staging.test" % n.replace("_", "-")
    pw = state.get(n, {}).get("pw") or "Stg-" + secrets.token_urlsafe(14)
    st, js = http("POST", HOST + "/auth/v1/admin/users", H_SVC,
                  {"email": email, "password": pw, "email_confirm": True, "user_metadata": {"synthetic": True}})
    if st in (200, 201):
        uid = js["id"]
    else:
        st2, lst = http("GET", HOST + "/auth/v1/admin/users?per_page=200", H_SVC)
        uid = next(u["id"] for u in lst["users"] if u["email"] == email)
        http("PUT", HOST + "/auth/v1/admin/users/" + uid, H_SVC, {"password": pw, "email_confirm": True})
    state[n] = {"id": uid, "email": email, "pw": pw}
fd = os.open(STATE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(state, f)
del SVC
U = {n: state[n]["id"] for n in PERSONAS}

# 3. synthetic fixture rows (idempotent; ids 98xx)
sql("""
INSERT INTO core10.tenants(id,slug) VALUES (9801,'stg-a'),(9802,'stg-b') ON CONFLICT DO NOTHING;
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9811,9801,'Staging A'),(9812,9802,'Staging B') ON CONFLICT DO NOTHING;
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9821,9801,9811,'stg-sweets','sweets_bakery','stg-seed-a'),(9822,9802,9812,'stg-other','restaurant','stg-seed-b') ON CONFLICT DO NOTHING;
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (9831,9801,9821,'showroom','Showroom','stg-seed-s1'),(9832,9801,9821,'factory','Factory','stg-seed-s2'),
 (9833,9802,9822,'showroom','Other showroom','stg-seed-s3') ON CONFLICT DO NOTHING;
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES (9801,'%(owner_a)s','tenant_owner'),(9802,'%(owner_b)s','tenant_owner') ON CONFLICT DO NOTHING;
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (9801,9821,'%(biz_owner)s','business_owner'),(9801,9821,'%(manager)s','manager'),(9801,9821,'%(investor)s','investor') ON CONFLICT DO NOTHING;
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,valid_until)
 VALUES (9801,9821,'%(expired)s','business_owner',now()-interval '1 day') ON CONFLICT DO NOTHING;
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions)
 VALUES (9801,9821,9831,'%(staff)s',ARRAY['stock.read']) ON CONFLICT DO NOTHING;
""" % U)

RESULTS = []


def rec(tid, desc, ok, detail=""):
    RESULTS.append((tid, desc, bool(ok), str(detail)[:160]))


def login(n):
    st, js = http("POST", HOST + "/auth/v1/token?grant_type=password", {"apikey": ANON},
                  {"email": state[n]["email"], "password": state[n]["pw"]})
    if st != 200:
        sys.exit("sign-in failed for %s: %s" % (n, st))
    return js["access_token"]


def api(method, path, token=None, body=None, apikey=None, profile=True):
    h = {} if apikey is False else {"apikey": apikey or ANON}
    if profile:
        h.update({"Accept-Profile": "core10", "Content-Profile": "core10"})
    h["Authorization"] = "Bearer " + (token or ANON)
    if apikey is False:
        h.pop("Authorization")
    return http(method, HOST + "/rest/v1/" + path, h, body)


def rpc(fn, args, token):
    return api("POST", "rpc/" + fn, token, args)


def err(js):
    return js.get("message", "") if isinstance(js, dict) else ""


T = {n: login(n) for n in PERSONAS}


def ctx(n):
    st, js = rpc("build01_context_v1", {}, T[n])
    return st, js


def biz_ids(js):
    return sorted(b["id"] for b in js.get("businesses", [])) if isinstance(js, dict) else None


# A. transport and forgery ------------------------------------------------------------------------
st, js = http("POST", HOST + "/rest/v1/rpc/build01_context_v1", {"Accept-Profile": "core10", "Content-Profile": "core10"}, {})
rec("A1", "no API key at all is rejected", st == 401, st)
st, js = rpc("build01_context_v1", {}, None)
rec("A2", "anon key (no user session) cannot call the access context", st != 200, "%s %s" % (st, err(js)))
st, js = api("GET", "businesses?select=id", None)
rec("A3", "anon key cannot read business rows", st != 200 or js == [], st)
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
head, payload, sig = T["owner_a"].split(".")
body = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
body["sub"] = U["owner_b"]
forged = ".".join([head, b64(json.dumps(body).encode()).decode(), sig])
st, js = rpc("build01_context_v1", {}, forged)
rec("A4", "token with a swapped subject and the old signature is rejected", st in (401, 403), "%s %s" % (st, err(js)))
hdr = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
pl = b64(json.dumps({"sub": U["owner_a"], "role": "authenticated", "aud": "authenticated", "exp": int(time.time()) + 3600}).encode())
mac = b64(hmac.new(secrets.token_bytes(32), hdr + b"." + pl, hashlib.sha256).digest())
st, js = rpc("build01_context_v1", {}, (hdr + b"." + pl + b"." + mac).decode())
rec("A5", "token signed with a random secret is rejected", st in (401, 403), "%s %s" % (st, err(js)))
none_hdr = b64(json.dumps({"alg": "none", "typ": "JWT"}).encode())
st, js = rpc("build01_context_v1", {}, (none_hdr + b"." + pl + b".").decode())
rec("A6", "unsigned (alg none) token is rejected", st in (401, 403), "%s %s" % (st, err(js)))

# B. identity and scope ---------------------------------------------------------------------------
manager_ctx = ctx("manager")[1]
if BIZ_A not in (biz_ids(manager_ctx) or []):
    rpc("change_access_v1", {"p_business": BIZ_A, "p_subject": U["manager"], "p_command": "business_member.grant",
                             "p_role": "manager", "p_site": None, "p_actions": [], "p_request": "stg_%s_heal" % RUN}, T["owner_a"])
for n, want_ids, want_role in [("owner_a", [BIZ_A], "tenant_owner"), ("biz_owner", [BIZ_A], "business_owner"),
                               ("manager", [BIZ_A], "manager"), ("staff", [BIZ_A], "site_staff"),
                               ("owner_b", [BIZ_B], "tenant_owner"), ("investor", [], None), ("expired", [], None), ("none", [], None)]:
    st, js = ctx(n)
    roles = {b["id"]: b["role"] for b in js.get("businesses", [])} if isinstance(js, dict) else {}
    ok = st == 200 and biz_ids(js) == want_ids and (want_role is None or roles.get(want_ids[0]) == want_role)
    rec("B-" + n, "%s sees %s%s" % (n, want_ids or "no business", "" if not want_role else " as " + want_role), ok, "%s %s" % (st, roles))
st, js = ctx("manager")
rec("B-manager-nomanage", "manager cannot manage the business", st == 200 and not any(b["can_manage"] for b in js["businesses"]), "")
st, js = ctx("staff")
rec("B-staff-sites", "site-granted staff sees only its showroom with stock.read",
    st == 200 and [s["id"] for s in js["sites"]] == [SITE_A1] and js["sites"][0]["allowed_actions"] == ["stock.read"], js.get("sites"))
st, js = ctx("owner_a")
rec("B-mode", "context states synthetic mode and not production-certified", js.get("data_mode") == "disposable-demo" and js.get("production_certified") is False, "")

# C. direct table access is closed to API users ----------------------------------------------------
for n, want in [("owner_a", [BIZ_A]), ("owner_b", [BIZ_B]), ("none", [])]:
    st, js = api("GET", "businesses?select=id&order=id", T[n])
    got = sorted(r["id"] for r in js) if st == 200 and isinstance(js, list) else None
    rec("C-read-" + n, "%s reads only own business rows" % n, got == want or (st != 200), "%s %s" % (st, got))
st, js = api("POST", "businesses", T["owner_a"], {"id": 9999, "tenant_id": 9801, "slug": "x", "template_code": "sweets_bakery", "request_key": "x"})
rec("C-write", "owner cannot insert a business row directly", st not in (200, 201, 204), "%s %s" % (st, err(js)))
st, js = api("DELETE", "business_members?user_id=eq." + U["manager"], T["owner_a"])
rec("C-delete", "owner cannot delete memberships directly", st not in (200, 204), "%s %s" % (st, err(js)))
st, js = api("GET", "canonical_audit_events_v1?select=id", T["manager"])
rec("C-audit", "manager cannot read the audit journal", st != 200 or js == [], "%s" % st)

# D. approval workflow, maker-checker, tenant isolation, audit -------------------------------------
st, js = rpc("publish_approval_policy_v1", {"p_business": BIZ_A, "p_domain": "inventory", "p_action": "adjust",
                                            "p_ttl_minutes": 60, "p_key": "stg_%s_policy" % RUN}, T["owner_a"])
rec("D1", "owner publishes an approval policy", st == 200, "%s %s" % (st, err(js)))
sub = {"p_business": BIZ_A, "p_domain": "inventory", "p_action": "adjust", "p_source_key": "stg-%s" % RUN,
       "p_source_version": 1, "p_payload": {"quantity_milli": "3000"}, "p_key": "stg_%s_submit" % RUN}
st, req = rpc("submit_typed_approval_v1", sub, T["manager"])
rec("D2", "manager submits an approval request", st == 200 and isinstance(req, int), "%s %s" % (st, err(req) if isinstance(req, dict) else req))
st2, req2 = rpc("submit_typed_approval_v1", sub, T["manager"])
rec("D3", "same request replayed returns the same request", st2 == 200 and req2 == req, "%s %s" % (st2, req2))
st, js = rpc("submit_typed_approval_v1", dict(sub, p_payload={"quantity_milli": "4000"}), T["manager"])
rec("D4", "same key with another payload is refused", st != 200 and "replay_conflict" in err(js), "%s %s" % (st, err(js)))
for tid, n, desc in [("D5", "manager", "maker cannot approve own request"), ("D6", "owner_b", "foreign tenant owner cannot approve"),
                     ("D7", "investor", "investor cannot approve"), ("D8", "staff", "site staff cannot approve"),
                     ("D9", "expired", "expired business owner cannot approve")]:
    st, js = rpc("decide_approval", {"p_request": req, "p_action": "approve", "p_key": "stg_%s_%s" % (RUN, n)}, T[n])
    rec(tid, desc, st != 200, "%s %s" % (st, err(js)))
st, js = rpc("submit_typed_approval_v1", dict(sub, p_source_key="stg-%s-staff" % RUN, p_key="stg_%s_staffsub" % RUN), T["staff"])
rec("D10", "site staff cannot submit an approval request", st != 200, "%s %s" % (st, err(js)))
st, rc = rpc("decide_approval", {"p_request": req, "p_action": "approve", "p_key": "stg_%s_owner" % RUN}, T["owner_a"])
rec("D11", "owner approves", st == 200, "%s %s" % (st, err(rc) if isinstance(rc, dict) else rc))
st, rc2 = rpc("decide_approval", {"p_request": req, "p_action": "approve", "p_key": "stg_%s_owner" % RUN}, T["owner_a"])
rec("D12", "approval replay returns the same receipt", st == 200 and rc2 == rc, "%s" % st)
st, js = rpc("my_approval_status_v1", {"p_business": BIZ_A, "p_limit": 50}, T["owner_a"])
rec("D13", "owner sees the request as approved", st == 200 and "approved" in json.dumps(js), "%s" % st)
st, js = rpc("verify_canonical_audit_v1", {"p_business": BIZ_A}, T["owner_a"])
rec("D14", "audit hash chain verifies for the owner", st == 200 and isinstance(js, dict) and js.get("ok") is True, "%s %s" % (st, js))
st, js = rpc("verify_canonical_audit_v1", {"p_business": BIZ_A}, T["owner_b"])
rec("D15", "foreign tenant owner cannot verify or read tenant A audit", st != 200 or (isinstance(js, dict) and js.get("ok") is not True), "%s %s" % (st, err(js)))

# E. revocation is immediate, role changes are guarded ----------------------------------------------
rev = {"p_business": BIZ_A, "p_subject": U["manager"], "p_command": "business_member.revoke", "p_role": None,
       "p_site": None, "p_actions": [], "p_request": "stg_%s_revoke" % RUN}
st, js = rpc("change_access_v1", rev, T["owner_a"])
rec("E1", "owner revokes the manager", st == 200, "%s %s" % (st, err(js)))
st, js = ctx("manager")
rec("E2", "the manager's still-valid token loses access at once", st == 200 and biz_ids(js) == [], "%s %s" % (st, biz_ids(js)))
st, js = rpc("submit_typed_approval_v1", dict(sub, p_source_key="stg-%s-after" % RUN, p_key="stg_%s_after" % RUN), T["manager"])
rec("E3", "the revoked manager cannot submit", st != 200, "%s %s" % (st, err(js)))
st, js = rpc("change_access_v1", dict(rev, p_command="business_member.grant", p_role="manager", p_request="stg_%s_regrant" % RUN), T["owner_a"])
rec("E4", "owner restores the manager", st == 200, "%s %s" % (st, err(js)))
st, js = ctx("manager")
rec("E5", "the restored manager sees the business again", st == 200 and biz_ids(js) == [BIZ_A], "%s" % biz_ids(js))
st, js = rpc("change_access_v1", dict(rev, p_subject=U["owner_a"], p_request="stg_%s_self" % RUN), T["owner_a"])
rec("E6", "an owner cannot change their own access", st != 200, "%s %s" % (st, err(js)))
for tid, n in [("E7", "manager"), ("E8", "expired"), ("E9", "owner_b"), ("E10", "none")]:
    st, js = rpc("change_access_v1", dict(rev, p_request="stg_%s_%s_try" % (RUN, n)), T[n])
    rec(tid, "%s cannot change access of tenant A" % n, st != 200, "%s %s" % (st, err(js)))

# report -------------------------------------------------------------------------------------------
n_ok = sum(1 for r in RESULTS if r[2])
mig = sql("select count(*) c, max(version) m from core10.schema_migrations")[0]
sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
lines = ["# B-018 hosted signed-auth verification (staging only)", "",
         "Project `%s` (CORE10 staging, synthetic data). Trunk `%s`. Run `%s`. Migrations applied on staging: %s (max version %s)."
         % (REF, sha, RUN, mig["c"], mig["m"]), "",
         "Real GoTrue sessions of 8 synthetic personas against the real PostgREST API. No migration applied by this run.",
         "", "**Result: %d of %d checks passed.**" % (n_ok, len(RESULTS)), "",
         "| ID | Check | Result | Evidence |", "| --- | --- | --- | --- |"]
lines += ["| %s | %s | %s | %s |" % (t, d, "PASS" if ok else "**FAIL**", e.replace("|", "/")) for t, d, ok, e in RESULTS]
out = "\n".join(lines)
print(out)
if REPORT:
    open(REPORT, "w").write(out + "\n")
sys.exit(0 if n_ok == len(RESULTS) else 1)
