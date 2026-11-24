'use strict';

const {createW02StockReview} = require('./w02-canonical-stock-review.cjs');

function fail(code) {
  throw Object.assign(new Error(code), {code});
}

function checkedReceipt(result) {
  if (result?.status !== 'EVIDENCE_PUBLISHED' || result.canPost !== false ||
      !Number.isSafeInteger(result.receiptId) || result.receiptId <= 0 ||
      !Number.isSafeInteger(result.auditEventId) || result.auditEventId <= 0 ||
      typeof result.closeRecord !== 'string' || typeof result.replayed !== 'boolean' ||
      !/^[0-9a-f]{64}$/.test(result.stockRevision)) fail('W02_INVALID_PUBLICATION_RECEIPT');
  return Object.freeze(result);
}

// Server-only contract: persist must independently resolve the fixed bearer
// via GoTrue, set validated actor claims in a private DB transaction and call
// _w02_publish_verified_close_v1. A null verification can only read a receipt.
function createW02ClosePublisher({authUrl, restUrl, persist} = {}) {
  if (typeof persist !== 'function') fail('W02_TRUSTED_PUBLICATION_PORT_REQUIRED');
  const review = createW02StockReview({authUrl, restUrl, canonicalRegistry: true});

  return async function publish({accessToken, businessId, fromSiteId, toSiteId, requestKey, priorObservation, evidence} = {}) {
    if (typeof accessToken !== 'string' || accessToken.length > 8192 ||
        !/^[\w-]+\.[\w-]+\.[\w-]+$/.test(accessToken)) fail('W02_SIGNED_SESSION_REQUIRED');
    if (![businessId, fromSiteId, toSiteId].every(id => Number.isSafeInteger(id) && id > 0) ||
        fromSiteId === toSiteId || typeof requestKey !== 'string' || !/^[A-Za-z0-9_-]{8,100}$/.test(requestKey) ||
        typeof priorObservation !== 'string' || !/^[0-9a-f]{64}$/.test(priorObservation) ||
        !evidence || Object.getPrototypeOf(evidence) !== Object.prototype ||
        Buffer.byteLength(JSON.stringify(evidence)) > 262144) fail('W02_INVALID_PUBLICATION');
    const payload = structuredClone(evidence);
    const selection = {accessToken, businessId, fromSiteId, toSiteId};
    const transact = verification => persist({...selection, requestKey, evidence: payload, verification});
    const saved = await transact(null);
    if (saved !== null) return checkedReceipt(saved);

    let verified;
    try {
      verified = await review({...selection, priorObservation, evidence: payload});
    } catch (error) {
      const replay = await transact(null);
      if (replay !== null) return checkedReceipt(replay);
      throw error;
    }
    if (verified.canonicalSnapshotVerified !== true || verified.custodyEvidenceVerified !== true) {
      const replay = await transact(null);
      if (replay !== null) return checkedReceipt(replay);
      fail(verified.reason);
    }

    const {stockRevision, controlEvidence, evidenceDigest} = verified;
    return checkedReceipt(await transact({stockRevision, controlEvidence, evidenceDigest}));
  };
}

module.exports = {createW02ClosePublisher};
