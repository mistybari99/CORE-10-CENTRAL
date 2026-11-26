// Loopback-only host for the generated Worker (same fetch handler Cloudflare runs).
import http from "node:http";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

export async function serve(port = 0) {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const worker = (await import(pathToFileURL(path.join(here, "dist/worker.mjs")).href + "?t=" + Date.now())).default;
  const server = http.createServer(async (req, res) => {
    const chunks = []; for await (const c of req) chunks.push(c);
    const r = await worker.fetch(new Request("http://127.0.0.1" + req.url, { method: req.method, headers: req.headers,
      body: ["GET", "HEAD"].includes(req.method) ? undefined : Buffer.concat(chunks) }));
    res.writeHead(r.status, Object.fromEntries(r.headers));
    res.end(r.body ? Buffer.from(await r.arrayBuffer()) : undefined);
  });
  await new Promise((ok) => server.listen(port, "127.0.0.1", ok));
  return server;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const s = await serve(Number(process.argv[2] || 8799));
  console.log("http://127.0.0.1:" + s.address().port);
}
