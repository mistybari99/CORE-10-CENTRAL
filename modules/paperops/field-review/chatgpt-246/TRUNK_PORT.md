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

Every response holds posting. Successful rehearsal evidence verifies the
locally configured signatures and their canonical Stock matches. The
canonical release port still needs a durable site-pair challan and prior
close registry, approved Master item mappings and actor/key custody,
and an atomic ledger revision with signed witness and reversal semantics.
The current inventory list provides no jointly committed event watermark
or canonical W02 challan record. The rehearsal uses PostgreSQL posting time
and fails closed at exact evidence-window boundaries.

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
  count reconciliation and stale net-zero movement.
- Synthetic receipt fixtures use the canonical command API in the
  disposable database to establish and change observed balances. The W02
  review itself calls only the canonical read RPCs.

W02-01 remains OPEN for the canonical custody publication and signed staging
acceptance. Hosted staging, release and posting approvals are separate.
Coordination Board and Master Decision Book: NOT WRITTEN.
