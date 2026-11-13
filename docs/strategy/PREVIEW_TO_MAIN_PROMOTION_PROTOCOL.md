# Preview-to-main promotion protocol

## Current boundary — 2026-11-13

`preview/c10-integrated-20261111-v1` is the only integration line for the
synthetic CORE 10 build. It is **363 commits ahead of `main`** at the recorded
boundary. A preview merge means *integrated for demo review*, never
automatically *eligible for main, deployment, or production*.

The current Preview head is `070bea27c92680c57e3f4e37283e3044a0b3f1b2`:

- Build 01 was integrated through PR #86.
- Build 02A canonical approval permissions were integrated through PR #100.
- PR #101 adds the write-free Build 01/02A preview walkthrough source.

## The two lines

| Line | Purpose | What may enter | What it must not imply |
| --- | --- | --- | --- |
| `preview/c10-integrated-20261111-v1` | compatibility and Owner demo integration | tested, additive, synthetic-only slices | production readiness or a main release |
| `main` | release lineage | only a separately reconciled, gate-complete release train | an automatic copy of Preview |

## Required workflow for every builder

1. Claim the module in Decision Book `C10-A061` before coding: owner, current
   Preview base SHA, files/schema namespace, dependencies, canonical demo
   personas, and Draft PR.
2. Build only in the claimed namespace. Do not duplicate membership, permission,
   audit, stock, finance, or identity engines.
3. Before Preview intake, rebase/merge the current Preview base, resolve only
   the claimed overlap, and run the module tests plus combined disposable
   PostgreSQL17, role-negative, replay/race/recovery, and 390/1440 UI checks
   where a UI exists.
4. The integration owner records the Preview merge SHA, exact checks, and all
   missing gates in the Decision Book. A failed or incomplete Draft remains out
   of Preview; nothing is bulk-merged.
5. Each Preview merge receives a promotion record: source commits/PRs,
   migrations and rollback, test evidence, dependencies, legacy impact,
   synthetic-vs-staging truth, and release blockers.

## Continuous main reconciliation — prevents a big-bang conflict

At the end of each completed wave, create a **non-deploying** branch from the
then-current `main`, named `release/c10-reconcile-YYYYMMDD`.

1. Reconcile the selected, promotion-recorded Preview slice into that branch.
   Do not merge the whole Preview branch by default.
2. Resolve conflicts once on the rehearsal branch, preserving original Islamia
   code/data boundaries and avoiding parallel schema/permission engines.
3. Run the release-rehearsal suite: full disposable PG17, signed API negatives,
   browser 390/1440, demo reset, migration/rollback rehearsal, and source/
   secret allowlist checks.
4. Record the exact reconciliation SHA, conflict decisions, and remaining gates
   in the Decision Book. The branch is evidence only until a separate Owner
   release decision.

This is repeated per wave, not deferred until the final ERP merge. Therefore
later main promotion is a reviewed set of already rehearsed changes rather than
a risky 363+ commit surprise.

## Main merge gate

A main PR is allowed only after every selected module is `INTEGRATED` and has:

- canonical synthetic demo acceptance, including isolation/deny/expiry/revoke;
- exact CI and current reconciliation evidence;
- versioned migration plus tested rollback where schema changes exist;
- no real data/account/payment/production action; and
- explicit current Owner approval for that particular release train.

The eventual main PR comes from the reviewed reconciliation branch, never from
an unqualified direct `preview → main` merge.
