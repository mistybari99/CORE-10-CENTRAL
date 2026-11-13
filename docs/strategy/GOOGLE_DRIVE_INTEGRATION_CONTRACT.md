# Google Drive Integration Contract

## Two separate requirements

1. **Project governance:** this repository reads/updates the existing CORE 10 Master Decision Book. It is not a product tenant integration and must never create a competing decision register.
2. **Product Drive adapter:** each tenant owner explicitly consents to narrowly scoped Drive document/export jobs. The platform owner's Google account is never blanket access to customer files.

## Current implementation truth

There is no product Drive adapter. PR #27 (`9da6403…`) owns provider accounts, secret references, dry-run, outbox/idempotency, retry lease, signature boundary, usage caps, audit and kill switch. Drive must extend/reconcile that contract; this Issue #68 branch deliberately does not create a second provider framework.

## Future adapter contract

`consent configured → scoped export request → queued → upload attempted → object/version verified → completed | conflict | retry | dead-letter | revoked`

Required fields include tenant/business/site, canonical source document/version, object purpose, approved folder mapping, MIME type, payload hash, idempotency key, expected ETag/version, token secret reference, requested/verified scopes, retry lease, quota usage, actor/correlation ID, retention and immutable audit result.

## OAuth and privacy

- OAuth 2.0 authorization code flow with explicit tenant-owner consent and least scopes.
- Prefer app-created/app-visible files where product requirements permit; broader Drive access requires a specific reviewed need.
- Tokens are encrypted backend secrets referenced by ID; never browser-visible, logged, committed or stored in SQL metadata payloads.
- Platform operator has no implicit document access. Support access is separately consented, time-bound and audited.
- Revoke disconnects new jobs, invalidates token references and preserves nonsecret audit/provenance.

## Folder and object mapping

Mapping keys include tenant, business, optional site, document class and environment. User-selected folder IDs are validated within the consenting account. File names are display metadata, never authority. Cross-tenant folder/object IDs are denied without disclosing existence.

## Idempotency, conflict and quotas

- Same key/same payload returns the prior object/version; changed payload conflicts.
- Upload timeout remains `UNKNOWN` until query/reconciliation prevents duplicate objects.
- ETag/version mismatch becomes a visible conflict; no silent overwrite.
- Quota/rate-limit response schedules bounded backoff; owner sees usage/threshold and kill switch.

## Export versus backup

Invoices, receipts and reports are exports/attachments. A database file copied to Drive is still an **unverified backup**. Backup acceptance additionally requires encryption, complete manifest (DB/Auth/Storage/config as applicable), key recovery, isolated restore, counts/checksums, stock lineage, DR=CR reconciliation, tenant isolation and measured recovery evidence.

## Mock/stage/test plan

1. Reconcile PR #27 interfaces and add a `documents/drive` provider family.
2. Pure mock adapter with deterministic synthetic documents; no network/OAuth.
3. Test two tenants, revoked membership, cross-tenant object ID, duplicate retry, timeout-after-success, ETag conflict, quota, kill switch and secret redaction.
4. Explicitly authorized nonproduction OAuth stage using synthetic files.
5. Production connection only after privacy, rollback, monitoring and owner approval.

Official references (retrieved 2026-11-11): https://developers.google.com/drive/api/guides/about-auth and https://developers.google.com/identity/protocols/oauth2
