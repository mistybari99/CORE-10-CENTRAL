# 2026-11-24 isolated PaperOps continuation — evidence hardening

**Parent:** Draft #152 at `073da5b3f2606f782f2e7f41aa629d5b54dfe192`.
**Work scope:** nonposting Lane B P0 controls only; unchanged 1,000/246 manifest, static source hashes, shared migrations and canonical runtime contracts.

## Actual code changes

- C02-03 / C02-01: a C-02 voucher reference can no longer reuse ANY Money account provider source-proof reference, including an unselected account option. The existing chosen-account and provider-replay restrictions are preserved.
- W03-01: reject normalized invalid UTC civil dates and timestamps with more than six fractional digits. Freeze and movement boundaries now compare integer microseconds, preventing Date.parse millisecond rounding from accepting outside-window events.
- Added adversarial tests: unselected evidence collision, invalid February dates, rejected sub-microsecond timestamps, before/inside/after microsecond movement boundaries.

## Evidence qualification

Original source is statically inspected using the existing pinned modules; these changes are **stricter nonposting controls**, not claims about historic legacy date precision or new Owner policies. No signed Money provider, verified physical stock count, adjustment RPC, durable reversal, new database migration, hosted write, or live deployment is included. Both C02-03 and W03-01 functional gaps remain OPEN for canonical signed integration and Owner approval.

The new exact-head stacked PR workflow exercises the combined source/control set, original 1,246-field matrix, A001–A020 and live/legacy boundary; record its actual run link only after it exists.

## Second code slice — W02 canonical Owner Control replay (2026-11-24)

- The signed W02 read adapter's local observation is now versioned `CORE10.W02.REGISTRY.V2` and includes both sites' effective Stock/transfer Control tuples (enabled, source, version, approval stages and transfer permission), in addition to actor, scope and canonical Stock/registry revision.
- It re-reads Control after custody signature verification and second canonical Stock revision read. Any Control change during review returns `W02_CONTROL_OBSERVATION_CHANGED` HOLD; a prior V1/V2 observation from an earlier policy is stale. No policy is invented or automatically approved.
- A genuine disposable GoTrue/PostgREST/PG17 adversarial scenario tests site-specific Control stage changes while Stock revision stays unchanged, stale observation replay, and deterministic Control change after first W02 snapshot. It confirms no stock postings from the read adapter and restores the test policy.
- The scope remains *nonposting*. The real production trusted evidence publisher, Owner policy acceptance and staging integration are still OPEN.
