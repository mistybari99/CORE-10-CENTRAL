'use strict';

const {createPublicKey, verify} = require('node:crypto');
const {canonical, digest} = require('../../source-port-handoff.cjs');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const REFERENCE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/;
const ROLES = ['openingReviewer', 'challanRegistrar', 'counter', 'witness'];
const SCOPE_FIELDS = ['tenantId', 'businessId', 'fromSiteId', 'toSiteId'];

function fail(code) {
  throw Object.assign(new Error(code), {code});
}
const positive = value => Number.isSafeInteger(value) && value > 0;
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const reference = value => typeof value === 'string' && REFERENCE.test(value);
const shape = (value, keys) => value && Object.getPrototypeOf(value) === Object.prototype &&
  Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

// Keep the microseconds carried by PostgreSQL. A post at the count cutoff
// cannot be rounded into the preceding stock window.
function instant(value) {
  const match = typeof value === 'string' &&
    /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,6}))?(Z|[+-]\d\d:\d\d)$/.exec(value);
  if (!match) fail('W02_INVALID_EVIDENCE_TIME');
  const seconds = Date.parse(match[1] + match[3]);
  if (!Number.isFinite(seconds) ||
      new Date(match[1] + 'Z').toISOString().slice(0, 19) !== match[1]) fail('W02_INVALID_EVIDENCE_TIME');
  return BigInt(seconds) * 1000n + BigInt((match[2] ?? '').padEnd(6, '0'));
}

function evidenceMessage(role, actorId, scope, payload) {
  return Buffer.from(canonical(['CORE10.W02.CUSTODY.V1', role, actorId, scope, payload]), 'utf8');
}

