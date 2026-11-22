// CORE 10 owner preview for the existing Worker core10-central. Deterministic bundler.
// /live/* = exact git blobs read straight from pinned commits (trunk or a named Draft PR head). Presentation glue lives in site/.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
export const PINS = {
  trunk: { sha: "a82ae99", ref: "ccr-15ed11dd-n3hw5h", status: "TRUNK_INTEGRATED" },
  pr109: { sha: "c7165af", ref: "PR #109 NP03B Sales (Draft)", status: "DRAFT_NOT_INTEGRATED" },
  pr112: { sha: "86851dc", ref: "PR #112 NP05A Sweets Manufacturing (Draft)", status: "DRAFT_NOT_INTEGRATED" },
};
const T = "trunk";
export const LIVE = [
  [T, "core10-owner-control-centre.css"], [T, "core10-owner-control-centre-ui.js"], [T, "core10-owner-control-client.js"],
  [T, "core10-master-data.css"], [T, "core10-master-data-client.js"], [T, "core10-master-data-ui.js"],
  [T, "core10-build01.html"], [T, "core10-build01.css"], [T, "core10-build01.js"], [T, "core10-build01-client.js"],
  [T, "core10-build01-config.js"], [T, "core10-build01-pack02.js"], [T, "core10-enterprise-client.js"], [T, "core10-control-studio.css"],
  [T, "vendor/supabase.js"],
  // GO-3 Level 2 (2026-11-22): the real signed Owner Control Centre against CORE10 staging (0100-0106 applied under GO-2).
  [T, "core10-owner-control-centre.html"], [T, "core10-owner-control-centre.js"],
  [T, "core10-pack02-workspace.js"], [T, "core10-pack02-workspace.css"], [T, "core10-pack02-controls.js"],
  [T, "docs/preview/c10-np01-canonical-reviewer-preview.html"],
  [T, "internal/enterprise-client/c10_np01_reviewer_workspace_v1.mjs"],
  [T, "internal/enterprise-client/c10_np01_reviewer_workspace_v1.css"],
  [T, "internal/enterprise-client/c10_np01_canonical_review_client_v1.mjs"],
  ["pr109", "core10-sales-order.css"], ["pr109", "core10-sales-master-catalog.js"], ["pr109", "core10-sales-order-client.js"],
  ["pr109", "core10-sales-order-ui.js"], ["pr109", "core10-sales-order-entry.js"],
  ["pr112", "core10-operational-flow.css"], ["pr112", "modules/manufacturing/manufacturing.css"],
  ["pr112", "modules/manufacturing/workbench.mjs"], ["pr112", "modules/manufacturing/client.mjs"],
];
// Level 2: the ONLY backend this bundle may reach, and its publishable (client-side, RLS/RPC-guarded) key.
export const STAGING = { ref: "rhrqhbyzrhaafynfhdaf", key: "sb_publishable_HeeiXCowelMel7kc171mvg_4xwkh7wf" };
export const SAMPLES = ["universal-owner", "business-owner-branded", "staff", "controls-central"];
const REPLAYS = [["/view/control-data.js", "CORE10_PREVIEW_CONTROL", "occ-owner-replay.json", T],
  ["/view/master-data.js", "CORE10_PREVIEW_MASTER", "md-replay.json", T],
  ["/view/sales-data.js", "CORE10_PREVIEW_SALES", "sales-replay.json", "pr109"],
  ["/view/mfg-data.js", "CORE10_PREVIEW_MFG", "mfg-replay.json", "pr112"]];
const FORBIDDEN = /(^|\/)(config\.js|index\.html|owner\.html|core10-stocktake-offline\.html|core10-stocktake-preview\.js|core10-shell\.js|core10-master-data\.js|sql-gateway\.cjs|ui-gateway\.cjs|gateway\.cjs|harness\.(js|html|mjs)|ui-harness\.js|md-harness\.(js|html)|seed\.sql)$/;

