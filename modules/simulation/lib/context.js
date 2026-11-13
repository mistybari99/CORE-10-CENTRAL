"use strict";
/* Scope + permission layer. DENY BY DEFAULT. Caller-submitted tenant/business/site NEVER authorizes itself.
   MockAuthority stands in for canonical A018/A021/A034 grants and is NOT signed Supabase GoTrue auth. */
const { SimError } = require("./decimal");
const CAPS = ["sim.read", "sim.run", "sim.write", "sim.review", "sim.export", "sim.export_full", "sim.propose", "sim.share", "sim.comment", "sim.template_author", "sim.read_shared"];
class MockAuthority {
  constructor(spec) { this.users = new Map(); this.sessions = new Map(); this.tenants = new Map(); this.businesses = new Map(); this.sites = new Map(); this.grants = [];
    for (const t of spec.tenants) this.tenants.set(t.id, t); for (const b of spec.businesses) this.businesses.set(b.id, b); for (const s of spec.sites) this.sites.set(s.id, s); for (const u of spec.users) this.users.set(u.id, u); for (const g of spec.grants) this.addGrant(g); }
  addGrant(g) { for (const c of g.caps) if (!CAPS.includes(c)) throw new SimError("BAD_CAP", c); this.grants.push(Object.assign({ revoked: false, tenantId: null, businessId: null, siteId: null }, g)); }
  revokeAll(userId) { for (const g of this.grants) if (g.userId === userId) g.revoked = true; }
  login(userId) { if (!this.users.has(userId)) return null; const s = { token: "mock-session-" + userId + "-" + this.sessions.size, userId, mock: true, notSignedAuth: true }; this.sessions.set(s.token, s); return Object.freeze(Object.assign({}, s)); }
  userOf(session) { if (!session || !this.sessions.has(session.token)) throw new SimError("UNAUTHENTICATED", "No valid session"); return this.users.get(this.sessions.get(session.token).userId); }
  /* does the CURRENT (live, revocation-aware) grant set allow cap on target? target must name a real tenant/business/site; tenant is DERIVED, never trusted */
  can(session, cap, target) {
    const user = this.userOf(session); const b = target.businessId ? this.businesses.get(target.businessId) : null; if (target.businessId && !b) return false;
    const tenantId = b ? b.tenantId : target.tenantId; if (target.siteId) { const s = this.sites.get(target.siteId); if (!s || (b && s.businessId !== b.id)) return false; }
    for (const g of this.grants) { if (g.userId !== user.id || g.revoked || !g.caps.includes(cap)) continue; if (g.tenantId && g.tenantId !== tenantId) continue; if (g.businessId && g.businessId !== target.businessId) continue;
      if (g.siteId && g.siteId !== (target.siteId || null)) continue; return true; }
    return false;
  }
  require(session, cap, target) { if (!this.can(session, cap, target)) throw new SimError("FORBIDDEN", "Not permitted: " + cap, { cap }); }
  tenantOfBusiness(businessId) { const b = this.businesses.get(businessId); if (!b) throw new SimError("UNKNOWN_BUSINESS", "Unknown business"); return b.tenantId; }
  /* the ONLY way a ScopeContext is produced: from authority state, then compared with whatever the client claimed */
  resolveContext(session, requested) {
    const user = this.userOf(session); requested = requested || {}; if (!requested.businessId) throw new SimError("SCOPE_REQUIRED", "businessId required");
    const tenantId = this.tenantOfBusiness(requested.businessId);
    if (requested.tenantId && requested.tenantId !== tenantId) throw new SimError("SCOPE_OVERRIDE_REJECTED", "Client-submitted tenant does not match the business: rejected");
    if (!this.can(session, "sim.read", { businessId: requested.businessId, siteId: requested.siteId || null }) && !this.can(session, "sim.read_shared", { businessId: requested.businessId, siteId: requested.siteId || null })) throw new SimError("FORBIDDEN", "No access to this business/site");
    const caps = CAPS.filter(c => this.can(session, c, { businessId: requested.businessId, siteId: requested.siteId || null }));
    return Object.freeze({ tenantId, businessId: requested.businessId, siteId: requested.siteId || null, userId: user.id, grantedCapabilities: Object.freeze(caps), sourceAuthRef: "MOCK_AUTHORITY_NOT_SIGNED_AUTH" });
  }
}
module.exports = { MockAuthority, CAPS };
