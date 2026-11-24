'use strict';

const {createHash} = require('node:crypto');
const {assertSource} = require('./w02-returnables-reconciliation.cjs');
const {configureCustody} = require('./w02-custody-evidence.cjs');
const {canonical, digest} = require('../../source-port-handoff.cjs');

const FEATURES = ['inventory.stock_event', 'inventory.transfer'];
const PAGE_SIZE = 200;
const MAX_PAGES = 5;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function fail(code) {
  throw Object.assign(new Error(code), {code});
}

function localOrigin(raw) {
  let url;
  try { url = new URL(raw); } catch { fail('W02_LOOPBACK_REQUIRED'); }
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port ||
      url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
    fail('W02_LOOPBACK_REQUIRED');
  }
  return url.origin;
}

function checkedScope(context, actor, business, siteIds) {
  if (context?.real_auth_account_verified !== true || context.actor_uid !== actor ||
      !Array.isArray(context.tenants) || !Array.isArray(context.businesses) || !Array.isArray(context.sites)) {
    fail('W02_SIGNED_CONTEXT_REQUIRED');
  }
  const matches = context.businesses.filter(row => row.id === business);
  const tenant = matches[0]?.tenant_id;
  if (matches.length !== 1 || !Number.isSafeInteger(tenant) || tenant <= 0 ||
      !context.tenants.some(row => row.id === tenant)) fail('W02_SCOPE_DENIED');
  for (const siteId of siteIds) {
    const rows = context.sites.filter(row => row.id === siteId);
    const row = rows[0];
    if (rows.length !== 1 || row.tenant_id !== tenant || row.business_id !== business ||
        !Array.isArray(row.allowed_actions) || !row.allowed_actions.includes('stock.read')) {
      fail('W02_SCOPE_DENIED');
    }
  }
  return tenant;
}

function policyTuple(rows) {
  if (!Array.isArray(rows)) fail('W02_CONTROL_UNAVAILABLE');
  return FEATURES.map(feature => {
    const matches = rows.filter(row => row.feature_key === feature);
    const row = matches[0];
    if (matches.length !== 1 || typeof row.enabled !== 'boolean' || !Number.isSafeInteger(row.version) ||
        row.version < 0 || !Number.isSafeInteger(row.stages) || row.stages < 0 ||
        !['site', 'business', 'default'].includes(row.source)) fail('W02_CONTROL_UNAVAILABLE');
    const crossSite = feature === 'inventory.transfer' ? row.params?.allow_cross_site : null;
    if (feature === 'inventory.transfer' && typeof crossSite !== 'boolean') fail('W02_CONTROL_UNAVAILABLE');
    return [row.enabled, row.source, row.version, row.stages, crossSite];
  });
}

async function readBalances(rpc, business, site) {
  const observations = [];
  let location = null, item = null;
  for (let page = 0; page < MAX_PAGES; page++) {
    const result = await rpc('inventory_list_balances_v1', {
      p_business: business, p_site: site, p_after_location: location, p_after_item: item, p_limit: PAGE_SIZE
    });
    if (result?.business_id !== business || result.limit !== PAGE_SIZE ||
        !Array.isArray(result.items) || result.items.length > PAGE_SIZE) fail('W02_STOCK_SCOPE_MISMATCH');
    for (const row of result.items) {
      if (row.site_id !== site || !Number.isSafeInteger(row.location_id) || row.location_id <= 0 ||
          !Number.isSafeInteger(row.item_id) || row.item_id <= 0) fail('W02_STOCK_SCOPE_MISMATCH');
      if (location !== null && (row.location_id < location || (row.location_id === location && row.item_id <= item)) ||
          typeof row.on_hand !== 'number' || !Number.isFinite(row.on_hand) || row.on_hand < 0 ||
          row.on_hand >= 10 ** 12) fail('W02_STOCK_OBSERVATION_INVALID');
      location = row.location_id;
      item = row.item_id;
      observations.push([location, item, row.on_hand]);
    }
    if (result.next_after === null && result.items.length < PAGE_SIZE) return observations;
    if (!result.next_after || result.items.length !== PAGE_SIZE ||
        result.next_after.location_id !== location || result.next_after.item_id !== item) {
      fail('W02_STOCK_OBSERVATION_INVALID');
    }
  }
  fail('W02_STOCK_OBSERVATION_INCOMPLETE');
}

