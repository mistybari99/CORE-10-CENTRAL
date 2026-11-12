# GOV-003 local demo (DEMO / NOT LIVE)

A real local web UI over a real local PostgreSQL database. Every button calls the local JSON API, which calls the GOV-003
SQL functions. Nothing is mocked in the browser, and nothing here is production. Data is synthetic.

## Run it (no npm, no install, no third-party code)

Requirements: Node 22 and a local PostgreSQL (16 or newer) reachable with trust auth, for example the repo's usual
`127.0.0.1:55432` with user `postgres`.

```
G3_DEMO=1 node internal/gov003/server/demo-server.mjs
```

Then open http://127.0.0.1:8787/ . The terminal prints `DEMO / NOT LIVE — synthetic data`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `G3_DEMO` | unset | Must be `1`, otherwise the server refuses to start (and any API process without it answers 401). |
| `G3_DEMO_PORT` | `8787` | Port, bound to 127.0.0.1 only. |
| `G3_DEMO_DB` | `g3_demo` | Only `g3_demo` or `g3_demo_test` are accepted. The database is dropped and rebuilt on every start. |
| `PGHOST` `PGPORT` `PGUSER` | `127.0.0.1` `55432` `postgres` | Where PostgreSQL is. |

Run the tests (they use their own database `g3_demo_test`, started in-process, real HTTP):

```
node --test "tests/gov003/demo/*.test.mjs"
node tests/gov003/static-checks.mjs
```

Deep links: `/?lang=en&view=audit&as=business_owner_b1`. Views: audit, signals, incidents, readiness, export, errors, grants.

## What you can try

1. Story A, journal: as `business_owner_b1` append an event, replay the same key (same receipt, no second effect), change the
   payload (409), verify the hash chain, filter and see the filtered count, create an export and check its SHA-256, then
   verify exact bytes (ok) and altered bytes (rejected). Switch to `staff_s1`, `investor_b1`, `revoked_b1` or
   `tenant_owner_t2`: the database answers one generic "access denied" and no foreign counts.
2. Story B, signals: run detection, see advisory signals that link to the original evidence, dismiss one as an independent
   reviewer; a second reviewer is refused. Detection and review change no stock, money, approval or role.
3. Story C, readiness: the feature is "not certified", "stale CI" (green on an old commit), "staging missing",
   "deployment unverified". Simulated green stays "simulation only". Incidents: a purge attempt on held evidence is refused
   and receipted.
4. Safe errors and grant review: a synthetic error full of fake secrets is stored only as a scrubbed projection. The grant
   diff reports an intentionally planted drift and never changes a permission.

## Honest limits

- Identities are fixture labels chosen in the UI (`X-Demo-Identity`), accepted only when `G3_DEMO=1`. They are NOT signed
  GoTrue sessions. The server turns a label into an actor id; the browser cannot name an actor, role or tenant. Real signed
  sessions are a separate, not yet integrated, boundary (`SIGNED_SESSION_UNAVAILABLE`).
- The hash chain proves alteration, it is not WORM storage. Risk signals are advisory only. Incident holds are a demo of
  retention behaviour, not a legal-hold certification.
- Local only: HTTP on 127.0.0.1, no TLS, no rate limiting beyond body-size and statement timeouts, not a deployable service.
- Tested against PostgreSQL 16 locally; the CI workflow targets 17.
- The UI is built with text nodes only, strict CSP (no inline script or style), no external asset, no service-role key.
