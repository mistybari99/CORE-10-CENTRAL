'use strict';

const assert = require('node:assert/strict');
const {createHmac, generateKeyPairSync, sign} = require('node:crypto');
const {spawn, spawnSync} = require('node:child_process');
const {once} = require('node:events');
const {test} = require('node:test');
const {setTimeout: delay} = require('node:timers/promises');
const {createW02StockReview} = require('../../field-review/chatgpt-246/w02-canonical-stock-review.cjs');
const {createW02ClosePublisher} = require('../../field-review/chatgpt-246/w02-close-publisher.cjs');
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
const custodyActors = {
  openingReviewer: 'b0711111-1111-4111-8111-111111111111',
  challanRegistrar: 'b0722222-2222-4222-8222-222222222222',
  counter: 'b0733333-3333-4333-8333-333333333333',
  witness: 'b0744444-4444-4444-8444-444444444444'
};

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
  const actors = custodyActors;
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

function assertDisposableSqlTarget() {
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.match(process.env.PGDATABASE, /^core10_w02_signed_\d+$/);
}

function trustedFixtureSql(sql, expectedFailure) {
  assertDisposableSqlTarget();
  const result = spawnSync('psql', ['-XAtq', '-v', 'ON_ERROR_STOP=1', '-c', sql],
    {encoding: 'utf8', timeout: 10000});
  if (result.error) throw result.error;
  if (expectedFailure) {
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, expectedFailure);
  } else {
    assert.equal(result.status, 0, result.stderr);
  }
  return result.stdout.trim();
}

async function publishFixtureInTransaction(sql, beforeCommit) {
  assertDisposableSqlTarget();
  const child = spawn('psql', ['-XAtq', '-v', 'ON_ERROR_STOP=1'], {stdio: ['pipe', 'pipe', 'inherit']});
  const exited = once(child, 'exit');
  const ready = once(child.stdout, 'data', {signal: AbortSignal.timeout(5000)});
  try {
    child.stdin.write(`BEGIN;\n${sql};\nSELECT 'W02_FIXTURE_READY';\n`);
    const [marker] = await Promise.race([ready, exited.then(() => { throw Error('Fixture publisher exited early'); })]);
    assert.equal(String(marker).trim(), 'W02_FIXTURE_READY');
    await beforeCommit();
    child.stdin.end('COMMIT;\n');
    assert.equal((await exited)[0], 0);
  } finally {
    child.kill();
    await exited.catch(() => {});
  }
}

