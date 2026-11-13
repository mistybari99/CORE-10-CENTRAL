// Serve the verified Pages artifact, never the repository checkout.
// Usage: PORT=8099 node tests/e2e/static_server.js
// Optional FAIL=<substring>: respond HTTP 500 for any path containing it (negative control).
const http = require('http'), fs = require('fs'), path = require('path');
const os = require('os');
const packaging = require('../../internal/core10-pages-package');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.svg': 'image/svg+xml', '.webp': 'image/webp',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.ico': 'image/x-icon', '.txt': 'text/plain' };
function createServer() {
  const temporary = process.env.CORE10_STATIC_ROOT ? null : fs.mkdtempSync(path.join(os.tmpdir(), 'core10-served-'));
  const root = process.env.CORE10_STATIC_ROOT ? path.resolve(process.env.CORE10_STATIC_ROOT) : path.join(temporary, 'public');
  if (temporary) packaging.build(path.resolve(__dirname, '..', '..'), root);
  else packaging.verify(root);
  const fail = process.env.FAIL || '';
  const server = http.createServer((req, res) => {
    let p;
    try { p = decodeURIComponent(new URL(req.url, 'http://x').pathname); } catch (e) { res.writeHead(400); return res.end(); }
    if (fail && p.includes(fail)) { res.writeHead(500); return res.end('forced failure'); }
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(root, p);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
    // Check each request as well: a post-verification injection must not be served.
    const relative = path.relative(root, file).split(path.sep).join('/');
    if (!packaging.isAllowed(relative)) { res.writeHead(404); return res.end('not found'); }
    try {
      if (fs.realpathSync(file) !== file) { res.writeHead(404); return res.end('not found'); }
    } catch { res.writeHead(404); return res.end('not found'); }
    fs.readFile(file, (err, buf) => {
      if (err) { res.writeHead(404); return res.end('not found'); }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(buf);
    });
  });
  server.once('close', () => { if (temporary) fs.rmSync(temporary, {recursive:true, force:true}); });
  return server;
}
module.exports = { createServer };
if (require.main === module) {
  const port = Number(process.env.PORT || 8099);
  createServer().listen(port, '127.0.0.1', () => console.log('static server on http://127.0.0.1:' + port));
}