async function readPostedCommands(rpc, business, site) {
  const commands = [];
  let before = null;
  for (let page = 0; page < MAX_PAGES; page++) {
    const result = await rpc('inventory_list_commands_v1', {
      p_business: business, p_site: site, p_status: 'posted', p_before_id: before, p_limit: PAGE_SIZE
    });
    if (result?.business_id !== business || result.limit !== PAGE_SIZE ||
        !Array.isArray(result.items) || result.items.length > PAGE_SIZE) fail('W02_COMMAND_SCOPE_MISMATCH');
    for (const row of result.items) {
      if (row.business_id !== business || row.status !== 'posted' ||
          ![row.source_site_id, row.destination_site_id].includes(site) ||
          !Number.isSafeInteger(row.command_id) || row.command_id <= 0 ||
          (before !== null && row.command_id >= before)) fail('W02_COMMAND_SCOPE_MISMATCH');
      before = row.command_id;
      const {command_id, kind, source_site_id, destination_site_id, item_id, quantity,
        stock_ref, created_by, confirmed_by, posted_by, posted_at} = row;
      commands.push({command_id, kind, source_site_id, destination_site_id, item_id, quantity,
        stock_ref, created_by, confirmed_by, posted_by, posted_at});
    }
    if (result.next_before_id === null && result.items.length < PAGE_SIZE) return commands;
    if (result.items.length !== PAGE_SIZE || result.next_before_id !== before) fail('W02_COMMAND_SCOPE_MISMATCH');
  }
  fail('W02_COMMAND_WINDOW_INCOMPLETE');
}

async function reviewRegistry({rpc, currentScope, control, policies, scope, actor, evidence, priorObservation, hold}) {
  const read = () => rpc('w02_custody_snapshot_v1', {
    p_business: scope.businessId, p_from_site: scope.fromSiteId, p_to_site: scope.toSiteId
  });
  const state = await read();
  const blocked = {
    CONTROL_DISABLED: 'W02_STOCK_CONTROL_DISABLED',
    PAIR_NOT_CONFIGURED: 'W02_CANONICAL_PAIR_REQUIRED',
    WINDOW_INCOMPLETE: 'W02_COMMAND_WINDOW_INCOMPLETE'
  };
  if (Object.hasOwn(blocked, state?.status)) return hold(blocked[state.status]);
  if (state?.status !== 'SNAPSHOT' || !/^[0-9a-f]{64}$/.test(state.revision) ||
      canonical(state.scope) !== canonical(scope) || !Array.isArray(state.movements)) fail('W02_REGISTRY_SCOPE_MISMATCH');
  if (!state.priorClose) return hold('W02_APPROVED_PRIOR_CLOSE_REQUIRED');
  const roles = ['openingReviewer', 'challanRegistrar', 'counter', 'witness'];
  if (roles.some(role => !state.keys?.[role])) return hold('W02_CANONICAL_SIGNER_REQUIRED');
  const signers = Object.fromEntries(roles.map(role => {
    const {actorId, spkiHex} = state.keys[role];
    if (!/^302a300506032b6570032100[0-9a-f]{64}$/.test(spkiHex)) fail('W02_CANONICAL_SIGNER_INVALID');
    const pem = Buffer.from(spkiHex, 'hex').toString('base64');
    return [role, {actorId, publicKey: '-----BEGIN PUBLIC KEY-----\n' + pem + '\n-----END PUBLIC KEY-----'}];
  }));
  if (state.movements.some(row => !row.command?.auditDigest || row.postings?.length !== 2 || !row.challan)) {
    return hold('W02_CANONICAL_MOVEMENT_EVIDENCE_REQUIRED');
  }
  // V2 includes both sites' effective Control versions and stages. A Stock-only
  // fingerprint would silently permit old read replay after Owner policy changes.
  const observation = digest(['CORE10.W02.REGISTRY.V2', actor, scope, state.revision, policies]);
  if (priorObservation !== undefined && priorObservation !== observation) {
    return hold('W02_STALE_OR_SCOPE_MISMATCHED_OBSERVATION');
  }
  let linked;
  if (evidence !== undefined) {
    const {actorId, ...record} = state.priorClose;
    if (actorId !== signers.openingReviewer.actorId || !evidence?.opening?.payload ||
        canonical(evidence.opening.payload) !== canonical({kind: 'APPROVED_PRIOR_CLOSE', ...record})) {
      fail('W02_CANONICAL_PRIOR_CLOSE_MISMATCH');
    }
    const prepare = configureCustody({scope, items: state.items, signers, stockRevision: state.revision});
    const commands = state.movements.map(row => ({...row, ...row.command, kind: 'transfer'}));
    linked = prepare(evidence, scope)(commands);
  }
  if ((await read())?.revision !== state.revision || await currentScope() !== scope.tenantId) {
    return hold('W02_STOCK_OBSERVATION_CHANGED');
  }
  // The read-only review must also recheck effective policy after the
  // potentially lengthy custody signature and movement reconciliation.
  if (canonical(await control()) !== canonical(policies)) {
    return hold('W02_CONTROL_OBSERVATION_CHANGED');
  }
  const revision = {observation, stockRevision: state.revision};
  return Object.freeze(linked ? {...hold('W02_VERIFIED_POSTING_DISABLED'), ...revision,
    custodyEvidenceVerified: true, canonicalSnapshotVerified: true, controlEvidence: policies, ...linked}
    : {...hold('W02_SIGNED_COUNT_REQUIRED'), ...revision});
}

