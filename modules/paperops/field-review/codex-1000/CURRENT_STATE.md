# PaperOps ১,২৪৬ field — বর্তমান অবস্থা

পর্যবেক্ষণ ২০২৬-১১-২৪। [Machine-readable matrix](completion-matrix.jsonl)-এ প্রতি original ID-এর lane/order, frozen source, rule scope, candidate destination, test, blocker এবং acceptance আছে। [Batch results](PROGRESS.md)-এ A001–A020-এর exact SHA ও Actions run আছে। ৪১৩টি Codex ও ১১০টি ChatGPT field-এ explicit req/show/role syntax পুনরায় মিলেছে। অন্যান্য মাঠেও linked source-rule evidence যেখানে আছে সেটি matrix-এ আছে।

| Lane | মোট | Declaration verified | Batch audit | Local control linked | Signed ERP | Owner-accepted |
|---|---:|---:|---|---:|---:|---:|
| A | ১,০০০ | ১,০০০ | ২০×৫০ complete | ০ | ০ | ০ |
| B | ২৪৬ | ২৪৬ | ৮৬ critical, ১৫০ historical, ১০ reserved পুনরায় মিলেছে | ৭৯ | ০ | ০ |

সকল ২৪৬টি Lane B constructor Parent routing ও frozen source-এর সঙ্গে মিলেছে। `W-02:item`-এর দুইটি মূল constructor রাখা হয়েছে। ৭৯টি existing local links-এর অর্থ control evidence, ১১টি মূল functional gap ও ২০টি obligation signed runtime/acceptance-এর জন্য এখনও OPEN। A019 source attribution resolution এবং Codex batch completion এই open items-এর সংখ্যা কমায়নি।

## PR ও branch reconciliation