async function proveCanonicalRegistry(owner, foreign, oneSite) {
  const scope = {tenantId: 971, ...selection};
  const adapter = createW02StockReview({authUrl, restUrl, canonicalRegistry: true});
  const inspect = extras => adapter({...selection, accessToken: owner, ...extras});
  const args = {p_business: 9711, p_from_site: 97111, p_to_site: 97112};
  const read = () => rpc(owner, 'w02_custody_snapshot_v1', args);
  const members = Object.entries({...custodyActors, openingReviewer: users.owner}).map(([role, actor]) => ({
    role, actor, ...generateKeyPairSync('ed25519')
  }));
  const historicWitness = generateKeyPairSync('ed25519').publicKey.export({type: 'spki', format: 'der'}).toString('hex');
  const priorHash = digest('prior close source fixture');
  let pair, openingAt;
  const move = (label, reverse = false) => seedStockCommand(owner, 'registry-' + label, {
    kind: 'transfer', quantity: 1, source: reverse ? 971121 : 971111, destination: reverse ? 971111 : 971121
  });
  function insertLine(stockRef, label) {
    return `INSERT INTO core10.w02_challan_lines_v1
      (pair_id,business_id,stock_ref,challan_ref,line_ref,source_sha256)
      VALUES (${pair},9711,${stockRef},'REG-${label}','1','${digest(label)}')`;
  }
  function signRole(role, payload) {
    const member = members.find(entry => entry.role === role);
    return sign(null, evidenceMessage(role, member.actor, scope, payload), member.privateKey).toString('base64url');
  }
  async function signedRegistryEvidence(state, record = 'REG-COUNT-01') {
    const {actorId, ...close} = state.priorClose;
    const prior = {kind: 'APPROVED_PRIOR_CLOSE', ...close};
    const window = {openingDigest: digest(prior), movements: state.movements.map(row => ({
      commandId: row.command.command_id, stockRef: row.stock_ref, asset: 'crates',
      direction: row.source_site_id === scope.fromSiteId ? 'ISSUE' : 'RETURN',
      quantity: row.quantity, challan: row.challan.record, line: row.challan.line, sourceSha256: row.challan.sourceSha256
    }))};
    await delay(15);
    const count = {record, at: new Date().toISOString(), windowDigest: digest(window),
      stockRevision: state.revision, crates: 3, trays: 1};
    return {
      opening: {payload: prior, signature: signRole('openingReviewer', prior)},
      window: {payload: window, signature: signRole('challanRegistrar', window)},
      count: {payload: count, counterSignature: signRole('counter', count), witnessSignature: signRole('witness', count)}
    };
  }

  await test('canonical registry requires a scoped pair and approved close and denies API writes', async () => {
    assert.equal((await inspect()).reason, 'W02_CANONICAL_PAIR_REQUIRED');
    assert.equal((await http(restUrl + '/rpc/w02_custody_snapshot_v1', {body: args})).ok, false);
    assert.equal((await http(restUrl + '/rpc/w02_custody_snapshot_v1', {token: foreign, body: args})).ok, false);
    assert.equal((await http(restUrl + '/rpc/w02_custody_snapshot_v1', {token: oneSite, body: args})).ok, false);
    pair = Number(trustedFixtureSql(`INSERT INTO core10.w02_pairs_v1
      (tenant_id,business_id,from_site_id,to_site_id,crate_item_id,tray_item_id)
      VALUES (971,9711,97111,97112,97101,97102) RETURNING id`));
    assert.ok(Number.isSafeInteger(pair) && pair > 0);
    assert.equal((await inspect()).reason, 'W02_APPROVED_PRIOR_CLOSE_REQUIRED');
    assert.equal((await http(restUrl + '/w02_keys_v1', {token: owner, body: {pair_id: pair}})).ok, false);
    assert.equal((await http(restUrl + '/w02_closes_v1', {token: owner, method: 'GET'})).ok, false);
    trustedFixtureSql(`TRUNCATE core10.w02_key_revocations_v1`, /W02_EVIDENCE_IMMUTABLE/);
    trustedFixtureSql(`UPDATE core10.w02_pairs_v1 SET crate_item_id=97102 WHERE id=${pair}`,
      /W02_EVIDENCE_IMMUTABLE/);
  });

  await test('one canonical revision joins approved close, enrolled keys, challan and paired Stock with Audit', async () => {
    openingAt = new Date().toISOString();
    const values = [
      ['witness', custodyActors.witness, historicWitness],
      ...members.map(member => [member.role, member.actor, member.publicKey.export({type: 'spki', format: 'der'}).toString('hex')])
    ].map(([role, actor, hex]) => `(${pair},'${role}','${actor}','${hex}')`).join(',');
    trustedFixtureSql(`
      BEGIN;
      INSERT INTO core10.w02_keys_v1(pair_id,role,actor_id,spki_hex) VALUES ${values};
      WITH opened AS (
        INSERT INTO core10.w02_closes_v1(pair_id,record_ref,approved_by,closed_at,crates,trays,source_sha256)
        VALUES (${pair},'REG-CLOSE-01','${users.owner}','${openingAt}',2,1,'${priorHash}') RETURNING id
      )
      INSERT INTO core10.w02_close_transfers_v1(pair_id,close_id,stock_ref)
      SELECT ${pair},opened.id,t.id FROM opened CROSS JOIN core10.stock_transfers_v1 t WHERE t.business_id=9711;
      COMMIT;`);
    const before = await read();
    assert.equal(before.movements.length, 0);
    assert.equal(before.priorClose.sourceSha256, priorHash);
    const transfer = await move('linked');
    assert.equal((await inspect()).reason, 'W02_CANONICAL_MOVEMENT_EVIDENCE_REQUIRED');
    const unlinked = await read();
    await publishFixtureInTransaction(insertLine(transfer.stock_ref, 'ISSUE'), async () => {
      const during = await read();
      assert.equal(during.revision, unlinked.revision);
      assert.equal(during.movements[0].challan, null);
    });
    const state = await read();
    assert.notEqual(state.revision, before.revision);
    assert.notEqual(state.revision, unlinked.revision);
    assert.equal(state.movements.length, 1);
    assert.equal(state.movements[0].postings.length, 2);
    assert.equal(state.movements[0].stock_ref, transfer.stock_ref);
    trustedFixtureSql(`INSERT INTO core10.w02_close_transfers_v1(pair_id,close_id,stock_ref)
      SELECT ${pair},id,${transfer.stock_ref} FROM core10.w02_closes_v1 WHERE pair_id=${pair}`,
      /W02_CLOSE_COVERAGE_OUTSIDE_PUBLICATION/);
    assert.match(state.movements[0].command.auditDigest, /^[0-9a-f]{64}$/);
    const evidence = await signedRegistryEvidence(state);
    const checked = await inspect({evidence});
    assert.equal(checked.canonicalSnapshotVerified, true);
    assert.equal(checked.stockRevision, state.revision);
    assert.equal(checked.canPost, false);
    assert.deepEqual(await inspect({evidence, priorObservation: checked.observation}), checked);
    const forged = structuredClone(evidence);
    forged.opening.payload.record = 'REG-OTHER-CLOSE';
    await assert.rejects(inspect({evidence: forged}), {code: 'W02_CANONICAL_PRIOR_CLOSE_MISMATCH'});
  });

  await test('effective Control revisions invalidate custody replay and mid-read policy changes fail closed', async () => {
    const state = await read();
    const evidence = await signedRegistryEvidence(state);
    const postedBefore = await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711});
    const first = await inspect({evidence});
    assert.equal(first.canonicalSnapshotVerified, true);
    assert.equal(first.canPost, false);
    const site = {p_business: 9711, p_site: 97111};
    const selected = () => rpc(owner, 'control_read_v1', site)
      .then(rows => rows.find(row => row.feature_key === 'inventory.transfer'));
    const setPolicy = (row, stages, key) => rpc(owner, 'control_set_v1', {
      ...site, p_feature: 'inventory.transfer', p_enabled: true, p_stages: stages,
      p_params: {...row.params, allow_cross_site: true}, p_effective_from: null,
      p_inherit: false, p_expected_version: row.version,
      p_reason: 'W02 isolated replay policy test', p_request_key: key
    });

    const initial = await selected();
    assert.equal(initial.stages, 0);
    await setPolicy(initial, 1, 'w02-policy-race-open');
    // The Stock ledger and W02 custody registry are unchanged, only Control.
    assert.equal((await read()).revision, state.revision);
    const stale = await inspect({evidence, priorObservation: first.observation});
    assert.equal(stale.status, 'HOLD');
    assert.equal(stale.reason, 'W02_STALE_OR_SCOPE_MISMATCHED_OBSERVATION');
    assert.equal(stale.observation, null);
    const afterStage = await selected();
    assert.equal(afterStage.stages, 1);

    // Deterministically change Control AFTER the first W02 snapshot is read.
    // Existing Stock-revision-only code would wrongly accept this review.
    const nativeFetch = globalThis.fetch;
    let changedAfterSnapshot = false;
    globalThis.fetch = async (...arguments_) => {
      const response = await nativeFetch(...arguments_);
      if (!changedAfterSnapshot && arguments_[0] === restUrl + '/rpc/w02_custody_snapshot_v1') {
        changedAfterSnapshot = true;
        await setPolicy(afterStage, 0, 'w02-policy-race-close');
      }
      return response;
    };
    try {
      const raced = await inspect({evidence});
      assert.equal(changedAfterSnapshot, true);
      assert.equal(raced.status, 'HOLD');
      assert.equal(raced.reason, 'W02_CONTROL_OBSERVATION_CHANGED');
      assert.equal(raced.canPost, false);
      assert.equal(raced.observation, null);
    } finally {
      globalThis.fetch = nativeFetch;
    }
    assert.equal((await selected()).stages, 0);
    assert.equal((await read()).revision, state.revision);
    assert.deepEqual(await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711}), postedBefore);
    const fresh = await inspect({evidence});
    assert.equal(fresh.canonicalSnapshotVerified, true);
    assert.equal(fresh.canPost, false);
  });

  await test('private publication is atomic with immutable coverage and Audit, and retries replay the receipt', async () => {
    const state = await read();
    const evidence = await signedRegistryEvidence(state);
    const reviewed = await inspect({evidence});
    const requestKey = 'w02-fixture-close-publication';
    const input = {...selection, accessToken: owner, requestKey, priorObservation: reviewed.observation, evidence};
    const rpcName = '_w02_publish_verified_close_v1';
    for (const token of [owner, oneSite, null]) {
      assert.equal((await http(restUrl + '/rpc/' + rpcName,
        {token, body: {...args, p_request: requestKey, p_evidence: evidence, p_verification: null}})).ok, false);
    }
    const role = 'core10_w02_pub_' + process.env.PGDATABASE.split('_').at(-1);
    trustedFixtureSql(`CREATE ROLE ${role} NOLOGIN;
      GRANT USAGE ON SCHEMA core10 TO ${role};
      GRANT EXECUTE ON FUNCTION core10.${rpcName}(bigint,bigint,bigint,text,jsonb,jsonb) TO ${role}`);
    const sqlJson = value => `convert_from(decode('${Buffer.from(JSON.stringify(value)).toString('hex')}','hex'),'UTF8')::jsonb`;
    const key = (value) => `convert_from(decode('${Buffer.from(value).toString('hex')}','hex'),'UTF8')`;
    let beforeWrite;
    const persist = async ({accessToken, businessId, fromSiteId, toSiteId, requestKey: req, evidence: body, verification}) => {
      const user = ok(await http(authUrl + '/user', {token: accessToken, method: 'GET'}), 'Authenticate publisher');
      const claims = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64url'));
      assert.equal(claims.sub, user.id);
      for (const id of [claims.sub, claims.session_id]) assert.match(id, /^[0-9a-f-]{36}$/);
      if (verification && beforeWrite) await beforeWrite();
      const saved = trustedFixtureSql(`BEGIN; SET LOCAL ROLE ${role};
        SET LOCAL request.jwt.claims = '${JSON.stringify({sub: claims.sub, session_id: claims.session_id})}';
        SELECT core10.${rpcName}(${businessId},${fromSiteId},${toSiteId},${key(req)},
             ${sqlJson(body)},${verification ? sqlJson(verification) : 'NULL'}); COMMIT;`);
      return saved ? JSON.parse(saved) : null;
    };
    const publish = createW02ClosePublisher({authUrl, restUrl, persist});
    try {
      await assert.rejects(publish({...input, accessToken: foreign}), /W02_PUBLISH_SCOPE_DENIED/);
      const forged = structuredClone(evidence);
      forged.count.witnessSignature = forged.count.counterSignature;
      await assert.rejects(publish({...input, evidence: forged}), /W02_EVIDENCE_SIGNATURE_INVALID/);
      await publishFixtureInTransaction('LOCK TABLE core10.stock_transfers_v1 IN ROW EXCLUSIVE MODE', async () => {
        await assert.rejects(publish(input), /W02_PUBLICATION_RETRY/);
      });
      const changePolicy = async () => {
        const scope = {p_business: 9711, p_site: 97111};
        const policy = (await rpc(owner, 'control_read_v1', scope)).find(row => row.feature_key === 'inventory.transfer');
        await rpc(owner, 'control_set_v1', {...scope, p_feature: 'inventory.transfer', p_enabled: true,
          p_stages: policy.stages, p_params: {...policy.params, max_qty: policy.params.max_qty - 1},
          p_effective_from: null, p_inherit: false, p_expected_version: policy.version,
          p_reason: 'W02 isolated publication policy race', p_request_key: 'w02-publication-policy-race'});
      };
      beforeWrite = changePolicy;
      await assert.rejects(publish(input), /W02_STALE_CONTROL_POLICY/);
      const afterPolicy = await inspect({evidence});
      beforeWrite = async () => {
        trustedFixtureSql(insertLine((await move('publication-race-out')).stock_ref, 'PUBLICATION-RACE-OUT'));
        trustedFixtureSql(insertLine((await move('publication-race-return', true)).stock_ref, 'PUBLICATION-RACE-RETURN'));
      };
      await assert.rejects(publish({...input, priorObservation: afterPolicy.observation}), /W02_STALE_CANONICAL_REVISION/);
      beforeWrite = null;
      assert.equal(trustedFixtureSql('SELECT count(*) FROM core10.w02_close_publications_v1'), '0');
      const freshEvidence = await signedRegistryEvidence(await read());
      const fresh = await inspect({evidence: freshEvidence});
      const ready = {...input, evidence: freshEvidence, priorObservation: fresh.observation};
      const stockBefore = await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711});
      trustedFixtureSql(`CREATE FUNCTION core10.w02_fixture_fail_save_v1() RETURNS trigger
        LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'W02_FIXTURE_SAVE_FAILED'; END $$;
        CREATE TRIGGER w02_fixture_fail_save BEFORE INSERT ON core10.w02_close_publications_v1
        FOR EACH ROW EXECUTE FUNCTION core10.w02_fixture_fail_save_v1()`);
      try {
        await assert.rejects(publish(ready), /W02_FIXTURE_SAVE_FAILED/);
        assert.equal((await read()).revision, fresh.stockRevision);
        assert.equal(trustedFixtureSql(`SELECT count(*) FROM core10.canonical_audit_events_v1
          WHERE action='w02.close_published'`), '0');
      } finally {
        trustedFixtureSql(`DROP TRIGGER w02_fixture_fail_save ON core10.w02_close_publications_v1;
          DROP FUNCTION core10.w02_fixture_fail_save_v1()`);
      }
      const committed = await publish(ready);
      assert.equal(committed.status, 'EVIDENCE_PUBLISHED');
      assert.equal(committed.canPost, false);
      assert.equal(committed.replayed, false);
      const replay = await publish(ready);
      assert.deepEqual(replay, {...committed, replayed: true});
      await assert.rejects(publish({...ready, evidence: forged}), /W02_PUBLICATION_REPLAY_CONFLICT/);
      assert.equal(trustedFixtureSql('SELECT count(*) FROM core10.w02_close_publications_v1'), '1');
      assert.equal(trustedFixtureSql(`SELECT count(*) FROM core10.canonical_audit_events_v1
        WHERE action='w02.close_published' AND id=${committed.auditEventId}`), '1');
      const closed = await read();
      assert.equal(closed.priorClose.record, evidence.count.payload.record);
      assert.equal(closed.movements.length, 0);
      assert.notEqual(closed.revision, state.revision);
      assert.deepEqual(await rpc(owner, 'inventory_list_commands_v1', {p_business: 9711}), stockBefore);
    } finally {
      trustedFixtureSql(`DROP OWNED BY ${role}; DROP ROLE ${role}`);
    }
  });

  await test('net-zero later Stock changes revision and revoking the current witness key never falls back', async () => {
    const old = await read(), evidence = await signedRegistryEvidence(old, 'REG-COUNT-02');
    trustedFixtureSql(insertLine((await move('late-out')).stock_ref, 'LATE-OUT'));
    trustedFixtureSql(insertLine((await move('late-return', true)).stock_ref, 'LATE-RETURN'));
    const newest = await read();
    assert.notEqual(newest.revision, old.revision);
    assert.equal(newest.movements.length, old.movements.length + 2);
    await assert.rejects(inspect({evidence}), {code: 'W02_STALE_CANONICAL_REVISION'});
    trustedFixtureSql(`INSERT INTO core10.w02_key_revocations_v1(key_id)
      SELECT max(id) FROM core10.w02_keys_v1 WHERE pair_id=${pair} AND role='witness'`);
    const revoked = await read();
    assert.notEqual(revoked.revision, newest.revision);
    assert.equal(revoked.keys.witness, undefined);
    assert.equal((await inspect()).reason, 'W02_CANONICAL_SIGNER_REQUIRED');
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
  await proveCanonicalRegistry(owner, foreign, oneSite);

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
