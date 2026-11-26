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

## Custody evidence rehearsal

The selected opening rule requires an independently approved prior close for
the same tenant, business and directed site pair. A missing prior close holds
the review. A first-count substitute is outside this rule.

The server-side rehearsal config pins that scope, two crate/tray item IDs and
the Ed25519 actor/key mapping for the opening reviewer, challan registrar,
counter and witness. Request evidence consists of a prior close envelope,
the signed movement window that references its digest, and a count
co-signed by the counter and witness that references the window digest.
Each signature binds the protocol version, role, actor, scope and payload.
The opening reviewer differs from the registrar. The counter and witness
differ from each other and from the recorded Stock command actors.

`inventory_list_commands_v1` supplies the canonical posted transfer command
and ledger reference. For mapped crate/tray items and the selected pair,
the adapter checks each signed line's command, Stock ref, item, direction
and quantity. Every movement after the opening and before the count must
be represented. Duplicate command, Stock and challan-line references,
unresolved timestamps, over-returns and count discrepancies fail closed.
A later movement invalidates the count even if on-hand balances return to
their earlier values. Reads use bounded pages and the same user bearer.

## Numbered database Draft

The Owner authorized the isolated NP03A schema and disposable tests. Draft
`0211_np03a_w02_custody_registry` follows the pending 0207–0210 lane work.
Confirm ordering and the lane reservation during integration, before any
hosted apply.

The registry stores a directed site pair and crate/tray Master references,
approved-close lineage, covered transfer references, canonical challan lines,
and Ed25519 public keys and revocations. PostgreSQL rejects changes to
published rows and their truncation. A prior close and the references it
covers must be published in one transaction. The down migration refuses
to remove a populated registry. A scoped signed user has the read RPC.
Publication and key enrollment are reserved for a trusted authority. The
disposable harness seeds its evidence using the local database owner.

`w02_custody_snapshot_v1` checks both sites and effective Stock Control inside
one PostgreSQL MVCC snapshot. The revision covers exact pending transfer IDs,
paired Stock postings, Stock command and Audit linkage, registry lines,
keys and the approved close. Coverage uses explicit references. A newer
Stock transfer changes the revision even when it leaves the net balance
unchanged. An incomplete window or missing movement, Audit, challan or key
proof holds the review.

Use `createW02StockReview({authUrl, restUrl, canonicalRegistry: true})`
for the numbered draft path. Supply the returned Stock revision in the
co-signed count payload. The opening payload and signed challan lines carry
their registered `sourceSha256` values. The adapter resolves the scoped
Master and signer mappings from the snapshot, verifies the count, and
rechecks the revision and signed scope before returning. Revoking the
latest role key does not restore a previously enrolled key.

Every response holds posting. The revision represents a consistent read
of committed state. A future publication or posting transaction must
revalidate it inside its own write boundary. A signed evidence publisher,
production actor and key enrollment, accountable rotation/renewal,
and reversal acceptance are separate release dependencies.

## Verification

- All PaperOps source evidence, Codex A001–A020, protected ownership and the
  master matrix are checked in the canonical checkout.
- The canonical root/live/legacy guards verify the 463-byte-preserved-file
  inventory and historical live pins.
- `tests/w02-signed/run.sh` runs GoTrue 2.197.0, PostgREST 12.2.12 and
  canonical numbered migrations on disposable PostgreSQL 17. Genuine
  password sessions cover same-scope reads, foreign tenant and business,
  one-site and read-only roles, stale observations, repeat reads, a
  site-level Control HOLD, invalid tokens and logout/revocation. Additional
  cases cover signed custody replay, an absent approved close, tampering,
  foreign scope and actor reuse, duplicate or mismatched source references,
  count reconciliation and stale net-zero movement. The numbered schema
  adds cases for uncommitted registry isolation, same-snapshot Stock/Audit
  linkage, approved opening coverage, ACLs and key revocation.
- Synthetic receipt fixtures use the canonical command API in the
  disposable database to establish and change observed balances. The W02
  review itself calls only the canonical read RPCs.

W02-01 remains OPEN for signed evidence publication and staging acceptance.
Hosted staging, release and posting approvals are separate.
Coordination Board and Master Decision Book: NOT WRITTEN.

## Private close publication Draft

Draft `0212_np03a_w02_close_publication` adds a private finalization
transaction on top of the numbered registry. The server first verifies the
same actor's GoTrue session, previously observed Stock and Control context,
and the count's registered Ed25519 signatures. The trusted persistence port
independently resolves the session and invokes the private PostgreSQL
function. The function checks actual scoped Owner permissions and the
active opening-reviewer assignment before creating a record.

The transaction rechecks the pending Stock revision and both sites'
effective Control settings, then commits the next close, its covered
transfers, the retained signed envelope and the canonical Audit receipt
together. Reusing the same request key with identical evidence returns the
original receipt. A different actor or payload conflicts. The reader
returns the published close as the next opening, and every API response
still has `canPost:false`.

The draft uses short no-wait table locks at publication time to prevent a
transfer or registry change between revision check and commit. Audit lock
waits are bounded, with a retry result. This locking choice is part of the
disposable rehearsal and affects concurrent Stock writers during the save.
Stock writer procedures remain byte-identical. A failed save rolls back the
close, coverage and Audit record.

No application or production caller is granted access by the migration.
The harness provisions a disposable role that can execute the private
function and uses actual GoTrue sessions for publication. Initial signed
source publication, real key enrollment and custody, hosted acceptance,
reversal and posting remain open.

The ordered upgrade test imports only the byte-identical 0207–0210 pairs
from Stock Lane `ad4b956e1523cbc8e7d016f9392150bf3267774c` into a disposable
checkout. The published review branch does not claim those migrations.
