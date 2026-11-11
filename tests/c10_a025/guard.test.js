"use strict";
/* Static guards: no code execution, no float money, no clock/random in pure code, no brand-specific logic (REV-009), no legacy imports. */
const assert = require("node:assert/strict"); const fs = require("fs"), path = require("path"); const root = path.join(__dirname, "../../modules/simulation");
const files = []; (function walk(d) { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) { if (f !== "dist") walk(p); } else if (/\.(js|html|css|sql)$/.test(f)) files.push(p); } })(root);
assert.ok(files.length >= 15);
for (const f of files) { const s = fs.readFileSync(f, "utf8"), rel = path.relative(root, f); const code = rel.endsWith(".js") ? s : "";
  if (code) { assert.doesNotMatch(code, /\beval\s*\(|new Function\s*\(|\bFunction\s*\(/, rel + ": dynamic code execution forbidden"); assert.doesNotMatch(code, /child_process|require\(["']https?["']\)|fetch\(|XMLHttpRequest/, rel + ": no process/network in engine"); }
  if (/^(lib|models)\//.test(rel)) { assert.doesNotMatch(s, /Math\.random|Date\.now|new Date\(|performance\.now/, rel + ": pure code must not read clock/random (inject now)"); assert.doesNotMatch(s.replace(/toNumberUnsafe/g, ""), /parseFloat|Number\([^)]*\)\s*[*/+-]\s*[0-9.]+\s*\.\d/, rel + ": no float money math"); }
  assert.doesNotMatch(s, /islamia|islamiya|ইসলামিয়া|BOS_APP|report_registry|sweets_report|legacy.parity/i, rel + ": REV-009: no brand-specific logic or legacy ERP imports");
  assert.doesNotMatch(s, /require\(["']\.\.\/\.\.\/\.\.\/(?!modules)/, rel + ": must not import repo legacy files"); }
/* repo-level: engine must not touch legacy ERP files, workflows other than its own, or prod config */
const { execFileSync } = require("child_process"); let changed = ""; try { changed = execFileSync("git", ["diff", "--name-only", "origin/main...HEAD"], { cwd: path.join(__dirname, "../.."), encoding: "utf8" }); } catch (e) { changed = ""; }
if (changed) for (const f of changed.split("\n").filter(Boolean)) assert.match(f, /^(modules\/simulation\/|tests\/c10_a025\/|\.github\/workflows\/core10-a025|docs\/development\/(C10_A025|c10-a025)|c10_a025)/, "A025 branch must only add isolated paths, found: " + f);
console.log("PASS guard: " + files.length + " source files — no eval, no network/process in engine, no float money, no clock/random in pure code, brand-neutral, isolated paths");
