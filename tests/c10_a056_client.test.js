"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { create, createPublic, hmacSign, hmacVerify, RPC_NAMES } = require("../core10-crm-lifecycle-client.js");

let signed = true, calls = [], respond = (n, a) => ({ data: { ok: true, n }, error: null });
const client = { auth: { getUser: async () => signed ? { data: { user: { id: "u" } }, error: null } : { data: { user: null }, error: { code: "401" } } },
  schema: (k) => { assert.equal(k, "c10_demo"); return { rpc: async (n, a) => { calls.push([n, a]); return respond(n, a); } }; } };

(async () => {
  const api = create({ client });
  await api.createCustomer({ business: 101, site: 1001, kind: "person", display_name: "A", request: "cust-req-0001" });
  assert.deepEqual(calls[0], ["a056_create_customer_v1", { p_business: 101, p_site: 1001, p_kind: "person", p_display_name: "A", p_legal_name: null, p_email: null, p_phone: null, p_tags: null, p_request: "cust-req-0001" }]);
  await assert.rejects(() => api.createCustomer({ business: 101, kind: "person", display_name: "A" }), /INVALID_ARG:request/);
  await assert.rejects(() => api.createCustomer({ business: "x", kind: "person", display_name: "A", request: "cust-req-0002" }), /INVALID_ARG:business/);
  await assert.rejects(() => api.createCustomer({ business: 101, kind: "person", display_name: "A", request: "short" }), /INVALID_ARG:request/);
  await assert.rejects(() => api.createCustomer({ business: 101, kind: "person", display_name: "A", request: "cust-req-0003", tenant: 2 }), /UNKNOWN_ARG:tenant/);
  await assert.rejects(() => api.listCustomers({}), /INVALID_ARG:business/);
  await assert.rejects(() => api.decideQuotation({ quotation: 1, version_no: 1, decision: "approve", request: "bad key!" }), /INVALID_ARG:request/);
  await api.mergeCustomers({ survivor: 1, loser: 2, expected_survivor: 1, expected_loser: 1, request: "merge-req-0001", reason: "dup" });
  assert.equal(calls.at(-1)[0], "a056_merge_customers_v1");
  // error code extraction
  respond = () => ({ data: null, error: { message: "A056_OPT_OUT_PRECEDENCE", code: "P0001" } });
  await assert.rejects(() => api.recordConsent({ customer: 1, channel: "email", purpose: "marketing", status: "granted", source: "x", request: "consent-req-01" }), (e) => e.code === "A056_OPT_OUT_PRECEDENCE");
  respond = () => ({ data: null, error: { message: "ERROR: A056_DENIED", code: "P0001" } });
  await assert.rejects(() => api.listCustomers({ business: 1 }), (e) => e.code === "A056_DENIED");
  respond = () => ({ data: null, error: null }); await assert.rejects(() => api.readPipeline({ business: 1 }), /UNVERIFIED_RESPONSE/);
  respond = () => ({ data: "id,kind\r\n1,person", error: null }); assert.match(await api.exportCustomersCsv({ business: 1 }), /^id,kind/);
  respond = () => ({ data: { x: 1 }, error: null }); await assert.rejects(() => api.exportCustomersCsv({ business: 1 }), /UNVERIFIED_RESPONSE/);
  signed = false; await assert.rejects(() => api.readSettings({ business: 1 }), /SIGN_IN_REQUIRED/); signed = true;
  await assert.rejects(() => create({}).readSettings({ business: 1 }), /SIGNED_CLIENT_REQUIRED/);
  assert.equal(api.release().production, false); assert.equal(api.release().provider, "NOOP");
  // public intake
  respond = () => ({ data: { reference: "ENQ-1", status: "DRAFT", replayed: false }, error: null });
  const pub = createPublic({ client });
  assert.equal((await pub.submit({ token: "c10in_abc", idempotency: "idem-key-0001", payload: { email: "a@b.test" } })).status, "DRAFT");
  respond = () => ({ data: { reference: "ENQ-1", status: "CONFIRMED" }, error: null });
  await assert.rejects(() => pub.submit({ token: "c10in_abc", idempotency: "idem-key-0002", payload: {} }), /UNVERIFIED_RESPONSE/);
  await assert.rejects(() => pub.submit({ token: "c10in_abc", idempotency: "x", payload: {} }), /INVALID_ARG:idempotency/);
  // HMAC envelope: deterministic, tamper and replay-window detection
  const sig = await hmacSign("s3cret", "post", "/rpc/a056", { a: 1 }, 1000);
  assert.match(sig, /^[0-9a-f]{64}$/); assert.equal(sig, await hmacSign("s3cret", "POST", "/rpc/a056", { a: 1 }, 1000));
  assert.equal(await hmacVerify("s3cret", "POST", "/rpc/a056", { a: 1 }, 1000, sig, 1000), true);
  assert.equal(await hmacVerify("s3cret", "POST", "/rpc/a056", { a: 2 }, 1000, sig, 1000), false);
  assert.equal(await hmacVerify("other", "POST", "/rpc/a056", { a: 1 }, 1000, sig, 1000), false);
  assert.equal(await hmacVerify("s3cret", "POST", "/rpc/a056", { a: 1 }, 1000, sig, 1000 + 10 * 60000), false);
  // contract sync: every client RPC exists in SQL, is granted, and is documented
  const sql = ["core", "pipeline", "growth"].map((n) => fs.readFileSync(path.join(__dirname, "..", "internal/enterprise-sql", `c10_a056_${n}_v1.sql`), "utf8")).join("\n").toLowerCase();
  const doc = fs.readFileSync(path.join(__dirname, "..", "docs/architecture/C10_A056_RPC_CONTRACT.md"), "utf8").toLowerCase();
  for (const n of RPC_NAMES) { assert.ok(sql.includes("function c10_demo." + n.toLowerCase() + "("), "missing in SQL: " + n); assert.ok(doc.includes(n.toLowerCase()), "missing in contract: " + n); }
  assert.ok(sql.includes("revoke all on function %s from public,anon,authenticated"), "functions are closed by default");
  for (const bad of ["insert into c10_demo.operation_orders_v1", "update c10_demo.operation_orders_v1", "insert into c10_demo.stock_movements", "insert into c10_demo.inventory_"]) assert.ok(!sql.includes(bad), "direct A049/A048 write: " + bad);
  console.log("PASS A056 signed client: arg validation, receipts, error codes, public intake, HMAC, SQL/contract sync, no direct A049 writes");
})().catch((e) => { console.error(e); process.exitCode = 1; });
