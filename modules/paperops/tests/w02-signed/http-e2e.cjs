'use strict';

const assert = require('node:assert/strict');
const {createHmac, generateKeyPairSync, sign} = require('node:crypto');
const {test} = require('node:test');
const {setTimeout: delay} = require('node:timers/promises');
const {createW02StockReview} = require('../../field-review/chatgpt-246/w02-canonical-stock-review.cjs');
const {evidenceMessage} = require('../../field-review/chatgpt-246/w02-custody-evidence.cjs');
const {digest} = require('../../source-port-handoff.cjs');

const authUrl = process.env.CORE10_W02_AUTH_URL, restUrl = process.env.CORE10_W02_REST_URL;
const review = createW02StockReview({authUrl, restUrl});
assert.equal(process.env.CORE10_W02_DISPOSABLE, 'W02_LOCAL_ONLY');
const password = 'W02-only-disposable-login!';
const users = {
  owner: 'a0711111-1111-4111-8111-111111111111',
  foreign: 'a0722222-2222-4222-8222-222222222222',
  oneSite: 'a0733333-3333-4333-8333-333333333333',
  readOnly: 'a0744444-4444-4444-8444-444444444444'
};
const selection = {businessId: 9711, fromSiteId: 97111, toSiteId: 97112};
const email = label => 'w02-fixture-' + label + '@example.test';

async function http(url, {token, body, method = 'POST'} = {}) {
  const headers = {'Content-Type': 'application/json'};
  if (token) headers.Authorization = 'Bearer ' + token;
  if (url.startsWith(restUrl + '/')) headers['Content-Profile'] = 'core10';
  const res = await fetch(url, {headers, method, body: body && JSON.stringify(body),
    redirect: 'error', signal: AbortSignal.timeout(10000)});
  return {ok: res.ok, status: res.status, data: await res.json().catch(() => null)};
}
function ok(result, label) {
  assert.equal(result.ok, true, label + ' HTTP ' + result.status + ' ' + (result.data?.message ?? ''));
  return result.data;
}
async function rpc(token, name, body = {}) {
  return ok(await http(restUrl + '/rpc/' + name, {token, body}), name);
}
async function login(label) {
  const result = await http(authUrl + '/token?grant_type=password', {body: {email: email(label), password}});
  const data = ok(result, 'GoTrue password login');
  assert.equal(data.user.id, users[label]);
  return data.access_token;
}

async function provisionUsers() {
  const secret = process.env.CORE10_W02_SIGNER;
  assert.ok(secret?.length >= 32);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const claims = encode({alg: 'HS256', typ: 'JWT'}) + '.' + encode({
    role: 'service_role', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 120
  });
  const token = claims + '.' + createHmac('sha256', secret).update(claims).digest('base64url');
  for (const [label, id] of Object.entries(users)) {
    const data = ok(await http(authUrl + '/admin/users', {token, body: {
      id, email: email(label), password, email_confirm: true, role: 'authenticated', aud: 'authenticated'
    }}), 'Create synthetic Auth identity');
    assert.equal(data.id, id);
  }
}

async function seedStockCommand(token, suffix, {kind = 'receive', source = null,
  destination = 971111, quantity, item = 97101}) {
  // Plant ledger state through the canonical write path inside the disposable
  // fixture. The module under review receives only the signed read interface.
  const created = await rpc(token, 'create_inventory_command_v1', {
    p_business: 9711, p_kind: kind, p_destination: destination, p_source: source,
    p_item: item, p_quantity: quantity, p_reason: null, p_request: 'w02-fixture-move-' + suffix
  });
  const advance = (action, version) => rpc(token, 'advance_inventory_command_v1', {
    p_command: created.command_id, p_action: action, p_version: version, p_request: 'w02-fixture-' + action + '-' + suffix
  });
  const confirmed = await advance('confirm', created.version);
  const posted = await advance('post', confirmed.version);
  assert.equal(posted.status, 'posted');
  return posted;
}