const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8", ".png": "image/png", ".svg": "image/svg+xml" };
const git = (...a) => execFileSync("git", a, { cwd: ROOT, encoding: "utf8" }).trim();
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");
const full = (k) => git("rev-parse", PINS[k].sha + "^{commit}");
const blob = (k, p) => git("rev-parse", `${full(k)}:${p}`);
const pinned = (k, p) => Buffer.from(execFileSync("git", ["cat-file", "blob", blob(k, p)], { cwd: ROOT }));
function walk(dir, base = "") {
  return fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))
    .flatMap((e) => e.isDirectory() ? walk(path.join(dir, e.name), base + e.name + "/") : [base + e.name]);
}

export function build() {
  const files = {}, manifest = [];
  const add = (route, buf, entry) => {
    files[route] = [TYPES[path.extname(route)] || "application/octet-stream", buf.toString("base64")];
    manifest.push({ route, bytes: buf.length, sha256: sha256(buf), ...entry });
  };
  {
    const src = pinned(T, "core10-control-centre-config.js").toString("utf8");
    const url = "https://" + STAGING.ref + ".supabase.co";
    if (!src.includes('url: "' + url + '", key: ""')) throw new Error("CONFIG_SOURCE_CHANGED");
    add("/live/core10-control-centre-config.js", Buffer.from(src.replace('key: ""', "key: " + JSON.stringify(STAGING.key))),
      { kind: "LEVEL2_CONFIG", commit: full(T), source: "core10-control-centre-config.js + STAGING.key (publishable)", backend: url });
  }
  for (const [k, p] of LIVE) add("/live/" + p, pinned(k, p), { kind: "ACTUAL_SOURCE", status: PINS[k].status, commit: full(k), source: p, git_blob: blob(k, p) });
  const ws = {};
  for (const n of SAMPLES) ws[n] = JSON.parse(pinned(T, `tests/pack02/fixtures/${n}.json`).toString("utf8"));
  add("/view/workspace-data.js", Buffer.from("window.CORE10_PREVIEW_WORKSPACE=" + JSON.stringify(ws) + ";\n"),
    { kind: "SAMPLE_DATA", commit: full(T), source: SAMPLES.map((n) => `tests/pack02/fixtures/${n}.json`).join(", ") });
  for (const [route, global, file, k] of REPLAYS) {
    const j = fs.readFileSync(path.join(HERE, "data", file), "utf8");
    add(route, Buffer.from("window." + global + "=" + j + ";\n"),
      { kind: "RECORDED_READ_REPLAY", status: PINS[k].status, commit: full(k), source: "preview/core10-central-owner-app/data/" + file });
  }
  for (const n of walk(path.join(HERE, "site")))
    add("/" + n, fs.readFileSync(path.join(HERE, "site", n)), { kind: "PREVIEW_SHELL", source: "preview/core10-central-owner-app/site/" + n });
  for (const r of Object.keys(files)) if (r !== "/index.html" && FORBIDDEN.test(r)) throw new Error("FORBIDDEN_FILE " + r);
  const runtime = fs.readFileSync(path.join(HERE, "worker-runtime.mjs"), "utf8");
  const pinStr = Object.entries(PINS).map(([k, v]) => k + "=" + full(k).slice(0, 7)).join(",");
  const worker = "// GENERATED by preview/core10-central-owner-app/build.mjs. Do not edit.\nconst PIN=" + JSON.stringify(pinStr) +
    ";\nconst FILES=" + JSON.stringify(files) + ";\n" + runtime;
  const pins = Object.fromEntries(Object.entries(PINS).map(([k, v]) => [k, { ...v, sha: full(k) }]));
  return { worker, manifest: { pins, worker_sha256: sha256(worker), files: manifest } };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { worker, manifest } = build();
  fs.mkdirSync(path.join(HERE, "dist"), { recursive: true });
  fs.writeFileSync(path.join(HERE, "dist/worker.mjs"), worker);
  fs.writeFileSync(path.join(HERE, "SOURCE_MANIFEST.json"), JSON.stringify(manifest, null, 1) + "\n");
  console.log("worker.mjs " + worker.length + " bytes sha256 " + manifest.worker_sha256);
}
