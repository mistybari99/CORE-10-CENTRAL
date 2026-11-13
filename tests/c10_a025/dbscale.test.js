"use strict";
/* DB-level scale: 320 sites + 10,000 scenarios in ONE tenant, RLS on. MEASURED inside PostgreSQL (clock_timestamp), no process spawn in the numbers. */
const assert = require("node:assert/strict"); const fs = require("fs"), path = require("path"); const H = require("./pg_harness");
(async () => {
  H.ensureServer(); try {
    H.setup(); const S = 320, N = 10000, ok = r => assert.ok(r.ok, r.err);
    ok(H.psql("insert into c10_sim_fixture.sites select 'S-SCALE-' || g, 'B-A1' from generate_series(1," + S + ") g;"));
    ok(H.psql("insert into c10_sim_fixture.grants select 'u_site_' || g, 'T-ALPHA', 'B-A1', 'S-SCALE-' || g, c, false from generate_series(1,20) g, (values ('sim.read'),('sim.run')) v(c);"));
    const t0 = Date.now(); ok(H.psql("insert into c10_sim.scenario_drafts(tenant_id, business_id, site_id, owner_user, name, kind, request_key, model_id, model_version, inputs) select 'T-ALPHA','B-A1','S-SCALE-' || (1 + (g % " + S + ")), 'u_seed', 'scale ' || g, 'baseline', 'scale-' || g, 'M01', '2.0.0', '{}' from generate_series(1," + N + ") g;")); const seedMs = Date.now() - t0;
    const time = (role, user, sql) => { const r = H.as(user, "do $$ declare t0 timestamptz := clock_timestamp(); n bigint; begin " + sql + " raise notice 'MS=%', round(extract(epoch from (clock_timestamp() - t0)) * 1000); end $$;", role); assert.ok(r.ok, r.err); const m = /MS=(\d+)/.exec(r.err + r.out); return m ? Number(m[1]) : NaN; };
    const owner = time("sim_authenticated", "u_owner_a", "select count(*) into n from c10_sim.scenario_drafts; assert n = " + N + ", 'owner sees all ' || n;");
    const site = time("sim_authenticated", "u_site_7", "select count(*) into n from c10_sim.scenario_drafts; assert n = " + (N / S | 0) + " or n = " + ((N / S | 0) + 1) + ", 'site user sees only its site ' || n;");
    const foreign = time("sim_authenticated", "u_owner_b", "select count(*) into n from c10_sim.scenario_drafts; assert n = 0, 'foreign tenant sees ' || n;");
    const listing = time("sim_authenticated", "u_owner_a", "perform id, name, status from c10_sim.scenario_drafts where business_id = 'B-A1' order by created_at desc limit 50;");
    const res = { sites: S, scenarios: N, seed_insert_ms: seedMs, owner_count_all_rows_ms: owner, site_scoped_count_ms: site, foreign_tenant_count_ms: foreign, list_first_50_ms: listing, server: H.psql("show server_version;").out, note: "RLS enforced via c10_sim.can_see per row; times measured inside PostgreSQL on a throwaway cluster" };
    fs.writeFileSync(path.join(__dirname, "db-scale-result.json"), JSON.stringify(res, null, 1));
    assert.ok(owner < 60000 && site < 60000, "RLS count over 10k rows exceeded generous 60 s ceiling: " + JSON.stringify(res));
    console.log("PASS dbscale (MEASURED in PostgreSQL " + res.server.split(" ")[0] + "): " + JSON.stringify({ sites: S, scenarios: N, owner_all_rows_ms: owner, site_scoped_ms: site, foreign_ms: foreign, list50_ms: listing }));
  } finally { H.stopServer(); }
})().catch(e => { console.error(e); try { H.stopServer(); } catch (_) {} process.exit(1); });
