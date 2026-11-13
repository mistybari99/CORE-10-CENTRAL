"use strict";
/* Dependency-free HTTP API over the Gateway. DRAFT: synthetic bearer tokens, localhost use. JSON only, 256 KB body cap, no CORS, no cookies. */
const http = require("http"); const { Gateway, HttpError } = require("./gateway");
const MAX = 256 * 1024;
function readBody(req) { return new Promise((res, rej) => { let n = 0, over = false; const parts = []; req.on("data", c => { n += c.length; if (n > MAX) { over = true; parts.length = 0; } else if (!over) parts.push(c); }); req.on("end", () => { if (over) return rej(new HttpError(413, "PAYLOAD_TOO_LARGE", "body over 256 KB")); if (!n) return res({}); try { const o = JSON.parse(Buffer.concat(parts).toString("utf8")); if (o === null || typeof o !== "object" || Array.isArray(o)) throw 0; res(o); } catch (e) { rej(new HttpError(400, "BAD_JSON", "body must be a JSON object")); } }); req.on("error", rej); }); }
function createServer(opts) {
  const gw = new Gateway(opts);
  return http.createServer(async (req, res) => {
    const send = (st, o, type) => { const body = type ? o : JSON.stringify(o); res.writeHead(st, { "Content-Type": type || "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" }); res.end(body); };
    try {
      const url = new URL(req.url, "http://x"); const parts = url.pathname.split("/").filter(Boolean); if (parts[0] !== "api" || parts[1] !== "scenarios") throw new HttpError(404, "NOT_FOUND", "no such route");
      const sub = gw.authenticate(req.headers.authorization); const m = req.method; const id = parts[2], act = parts[3];
      const body = m === "POST" || m === "PUT" ? await readBody(req) : {};
      if (!id) { if (m === "POST") return send(201, gw.create(sub, body)); if (m === "GET") return send(200, gw.list(sub, url.searchParams.get("businessId"))); throw new HttpError(405, "METHOD", "method not allowed"); }
      if (!act) { if (m === "GET") return send(200, gw.read(sub, id)); if (m === "DELETE") return send(200, gw.archive(sub, id)); throw new HttpError(405, "METHOD", "method not allowed"); }
      if (act === "inputs" && m === "PUT") return send(200, gw.saveInputs(sub, id, body)); if (act === "run" && m === "POST") return send(200, gw.run(sub, id)); if (act === "transition" && m === "POST") return send(200, gw.transition(sub, id, body));
      if (act === "propose" && m === "POST") return send(201, gw.propose(sub, id)); if (act === "apply" && m === "POST") return send(409, gw.applyToLive(sub, id)); if (act === "share" && m === "POST") return send(200, gw.share(sub, id, body)); if (act === "comments" && m === "POST") return send(201, gw.comment(sub, id, body));
      if (act === "export" && m === "GET") { const f = url.searchParams.get("format") === "csv" ? "csv" : "json"; const o = gw.export(sub, id, f); return f === "csv" ? send(200, o.csv, "text/csv; charset=utf-8") : send(200, o); }
      throw new HttpError(404, "NOT_FOUND", "no such route");
    } catch (e) { if (e instanceof HttpError) return send(e.status, { error: e.code, message: e.message }); send(500, { error: "INTERNAL", message: "internal error" }); }
  });
}
module.exports = { createServer };
if (require.main === module) { /* demo launch: synthetic tokens dev-<userId>; refuses to run unless explicitly acknowledged */
  if (process.env.C10_SIM_ACK_SYNTHETIC !== "yes") { console.error("Refusing to start: set C10_SIM_ACK_SYNTHETIC=yes (synthetic tokens, disposable DB only)."); process.exit(2); }
  const users = require("../lib/demo-data").users; const tokens = new Map(users.map(u => ["dev-" + u.id, u.id])); const port = Number(process.env.PORT || 8787);
  createServer({ db: require("./db-psql").makeExecutor(), tokens }).listen(port, "127.0.0.1", () => console.log("C10 simulation gateway (DRAFT, synthetic) on http://127.0.0.1:" + port));
}