function configureCustody(configuration) {
  const {scope, items, signers} = configuration ?? {};
  if (!shape(scope, SCOPE_FIELDS) || !SCOPE_FIELDS.every(key => positive(scope[key])) ||
      scope.fromSiteId === scope.toSiteId ||
      !shape(items, ['crates', 'trays']) || !positive(items.crates) || !positive(items.trays) ||
      items.crates === items.trays || !shape(signers, ROLES)) fail('W02_CUSTODY_CONFIGURATION_INVALID');
  const roles = Object.fromEntries(ROLES.map(role => {
    const entry = signers[role];
    if (!shape(entry, ['actorId', 'publicKey']) || !UUID.test(entry.actorId) ||
        typeof entry.publicKey !== 'string' || !entry.publicKey.startsWith('-----BEGIN PUBLIC KEY-----')) {
      fail('W02_CUSTODY_CONFIGURATION_INVALID');
    }
    let publicKey;
    try { publicKey = createPublicKey(entry.publicKey); } catch { fail('W02_CUSTODY_CONFIGURATION_INVALID'); }
    if (publicKey.asymmetricKeyType !== 'ed25519') fail('W02_CUSTODY_CONFIGURATION_INVALID');
    return [role, {actor: entry.actorId.toLowerCase(), publicKey, thumbprint: publicKey.export({type: 'spki', format: 'der'}).toString('hex')}];
  }));
  for (const [a, b] of [['openingReviewer', 'challanRegistrar'], ['counter', 'witness']]) {
    if (roles[a].actor === roles[b].actor || roles[a].thumbprint === roles[b].thumbprint) {
      fail('W02_INDEPENDENT_REVIEW_REQUIRED');
    }
  }
  // One public key cannot impersonate multiple actor IDs across roles.
  for (const left of Object.values(roles)) for (const right of Object.values(roles)) {
    if (left.thumbprint === right.thumbprint && left.actor !== right.actor) fail('W02_CUSTODY_CONFIGURATION_INVALID');
  }
  const expectedScope = canonical(scope);
  const mappedItems = {...items};

  return function prepareEvidence(rawEvidence, context) {
    if (canonical(context) !== expectedScope) fail('W02_CUSTODY_SCOPE_MISMATCH');
    if (!rawEvidence?.opening) fail('W02_APPROVED_PRIOR_CLOSE_REQUIRED');
    const evidence = structuredClone(rawEvidence);
    if (!shape(evidence, ['opening', 'window', 'count'])) fail('W02_INVALID_CUSTODY_EVIDENCE');
    const {opening, window, count} = evidence;
    if (!shape(opening, ['payload', 'signature']) || !shape(opening.payload, ['kind', 'record', 'at', 'crates', 'trays']) ||
        opening.payload.kind !== 'APPROVED_PRIOR_CLOSE' || !reference(opening.payload.record) ||
        !quantity(opening.payload.crates) || !quantity(opening.payload.trays)) fail('W02_APPROVED_PRIOR_CLOSE_REQUIRED');
    if (!shape(window, ['payload', 'signature']) || !shape(window.payload, ['openingDigest', 'movements']) ||
        window.payload.openingDigest !== digest(opening.payload) ||
        !Array.isArray(window.payload.movements) || window.payload.movements.length > 200) fail('W02_INVALID_MOVEMENT_WINDOW');
    if (!shape(count, ['payload', 'counterSignature', 'witnessSignature']) ||
        !shape(count.payload, ['record', 'at', 'windowDigest', 'crates', 'trays']) ||
        !reference(count.payload.record) || count.payload.record === opening.payload.record ||
        !quantity(count.payload.crates) || !quantity(count.payload.trays)) fail('W02_INVALID_WITNESSED_COUNT');
    const openedAt = instant(opening.payload.at), countedAt = instant(count.payload.at);
    if (openedAt >= countedAt || countedAt > BigInt(Date.now()) * 1000n) fail('W02_INVALID_EVIDENCE_TIME');

    const declared = new Map(), stockRefs = new Set(), challanLines = new Set();
    for (const movement of window.payload.movements) {
      if (!shape(movement, ['commandId', 'stockRef', 'asset', 'direction', 'quantity', 'challan', 'line']) ||
          !positive(movement.commandId) || !positive(movement.stockRef) || !positive(movement.quantity) ||
          !['crates', 'trays'].includes(movement.asset) || !['ISSUE', 'RETURN'].includes(movement.direction) ||
          !reference(movement.challan) || !reference(movement.line)) fail('W02_INVALID_MOVEMENT_WINDOW');
      const line = JSON.stringify([movement.challan, movement.line]);
      if (declared.has(movement.commandId) || stockRefs.has(movement.stockRef) || challanLines.has(line)) {
        fail('W02_DUPLICATE_MOVEMENT_OR_CHALLAN_LINE');
      }
      declared.set(movement.commandId, movement);
      stockRefs.add(movement.stockRef);
      challanLines.add(line);
    }
    if (count.payload.windowDigest !== digest(window.payload)) fail('W02_INVALID_WITNESSED_COUNT');
    const checked = [
      ['openingReviewer', opening.payload, opening.signature],
      ['challanRegistrar', window.payload, window.signature],
      ['counter', count.payload, count.counterSignature],
      ['witness', count.payload, count.witnessSignature]
    ];
    for (const [role, payload, signature] of checked) {
      if (typeof signature !== 'string' || !/^[A-Za-z0-9_-]{86}$/.test(signature)) fail('W02_EVIDENCE_SIGNATURE_INVALID');
      const bytes = Buffer.from(signature, 'base64url');
      const {actor, publicKey} = roles[role];
      if (bytes.toString('base64url') !== signature ||
          !verify(null, evidenceMessage(role, actor, context, payload), publicKey, bytes)) {
        fail('W02_EVIDENCE_SIGNATURE_INVALID');
      }
    }

    const net = {crates: BigInt(opening.payload.crates), trays: BigInt(opening.payload.trays)};
    const {fromSiteId, toSiteId} = context;
    function windowRows(commands) {
      const rows = [];
      for (const row of commands) {
        const forward = row.source_site_id === fromSiteId && row.destination_site_id === toSiteId;
        const reverse = row.source_site_id === toSiteId && row.destination_site_id === fromSiteId;
        if (row.kind !== 'transfer' || !forward && !reverse ||
            ![mappedItems.crates, mappedItems.trays].includes(row.item_id)) continue;
        const postedAt = instant(row.posted_at);
        if (postedAt === openedAt || postedAt === countedAt) fail('W02_MOVEMENT_AT_WINDOW_BOUNDARY');
        if (postedAt > openedAt) rows.push([postedAt, row, forward ? 'ISSUE' : 'RETURN']);
      }
      return rows;
    }
    return function matchStock(commands) {
      const rows = windowRows(commands);
      if (rows.some(([time]) => time > countedAt)) fail('W02_COUNT_STALE_NEW_MOVEMENT');
      if (rows.length !== declared.size) fail('W02_MOVEMENT_WINDOW_MISMATCH');
      const balances = {...net};
      rows.sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
      for (const [i, [time, row, direction]] of rows.entries()) {
        if (i > 0 && time === rows[i - 1][0]) fail('W02_MOVEMENT_ORDER_UNCERTAIN');
        const movement = declared.get(row.command_id);
        if (!movement || movement.direction !== direction || movement.stockRef !== row.stock_ref ||
            row.item_id !== mappedItems[movement.asset] || row.quantity !== movement.quantity) {
          fail('W02_MOVEMENT_WINDOW_MISMATCH');
        }
        const commandActors = [row.created_by, row.confirmed_by, row.posted_by];
        if (commandActors.some(actor => typeof actor !== 'string' || !UUID.test(actor))) fail('W02_MOVEMENT_WINDOW_MISMATCH');
        if (commandActors.some(actor => [roles.counter.actor, roles.witness.actor].includes(actor.toLowerCase()))) {
          fail('W02_INDEPENDENT_COUNT_REQUIRED');
        }
        balances[movement.asset] += BigInt(direction === 'ISSUE' ? movement.quantity : -movement.quantity);
        if (balances[movement.asset] < 0n) fail('W02_MOVEMENT_OVER_RETURN');
      }
      if (balances.crates !== BigInt(count.payload.crates) || balances.trays !== BigInt(count.payload.trays)) {
        fail('W02_WITNESSED_COUNT_MISMATCH');
      }
      return {evidenceDigest: digest(['CORE10.W02.CUSTODY.V1', context, count.payload]), matchedMovements: rows.length};
    };
  };
}

module.exports = {configureCustody, evidenceMessage};