| PR | যাচাইকৃত build SHA | Ancestry / verdict | Node 22 |
|---|---|---|---|
| [Parent #132](https://github.com/mistybari99/CORE-10-CENTRAL/pull/132) | `df247deee3548a7f75640e8274c0934d86916d91` | Trunk merge base `6424aabe981513749ebfc166782fd60ff22ba140`, Parent +171 / −59। Trunk-এর root loader/quarantine changes-এর সঙ্গে conflict | [150/150 and guards](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329507431) |
| [Codex #148](https://github.com/mistybari99/CORE-10-CENTRAL/pull/148) | `ad24066e4c5f83a9f74c10c4fae0929cea7bc180` | A020 build Parent +34 / −0। Progress tip `ffcf464279a1f2b146d0276d0850df30f89c51e9` Parent +36 / −0 | [A020 CI](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329921549) |
| [ChatGPT #149](https://github.com/mistybari99/CORE-10-CENTRAL/pull/149) | `72638864dddda7da49f69b8e010ad254a1cb7e23` | Parent merge base `98169c2bf6ebbf3bae875bdee11e51ff06766c48`, Child +55 / −6। Shared workflow conflict। A007 ও A019-এর পূর্বের ownership blob | [211/211](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45276670423) |
| [W02 #150](https://github.com/mistybari99/CORE-10-CENTRAL/pull/150) | `150b3d53d0f97847143a5232f084d3aef06433c8` | #149-এর উপর একটি scoped returnables correction | [214/214](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329036203) |
| [Combined #151](https://github.com/mistybari99/CORE-10-CENTRAL/pull/151) | `12f41e67d6da143aed85fb840871f1aae581324c` প্রথম code commit | Corrected Parent → Codex fast-forward → reviewed Lane B file transfer। প্রথম code commit-এর [combined CI সফল](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45330297936)। বর্তমান exact-head CI Draft PR checks-এ | [Checks](https://github.com/mistybari99/CORE-10-CENTRAL/pull/151/checks) |

- #149 থেকে `field-review/chatgpt-246/**`, `tests/chatgpt-246-*.test.cjs` এবং তিনটি static source consumer নেওয়া হয়েছে। `source-conditional-recheck.cjs`-এ actual O/n read-only evidence আছে। `issue-registry.json`-এর original ownership blob পূর্বের branch evidence হিসেবে আছে। তুলনা বর্তমান Parent manifest ও exact Lane B keys দিয়ে হয়।
- Parent-এর `legacy-rule-extractor.cjs`, `legacy-field-index.json`, `legacy-rule-candidates.json`, `field-routing.cjs`, routing report, manifest ও foundation workflow authoritative। `A007` cashier 304। `A019` slots 920–922। F-03 header item ও ingredient item পৃথক, recipe a/b/c-তে min syntax 4/5/2। এগুলো versioned recipe evidence।
- Standalone Draft test-এর পর canonical port-এ প্রথমে current trunk layout ধরে কেবল reviewed PaperOps changes নিতে হবে। Trunk-এর ২৪টি root HTML এবং manufacturing entry point-এ পরীক্ষামূলক merge conflict এসেছে। Canonical root quarantine বা active shell bundles port-এর ভিত্তি হিসেবে থাকবে। Canonical integration-এর আলাদা GO বাকি।

## Lane B functional gaps

প্রতিটি সারিতে source scope ও local code/test আছে। ১১টির প্রত্যেকটিতে `LOCAL_SYNTHETIC_CONTROL_BUILT`, signed integration/test false, Owner acceptance false এবং real posting false। Test path-এর prefix `modules/paperops/tests/chatgpt-246-`। Source ID, exact test path ও original baseline evidence [registry](../chatgpt-246/issue-registry.json)-এ।

| Gap | Original source verification | Local test stem | বাকি |
|---|---|---|---|
| C02-01 | খালি pay mode = cash print convention | `c02-account-source` | explicit mode বনাম approved fallback ও canonical tender selection |
| C02-02 | yellow `no_receipt`, red `receipt_reason_missing` | `receipt-severity` | exception অনুমোদনকারী, receipt policy, tamper-proof escalation |
| C02-03 | `moneySrc.formOpts('expense_10_2')`, `hasAccounts` | `c02-account-source` | signed scoped account list, active/capability recheck at journal validation |
| C01-01 | handover, hub diff ও warning conditions | `c01-cash-custody` | physical recount evidence, sender/carrier/receiver role binding, Money day and reversal |
| W02-01 | ছয় manual field declaration | `w02-returnables-reconciliation` | approved carry-forward ও Stock snapshot, returnable item model, immutable reversal |
| W02-02 | `cust_order=yes`, `pay=cash` visibility | `w02-customer-payment` | signed order/challan/receipt ও missing-evidence policy |
| W03-01 | original movement condition ও variance/witness source | `w03-stock-count` | freeze revision, independent count, approval and adjustment/reversal transaction |
| R01-01 | source temperature settings/red severity, peak reading, expiry evidence | `r01-food-safety` | approved per-unit limits, Quality notification/quarantine/release authority |
| R01-02 | exact O/n visibility, zero present | `source-helpers` | signed provider field normalization এবং runtime checks |
| R01-03 | voucher rows ও original amount total | `r01-money-day-ledger` | immutable C-02 source linkage, signed Money journal and reversals |
| R01-04 | float, cash, receipts statements and local continuity | `r01-money-day-ledger` | signed advances/refunds/deposits, day lock and independent reconciliation |

## ২০টি obligation-এর একক mapping

প্রতিটি `OPEN`। Gap overlap ক্ষেত্রগুলো নিচে একবার করে দেখানো হয়েছে। Adjacent candidate একটি সম্পর্কিত prototyping path এবং obligation-এর পূর্ণ source coverage বাকি। Exact original fields [control-trace.json](../../control-trace.json)-এ আছে।

| Obligation | Gap / adjacent proof | Canonical destination ও অবশিষ্ট gate |
|---|---|---|
| SHOWROOM_OPEN_SAFETY | R01-01, R01-04 | Quality cold-chain/expiry + Money opening count |
| JALEBI_MEASUREMENT_SEPARATION | পৃথক | Manufacturing independent measurement actor/slot |
| JALEBI_YIELD_AND_UNSOLD | পৃথক | Manufacturing yield and Stock unsold disposition |
| CASH_CUSTODY_PROOF | C01-01 | Money custody line, dual attestations, immutability/reversal |
| GOODS_TWO_PARTY_TRANSFER | W02-01, W02-02 adjacent | Stock receive by independent actor with dispatch/receipt lines |
| PHYSICAL_COUNT_IS_NOT_ADJUSTMENT | W03-01 | Stock freeze/revision and separately approved adjustment |
| STOCK_LEDGER_CARRY_FORWARD | W02-01 adjacent | Stock W-04 balance and GRN/issue/count lineage |
| GRN_ACCEPTANCE_QC | R01-01 adjacent | Procurement receipt and quality holds with exact units/lines |
| THREE_WAY_BILL_MATCH | C02-03 / R01-03 adjacent | Procurement/Money approved PO, accepted GRN, invoice match |
| QUOTE_SELECTION_PROOF | পৃথক | Procurement comparison, exception and threshold policy |
| ORDER_FULFILMENT_ADVANCE | W02-02 / R01-04 adjacent | Sales order/delivery/refund and Money deposit allocation |
| DISCOUNT_ABOVE_LIMIT | পৃথক | Sales/Control discount tier and authenticated approval timestamp |
| RETURN_REFUND_AND_ROOT_CAUSE | R01-04 adjacent | Sales, Money and Quality customer remedy and lot disposition |
| CHANNEL_SETTLEMENT_RECON | R01-04 adjacent | Money statements, fee lines and channel reconciliation |
| AGEING_AND_CREDIT_STOP | পৃথক | Money party-level ageing and Sales credit block |
| FACTORY_PRESTART_AND_BATCH | R01-01 adjacent | Manufacturing release and Quality shift safety |
| RECIPE_VERSION_NOT_DAILY_COPY | A019 | Effective Manufacturing recipe revision and independent approval |
| YIELD_TEST_INPUT_OUTPUT | A019/A020 | Three different test days, typed measured rows and approved target |
| GRADE_AND_SHELF_LIFE | A019 | Versioned QC spec, lot expiry/hold/recall |
| MONTHLY_PROFIT_AR_AP | পৃথক | Finance journal/AR/AP and site-reconciled monthly close |

## Canonical contracts ও executable backlog

Trunk snapshot `6bb4c06639dec67695b7b924e8c39c3add3770a5`। `internal/migrations/`-এ Auth/Control/Approval/Audit, Master 0150–0153, Stock 0200–0206, Finance 0400–0401, Manufacturing 0500–0504 code দেখা গেছে। Sales 030x trunk-এ নেই। Governed staging records-এর max 0206, Sales/Finance/Manufacturing hosted adoption বাকি। Shell signed context built; per-module propagation এবং PaperOps signed authority বাকি।

প্রস্তাবিত সব port-এ server signed subject থেকে live membership, business/site rights ও feature/approval version নিতে হবে। Immutable source tuple হবে tenant/business/site, source form, document/version, row/event এবং action key। Same-key/same-hash replay একই ফল ফেরাবে, same-key/different-hash HOLD। Post-lock actor/policy recheck-এর পর canonical state transition ও Audit event একই transaction-এ। Correction-এর জন্য authorized reversal/compensation original references ধরে। প্রতিটি acceptance suite অন্য tenant/business/site, wrong actor role, stale approval, competing same key ও partial rollback পরীক্ষা করবে।

| Priority | Owner / target | Dependency ও exact path | Acceptance ও ব্যবহারকারীর input |
|---|---|---|---|
| P0 | NP01 / Auth, Control / Approval | `internal/migrations/0117_np01_bootstrap_owner_context.up.sql` ও `apps/central/site/shell-context.js`। PaperOps adapter boundary `modules/paperops/source-books-posting-boundary.cjs` | Signed context authoritative, tampered role/site/expiry denied, revocation during lock rolls back। User site select এবং নিজের sign-in |
| P0 | NP06 / Money | C02 account + R01 book, `field-review/chatgpt-246/c02-account-source.cjs`, `r01-money-day-ledger.cjs`। Canonical `0400_np06_finance_foundation.up.sql`, `0401_np06_journal_reversal.up.sql`। আগে Sales release order | Paid account, source voucher, period and policy versions checked; balanced immutable journal; duplicate or scope mismatch denied; linked authorized reversal। User selects approved tender and attaches receipt/exception |
| P0 | NP03A / Stock | W-02 six returnable fields ও W-03 freeze, `w02-returnables-reconciliation.cjs`, `w03-stock-count-freeze.cjs`, `0201_np03a_inventory_commands.up.sql` ও `0202_np03a_inventory_approval.up.sql` | Signed site-pair movement, opening/snapshot pointer, physical variance HOLD, distinct reviewer, only approved correction produces Stock delta। User enters count/variance proof |
| P0 | NP03A / Quality + NP02 Control | R01 safety fields এবং F-02 lot/spec, `r01-food-safety-review.cjs`, `0203_np03a_procurement_grn.up.sql`, dedicated Quality scope still Board-owned | Active limit version, busy-day samples, lot quarantine and release authority proven। User records temperature, incident and stock lot |
| P0 | Canonical integration owner | Git verified scope and root isolation after selective port from #151, `tests/core10-legacy-move-integrity.test.js`, `tests/core10-live-legacy-guard.test.js` | Exact canonical candidate combined source tests + signed and release acceptance; obtain separate Owner GO before merge |
| P1 | NP03B / Sales | W02 order/payment and S-01 evidence, `w02-customer-payment-source.cjs`, `tests/np03b/correction-security.sql`। Sales 030x forward corrections and 0305 reservation resolution | Linked order, immutable eligible challan and settlement, independent approver, over-collection and return/reversal checked। User picks order / payment evidence |
| P1 | NP05A / Manufacturing + Master | F-03/F-04/F-01, `0500_np05a_manufacturing.up.sql` through `0504_np05a_canonical_master.up.sql`, Codex A019/A020 | Activated recipe/spec, scoped ingredient items and approved UOM, measured trial vs target, maker/checker separation and release rollback। User enters actual measurements and review decision |
| P2 | PaperOps print | `modules/paperops/paperops.js`, `modules/paperops/tests/paperops.test.cjs` after signed data ownership | Source-linked print/preview with business/site scope, readonly calculated/master values এবং কেবল mandatory operational fields |

## Owner decision register

| Decision | Proposed options | Default |
|---|---|---|
| A019 attribution | তিনটি source-attribution এবং derived artifacts | এই scope **authorized**, Parent `df247dee` |
| Isolated integration | Parent-bounded Draft ও combined CI | এই scope **authorized**, #151 |
| C02 payment/receipt | explicit tender / explicitly approved empty=cash, signed exception tier with reason and source receipt | HOLD blank and unapproved exceptions |
| Returnables/cash/count | approved opening source and cycle count authority, stock classes, float/imprest/account policy এবং handover role matrix | HOLD posting or adjustments from unapproved reconciliation |
| Food and product release | business/site settings ও effective Quality/Manufacturing authority | HOLD release when critical policy/evidence absent |
| Canonical release | protected write/port, Owner signed test, merge, hosted apply ও deploy | HOLD until separately scoped GO |

Board ও Master Decision Book **NOT WRITTEN**।

## Build change log

| কাজ | পরিবর্তিত paths | Exact build commit / verification |
|---|---|---|
| A019 attribution | Parent extractor, index, candidates, routing, manifest এবং A007/A019 regression | `df247deee3548a7f75640e8274c0934d86916d91`, [#132 CI](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329507431) |
| A019 batch | `batch-A019.json`, `issues-A019.json`, `audit-A019-recipe.test.cjs`, `summary.cjs`, Codex workflow | `f4cce3aa5c395d01d739a227401d65a4c29e5d5c`, [115 audit tests](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329659659) |
| A020 batch | `batch-A020.json`, `issues-A020.json`, `audit-A020.test.cjs`, Codex workflow | `ad24066e4c5f83a9f74c10c4fae0929cea7bc180`, [121 audit tests](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329921549) |
| W02-01 | `w02-returnables-reconciliation.cjs`, matching test, registry/closure, status, dedicated workflow | `150b3d53d0f97847143a5232f084d3aef06433c8`, [214 PaperOps tests](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45329036203) |
| Integrate + verify | Reviewed Lane B paths, completion matrix generator/output, combined workflow | `12f41e67d6da143aed85fb840871f1aae581324c`, [first combined CI](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45330297936), [current Draft head checks](https://github.com/mistybari99/CORE-10-CENTRAL/pull/151/checks) |