// Local rehearsal over existing GoTrue and canonical PostgREST reads. The bearer
// stays fixed for the whole request, and no stock quantities are returned.
function createW02StockReview({authUrl, restUrl, custody, canonicalRegistry = false} = {}) {
  const auth = localOrigin(authUrl), rest = localOrigin(restUrl);
  const sourceFieldIDs = assertSource().fields;
  if (canonicalRegistry && custody !== undefined) fail('W02_AMBIGUOUS_CUSTODY_PROVIDER');
  const prepareEvidence = custody === undefined ? null : configureCustody(custody);
  return async function review({accessToken, businessId, fromSiteId, toSiteId, priorObservation, evidence} = {}) {
    if (![businessId, fromSiteId, toSiteId].every(id => Number.isSafeInteger(id) && id > 0) ||
        fromSiteId === toSiteId || priorObservation !== undefined &&
        (typeof priorObservation !== 'string' || !/^[0-9a-f]{64}$/.test(priorObservation))) {
      fail('W02_INVALID_SELECTION');
    }
    if (typeof accessToken !== 'string' || accessToken.length > 8192 ||
        !/^[\w-]+\.[\w-]+\.[\w-]+$/.test(accessToken)) fail('W02_SIGNED_SESSION_REQUIRED');

    const request = async (url, code, body) => {
      try {
        const headers = {Authorization: 'Bearer ' + accessToken, Accept: 'application/json'};
        if (body) {
          headers['Content-Type'] = 'application/json';
          headers['Content-Profile'] = 'core10';
        }
        const response = await fetch(url, {
          headers, method: body ? 'POST' : 'GET', body: body ? JSON.stringify(body) : undefined,
          redirect: 'error', signal: AbortSignal.timeout(5000)
        });
        if (response.ok) return await response.json();
      } catch {
        // Transport, invalid response and authorization errors all fail closed.
      }
      fail(code);
    };
    const user = await request(auth + '/user', 'W02_SIGNED_SESSION_REQUIRED');
    if (typeof user?.id !== 'string' || !UUID.test(user.id)) fail('W02_SIGNED_SESSION_REQUIRED');
    const rpc = (name, args) => request(rest + '/rpc/' + name, 'W02_CANONICAL_READ_DENIED', args);
    const sites = [fromSiteId, toSiteId];
    const currentScope = async () => checkedScope(await rpc('build01_context_v1', {}), user.id, businessId, sites);
    const tenant = await currentScope();
    const control = async () => Promise.all(sites.map(site => rpc('control_read_v1', {
      p_business: businessId, p_site: site
    }).then(policyTuple)));
    const policies = await control();
    const hold = reason => Object.freeze({
      status: 'HOLD', reason, sourceFieldIDs, observation: null,
      signedMovementSnapshotVerified: false, canPost: false
    });
    if (policies.some(([stock, transfer]) => !stock[0] || !transfer[0] || !transfer[4])) {
      return hold('W02_STOCK_CONTROL_DISABLED');
    }

    if (canonicalRegistry) return reviewRegistry({
      rpc, currentScope, control, policies, actor: user.id, scope: {tenantId: tenant, businessId, fromSiteId, toSiteId},
      evidence, priorObservation, hold
    });
    if (evidence !== undefined && !prepareEvidence) fail('W02_CUSTODY_PROVIDER_REQUIRED');
    if (prepareEvidence && !evidence?.opening) return hold('W02_APPROVED_PRIOR_CLOSE_REQUIRED');
    const matchStock = prepareEvidence?.(evidence, {tenantId: tenant, businessId, fromSiteId, toSiteId});
    const readStock = async () => {
      const balances = await Promise.all(sites.map(site => readBalances(rpc, businessId, site)));
      const commands = matchStock ? await readPostedCommands(rpc, businessId, fromSiteId) : [];
      return {balances, commands};
    };
    const observed = await readStock();
    // A repeated read detects changes during the observation. Existing reads do
    // not provide a joint ledger revision or challan; the result remains HOLD.
    const confirmed = await readStock();
    const confirmedPolicies = await control();
    if (await currentScope() !== tenant) fail('W02_SCOPE_DENIED');
    if (JSON.stringify(observed) !== JSON.stringify(confirmed) || JSON.stringify(policies) !== JSON.stringify(confirmedPolicies)) {
      return hold('W02_STOCK_OBSERVATION_CHANGED');
    }
    const linked = matchStock?.(confirmed.commands);
    const material = [user.id, tenant, businessId, sites, policies, JSON.stringify(confirmed.balances)];
    if (linked) material.push(confirmed.commands, linked);
    const observation = createHash('sha256').update(JSON.stringify(material)).digest('hex');
    if (priorObservation !== undefined && priorObservation !== observation) {
      return hold('W02_STALE_OR_SCOPE_MISMATCHED_OBSERVATION');
    }
    if (linked) return Object.freeze({...hold('W02_CANONICAL_CUSTODY_PROVIDER_REQUIRED'),
      observation, custodyEvidenceVerified: true, evidenceDigest: linked.evidenceDigest,
      matchedMovements: linked.matchedMovements});
    return Object.freeze({...hold('W02_SIGNED_MOVEMENT_AND_CARRY_FORWARD_REQUIRED'), observation});
  };
}

module.exports = {createW02StockReview};
