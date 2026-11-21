// Read-only review Worker runtime (appended to the generated FILES table by build.mjs).
// No bindings, no secrets, no outbound fetch. Only GET/HEAD of the embedded files.
const CSP = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; " +
  "connect-src 'none'; frame-src 'none'; worker-src 'none'; manifest-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
// The existing NP01 offline reviewer preview mounts itself from an inline module script (unchanged source).
const INLINE_SCRIPT_OK = new Set(["/live/docs/preview/c10-np01-canonical-reviewer-preview.html"]);
const SECURITY = {
  "x-content-type-options": "nosniff", "referrer-policy": "no-referrer", "x-frame-options": "DENY",
  "x-robots-tag": "noindex, nofollow", "cross-origin-opener-policy": "same-origin", "cross-origin-resource-policy": "same-origin",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
  "strict-transport-security": "max-age=31536000", "x-core10-review": "read-only; source=" + PIN,
};
const decoded = new Map();
function bytes(route) {
  if (!decoded.has(route)) {
    const bin = atob(FILES[route][1]); const u = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    decoded.set(route, u);
  }
  return decoded.get(route);
}
function respond(status, body, type, route) {
  const csp = INLINE_SCRIPT_OK.has(route) ? CSP.replace("script-src 'self'", "script-src 'self' 'unsafe-inline'") : CSP;
  return new Response(body, { status, headers: { "content-type": type, "content-security-policy": csp, "cache-control": "no-store", ...SECURITY } });
}
export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method !== "GET" && request.method !== "HEAD") {
      const r = respond(405, "READ_ONLY_REVIEW: no writes are possible on this preview.\n", "text/plain; charset=utf-8", "");
      r.headers.set("allow", "GET, HEAD");
      return r;
    }
    const route = url.pathname === "/" ? "/index.html" : url.pathname;
    if (!Object.prototype.hasOwnProperty.call(FILES, route)) return respond(404, "NOT_IN_REVIEW_PACKAGE\n", "text/plain; charset=utf-8", route);
    return respond(200, request.method === "HEAD" ? null : bytes(route), FILES[route][0], route);
  },
};