async function proveCustody(owner) {
  const scope = {tenantId: 971, ...selection};
  const items = {crates: 97101, trays: 97102};
  const actors = {
    openingReviewer: 'b0711111-1111-4111-8111-111111111111',
    challanRegistrar: 'b0722222-2222-4222-8222-222222222222',
    counter: 'b0733333-3333-4333-8333-333333333333',
    witness: 'b0744444-4444-4444-8444-444444444444'
  };
  const keys = Object.fromEntries(Object.keys(actors).map(role => [role, generateKeyPairSync('ed25519')]));
  const signers = Object.fromEntries(Object.entries(actors).map(([role, actorId]) => [role, {
    actorId, publicKey: keys[role].publicKey.export({type: 'spki', format: 'pem'})
  }]));
  const custody = {scope, items, signers};
  const linkedReview = createW02StockReview({authUrl, restUrl, custody});
  const reviewEvidence = (evidence, extra) => linkedReview({...selection, accessToken: owner, evidence, ...extra});
  const signPayload = (role, payload, signingScope = scope, actor = actors[role]) =>
    sign(null, evidenceMessage(role, actor, signingScope, payload), keys[role].privateKey).toString('base64url');
  const at = new Date().toISOString();
  const move = (suffix, quantity, reverse = false) => seedStockCommand(owner, suffix, {
    kind: 'transfer', quantity, source: reverse ? 971121 : 971111, destination: reverse ? 971111 : 971121
  });
  const issue = await move('issue', 2), returned = await move('return', 1, true);
  await delay(10);
  const countedAt = new Date().toISOString();
  const prior = {kind: 'APPROVED_PRIOR_CLOSE', record: 'CLOSE-9711-01', at, crates: 2, trays: 1};
  const movements = [[issue, 'ISSUE'], [returned, 'RETURN']].map(([row, direction], i) => ({
    commandId: row.command_id, stockRef: row.stock_ref, asset: 'crates', direction,
    quantity: row.quantity, challan: 'W02-CHALLAN-' + i, line: '1'
  }));
  function signedEvidence({opening = prior, rows = movements, count = {}, signingScope = scope} = {}) {
    const window = {openingDigest: digest(opening), movements: rows};
    const witnessed = {record: 'COUNT-9711-02', at: countedAt, windowDigest: digest(window), crates: 3, trays: 1, ...count};
    return structuredClone({
      opening: {payload: opening, signature: signPayload('openingReviewer', opening, signingScope)},
      window: {payload: window, signature: signPayload('challanRegistrar', window, signingScope)},
      count: {payload: witnessed, counterSignature: signPayload('counter', witnessed, signingScope),
        witnessSignature: signPayload('witness', witnessed, signingScope)}
    });
  }

  await test('GoTrue review links witnessed count and prior close to two canonical posted movements and signed challan lines', async () => {
    const before = await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711});
    const evidence = signedEvidence();
    const matched = await reviewEvidence(evidence);
    assert.equal(matched.status, 'HOLD');
    assert.equal(matched.canPost, false);
    assert.equal(matched.signedMovementSnapshotVerified, false);
    assert.equal(matched.custodyEvidenceVerified, true);
    assert.equal(matched.matchedMovements, 2);
    assert.equal(matched.evidenceDigest, digest(['CORE10.W02.CUSTODY.V1', scope, evidence.count.payload]));
    assert.deepEqual(await reviewEvidence(evidence, {priorObservation: matched.observation}), matched);
    assert.deepEqual(await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711}), before);
  });

  await test('missing approved prior close holds and a first-count substitute cannot pass', async () => {
    const hold = await reviewEvidence();
    assert.equal(hold.reason, 'W02_APPROVED_PRIOR_CLOSE_REQUIRED');
    assert.equal(hold.observation, null);
    await assert.rejects(reviewEvidence(signedEvidence({opening: {...prior, kind: 'FIRST_COUNT'}})),
      {code: 'W02_APPROVED_PRIOR_CLOSE_REQUIRED'});
    await assert.rejects(review({...selection, accessToken: owner, evidence: signedEvidence()}),
      {code: 'W02_CUSTODY_PROVIDER_REQUIRED'});
  });

  await test('tampered, foreign-scope or non-independent evidence fails closed', async () => {
    const tampered = signedEvidence();
    tampered.count.payload.crates++;
    await assert.rejects(reviewEvidence(tampered), {code: 'W02_EVIDENCE_SIGNATURE_INVALID'});
    await assert.rejects(reviewEvidence(signedEvidence({signingScope: {...scope, tenantId: 972}})),
      {code: 'W02_EVIDENCE_SIGNATURE_INVALID'});
    assert.throws(() => createW02StockReview({authUrl, restUrl, custody: {
      ...custody, signers: {...signers, witness: {...signers.witness, actorId: signers.counter.actorId}}
    }}), {code: 'W02_INDEPENDENT_REVIEW_REQUIRED'});
    const sameBookActor = createW02StockReview({authUrl, restUrl, custody: {
      ...custody, signers: {...signers, witness: {...signers.witness, actorId: users.owner}}
    }});
    const reassigned = signedEvidence();
    await assert.rejects(sameBookActor({...selection, accessToken: owner, evidence: reassigned}),
      {code: 'W02_EVIDENCE_SIGNATURE_INVALID'});
    reassigned.count.witnessSignature = signPayload('witness', reassigned.count.payload, scope, users.owner);
    await assert.rejects(sameBookActor({...selection, accessToken: owner, evidence: reassigned}),
      {code: 'W02_INDEPENDENT_COUNT_REQUIRED'});
  });

  await test('a signed bundle cannot omit a movement, substitute a Stock ref or duplicate a challan line', async () => {
    await assert.rejects(reviewEvidence(signedEvidence({rows: movements.slice(0, 1)})),
      {code: 'W02_MOVEMENT_WINDOW_MISMATCH'});
    await assert.rejects(reviewEvidence(signedEvidence({rows: [{...movements[0], stockRef: 9999}, movements[1]]})),
      {code: 'W02_MOVEMENT_WINDOW_MISMATCH'});
    await assert.rejects(reviewEvidence(signedEvidence({rows: [movements[0], {...movements[1], challan: movements[0].challan}]})),
      {code: 'W02_DUPLICATE_MOVEMENT_OR_CHALLAN_LINE'});
    await assert.rejects(reviewEvidence(signedEvidence({count: {crates: 2}})),
      {code: 'W02_WITNESSED_COUNT_MISMATCH'});
    await assert.rejects(reviewEvidence(signedEvidence({count: {at: returned.posted_at}})),
      {code: 'W02_MOVEMENT_AT_WINDOW_BOUNDARY'});
  });

  await test('a net-zero later issue and return still make the witnessed count stale', async () => {
    const evidence = signedEvidence();
    const before = await reviewEvidence(evidence);
    await move('late-issue', 1);
    await move('late-return', 1, true);
    await assert.rejects(reviewEvidence(evidence, {priorObservation: before.observation}),
      {code: 'W02_COUNT_STALE_NEW_MOVEMENT'});
  });
}

