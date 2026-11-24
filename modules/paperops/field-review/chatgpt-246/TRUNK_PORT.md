# W02-01 canonical stock read rehearsal

Owner continuation authorized a trunk-based Draft and an isolated signed
rehearsal. The port starts from canonical trunk
`6bb4c06639dec67695b7b924e8c39c3add3770a5` and takes the reviewed PaperOps
module from #151 head `43baefc8e270f4f81643f71204ddc480edd9c427`. The Codex
reader opens the five pinned form files from the canonical legacy
quarantine. Parent root loaders, historical workflows, migrations and live
application paths are outside this port. The 1,246 field IDs and original
1,000/246 order remain intact.

## Read contract

`createW02StockReview({authUrl, restUrl})` constructs a loopback review
function. It owns no credentials. A caller supplies one GoTrue user access
token, a business ID and two distinct site IDs. Every request uses the same
bearer. GoTrue verifies identity and canonical `build01_context_v1` must
resolve the same actor and tenant with `stock.read` at both sites.

The review checks `inventory.stock_event` and `inventory.transfer` through
`control_read_v1` at both sites, then reads bounded keyset pages from
`inventory_list_balances_v1`. An explicit cross-site disable returns HOLD.
Two observations are compared before the final signed scope recheck. A
change during observation, a different actor or scope, or a changed balance
invalidates a prior fingerprint. A complete observation returns its
fingerprint for read replay. Quantities stay inside the adapter, and the
fingerprint is a non-persistent comparison key.

Canonical balances lack a single ledger revision and the returnable-event
and challan linkage required to tie a witnessed count to W02. Every response
holds posting. The balance reader cannot supply an authenticated opening
carry-forward decision, approved crate/tray master mapping, or a signed
movement snapshot. The synthetic reconciliation in
`w02-returnables-reconciliation.cjs` continues to exercise those candidate
evidence requirements.

## Verification

- All PaperOps source evidence, Codex A001–A020, protected ownership and the
  master matrix are checked in the canonical checkout.
- The canonical root/live/legacy guards verify the 463-byte-preserved-file
  inventory and historical live pins.
- `tests/w02-signed/run.sh` runs GoTrue 2.197.0, PostgREST 12.2.12 and
  canonical numbered migrations on disposable PostgreSQL 17. Genuine
  password sessions cover same-scope reads, foreign tenant and business,
  one-site and read-only roles, stale observations, repeat reads, a
  site-level Control HOLD, invalid tokens and logout/revocation.
- Synthetic receipt fixtures use the canonical command API in the
  disposable database to establish and change observed balances. The W02
  review itself calls only the canonical read RPCs.

W02-01 remains OPEN for an approved immutable returnables snapshot provider,
signed custody evidence and Owner-approved carry-forward. Hosted staging,
release and posting approvals are separate. Coordination Board and Master
Decision Book: NOT WRITTEN.
