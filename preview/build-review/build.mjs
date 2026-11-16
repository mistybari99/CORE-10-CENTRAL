// CORE10 build review: deterministic bundler for the read-only Cloudflare review Worker.
// Every /live/ file is the exact git blob of the pinned trunk commit (SOURCE_DRIFT otherwise).
// Output: preview/build-review/dist/worker.mjs (not committed) and SOURCE_MANIFEST.json (committed).
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
export const PIN = "fe1c6b676a25156dfac15ff79538a99bfb7218ff"; // ccr-15ed11dd-n3hw5h trunk HEAD

// Actual frontend source served unchanged under /live/<path>.
export const LIVE = [
  // B-021 Owner Control Centre (real page; its shipped config has an empty key -> NOT_CONNECTED)
  "core10-owner-control-centre.html", "core10-owner-control-centre.css", "core10-owner-control-centre.js",
  "core10-owner-control-centre-ui.js", "core10-owner-control-client.js", "core10-control-centre-config.js",
  // Build 01 setup and access (real page; shipped config enabled:false -> locked)
  "core10-build01.html", "core10-build01.css", "core10-build01.js", "core10-build01-client.js",
  "core10-build01-config.js", "core10-build01-pack02.js", "core10-enterprise-client.js", "core10-control-studio.css",
  "vendor/supabase.js",
  // PACK-02 workspace renderers (driven by verbatim test fixtures, see /pack02.html)
  "core10-pack02-workspace.js", "core10-pack02-workspace.css", "core10-pack02-controls.js",
  // NP01 canonical Approval reviewer: existing offline synthetic preview + its real UI modules
  "docs/preview/c10-np01-canonical-reviewer-preview.html",
  "internal/enterprise-client/c10_np01_reviewer_workspace_v1.mjs",
  "internal/enterprise-client/c10_np01_reviewer_workspace_v1.css",
  "internal/enterprise-client/c10_np01_canonical_review_client_v1.mjs",
];
export const FIXTURES = ["universal-owner", "business-owner", "business-owner-branded", "staff", "controls-central", "controls-business"];
// Listed for traceability only, never served (legacy BOS dependency / test-only).
export const EVIDENCE_ONLY = ["owner.html", "index.html", "core10-shell.js", "core10-owner.css", "core10-home.js",
  "core10-owner-business-entry.js", "core10-owner-inbox.js", "core10-control-studio-entry.js",
  "core10-pack02-signed.js", "core10-pack02-app.js",
  "tests/control-centre/owner-control-centre-browser.cjs", "tests/control-centre/seed.sql",
  "tests/pack02/workspace-browser.cjs", "tests/e2e/core10-build01-live-browser.cjs",
  "tests/e2e/core10-build01-locked-browser.cjs", "tests/migrations/np02-master-tables-e2e.sql"];
// Must never be reachable from the Worker.
export const FORBIDDEN = ["config.js", "tests/control-centre/sql-gateway.cjs", "tests/control-centre/harness.js",
  "tests/control-centre/harness.html"];

const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8", ".png": "image/png", ".svg": "image/svg+xml",
  ".md": "text/markdown; charset=utf-8" };
const git = (...a) => execFileSync("git", a, { cwd: ROOT, encoding: "utf8" }).trim();
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");
const blobAtPin = (p) => git("rev-parse", `${PIN}:${p}`);
function pinned(p) {
  const buf = Buffer.from(execFileSync("git", ["cat-file", "blob", blobAtPin(p)], { cwd: ROOT }));
  const disk = fs.existsSync(path.join(ROOT, p)) ? fs.readFileSync(path.join(ROOT, p)) : null;
  if (!disk || !disk.equals(buf)) throw new Error("SOURCE_DRIFT " + p + " differs from " + PIN);
  return buf;
}

export function build() {
  const files = {}, manifest = [];
  const add = (route, buf, entry) => {
    files[route] = [TYPES[path.extname(route)] || "application/octet-stream", buf.toString("base64")];
    manifest.push({ route, bytes: buf.length, sha256: sha256(buf), ...entry });
  };
  for (const p of LIVE) add("/live/" + p, pinned(p), { kind: "ACTUAL_SOURCE", source: p, git_blob: blobAtPin(p) });
  const fx = {};
  for (const n of FIXTURES) {
    const p = `tests/pack02/fixtures/${n}.json`;
    fx[n] = JSON.parse(pinned(p).toString("utf8"));
    manifest.push({ route: "(embedded in /pack02-fixtures.js)", kind: "VERBATIM_TEST_FIXTURE", source: p, git_blob: blobAtPin(p) });
  }
  add("/pack02-fixtures.js", Buffer.from("/* Generated: verbatim tests/pack02/fixtures/*.json @ " + PIN + " (synthetic). */\nwindow.CORE10_REVIEW_FIXTURES=" + JSON.stringify(fx) + ";\n"),
    { kind: "REVIEW_GENERATED", source: "preview/build-review/build.mjs" });
  for (const n of fs.readdirSync(path.join(HERE, "site")).sort()) {
    const route = n === "index.html" ? "/index.html" : "/" + n;
    add(route, fs.readFileSync(path.join(HERE, "site", n)), { kind: "REVIEW_UI", source: "preview/build-review/site/" + n });
  }
  for (const n of fs.readdirSync(path.join(HERE, "evidence")).sort())
    add("/evidence/" + n, fs.readFileSync(path.join(HERE, "evidence", n)), { kind: "TEST_SCREENSHOT", source: "preview/build-review/evidence/" + n });
  for (const p of EVIDENCE_ONLY) manifest.push({ route: null, kind: "EVIDENCE_ONLY_NOT_SERVED", source: p, git_blob: blobAtPin(p) });
  const pub = Buffer.from(JSON.stringify({ pin: PIN, note: "Read-only review. ACTUAL_SOURCE rows equal the git blob at pin.", files: manifest }, null, 1));
  files["/manifest.json"] = [TYPES[".json"], pub.toString("base64")];
  for (const f of FORBIDDEN) if (Object.keys(files).some((r) => r.endsWith("/" + f))) throw new Error("FORBIDDEN_FILE " + f);

  const runtime = fs.readFileSync(path.join(HERE, "worker-runtime.mjs"), "utf8");
  const worker = "// GENERATED by preview/build-review/build.mjs from trunk " + PIN + ". Do not edit.\nconst PIN=" + JSON.stringify(PIN) +
    ";\nconst FILES=" + JSON.stringify(files) + ";\n" + runtime;
  const out = { pin: PIN, branch_of_source: "ccr-15ed11dd-n3hw5h", worker_sha256: sha256(worker), files: manifest };
  return { worker, manifest: out };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { worker, manifest } = build();
  fs.mkdirSync(path.join(HERE, "dist"), { recursive: true });
  fs.writeFileSync(path.join(HERE, "dist/worker.mjs"), worker);
  fs.writeFileSync(path.join(HERE, "SOURCE_MANIFEST.json"), JSON.stringify(manifest, null, 1) + "\n");
  console.log("worker.mjs " + worker.length + " bytes sha256 " + manifest.worker_sha256 + " · " + manifest.files.length + " manifest rows");
}