async function run() {
  const [owner, foreign, oneSite, readOnly] = await Promise.all(Object.keys(users).map(login));
  await seedStockCommand(owner, 'initial', {quantity: 5});
  const ownerRead = extra => review({...selection, accessToken: owner, ...extra});

  await test('real GoTrue read and deterministic read replay leave canonical stock commands unchanged', async () => {
    const before = await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711});
    const first = await ownerRead();
    assert.equal(first.status, 'HOLD');
    assert.equal(first.reason, 'W02_SIGNED_MOVEMENT_AND_CARRY_FORWARD_REQUIRED');
    assert.equal(first.sourceFieldIDs.length, 6);
    assert.equal(first.canPost, false);
    assert.equal(first.signedMovementSnapshotVerified, false);
    assert.match(first.observation, /^[0-9a-f]{64}$/);
    assert.deepEqual(await ownerRead({priorObservation: first.observation}), first);
    assert.deepEqual(await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711}), before);
    const staff = await ownerRead({accessToken: readOnly});
    assert.equal(staff.canPost, false);
    assert.equal(staff.reason, first.reason);
    assert.notEqual(staff.observation, first.observation);
    const swapped = await ownerRead({accessToken: readOnly, priorObservation: first.observation});
    assert.equal(swapped.reason, 'W02_STALE_OR_SCOPE_MISMATCHED_OBSERVATION');
    assert.equal(swapped.observation, null);
  });

  await test('foreign tenant, foreign site/business and one-site staff fail closed', async () => {
    await assert.rejects(ownerRead({accessToken: foreign}), {code: 'W02_SCOPE_DENIED'});
    await assert.rejects(ownerRead({toSiteId: 97211}), {code: 'W02_SCOPE_DENIED'});
    await assert.rejects(ownerRead({toSiteId: 97121}), {code: 'W02_SCOPE_DENIED'});
    await assert.rejects(ownerRead({accessToken: oneSite}), {code: 'W02_SCOPE_DENIED'});
  });

  await test('canonical stock changes invalidate a prior observation', async () => {
    const before = await ownerRead();
    await seedStockCommand(owner, 'changed', {quantity: 1});
    const stale = await ownerRead({priorObservation: before.observation});
    assert.equal(stale.reason, 'W02_STALE_OR_SCOPE_MISMATCHED_OBSERVATION');
    assert.equal(stale.observation, null);
    const fresh = await ownerRead();
    assert.notEqual(fresh.observation, before.observation);
    assert.equal(fresh.canPost, false);
  });

  await proveCustody(owner);

  await test('site-level Control disables transfer review without authorizing posting', async () => {
    await rpc(owner, 'control_set_v1', {
      p_business: 9711, p_site: 97112, p_feature: 'inventory.transfer', p_enabled: false,
      p_stages: 0, p_params: {}, p_effective_from: null, p_inherit: false,
      p_expected_version: 0, p_reason: 'W02 disposable site switch', p_request_key: 'w02-site-switch'
    });
    const held = await ownerRead();
    assert.equal(held.reason, 'W02_STOCK_CONTROL_DISABLED');
    assert.equal(held.observation, null);
    assert.equal(held.canPost, false);
  });

  await test('unsigned, invalid connections, malformed selections and revoked sessions deny', async () => {
    assert.throws(() => createW02StockReview({authUrl: 'https://remote.example', restUrl}), {code: 'W02_LOOPBACK_REQUIRED'});
    await assert.rejects(ownerRead({toSiteId: 97111}), {code: 'W02_INVALID_SELECTION'});
    await assert.rejects(ownerRead({priorObservation: 'old'}), {code: 'W02_INVALID_SELECTION'});
    await assert.rejects(ownerRead({accessToken: undefined}), {code: 'W02_SIGNED_SESSION_REQUIRED'});
    const pieces = owner.split('.');
    pieces[2] = (pieces[2][0] === 'A' ? 'B' : 'A') + pieces[2].slice(1);
    await assert.rejects(ownerRead({accessToken: pieces.join('.')}), {code: 'W02_SIGNED_SESSION_REQUIRED'});
    ok(await http(authUrl + '/logout?scope=local', {token: owner}), 'GoTrue session logout');
    await assert.rejects(ownerRead(), /W02_(SIGNED_SESSION_REQUIRED|CANONICAL_READ_DENIED)/);
  });
}

(process.argv[2] === 'users' ? provisionUsers() : run()).catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
