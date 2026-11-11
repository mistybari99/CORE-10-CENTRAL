"use strict";
// Verify the publishable artifact, never mistake the development checkout for it.
// Usage: node tests/e2e/forbidden_files.js [existing-artifact-directory]
// No argument builds an isolated temporary artifact with the canonical packager.
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { build, verify } = require("../../internal/core10-pages-package");

function checkArtifact(directory) {
  return verify(path.resolve(directory));
}

function main(args) {
  if (args.length > 1) throw new Error("Usage: forbidden_files.js [artifact-directory]");
  let temporary;
  try {
    let artifact = args[0];
    if (!artifact) {
      temporary = fs.mkdtempSync(path.join(os.tmpdir(), "c10-served-set-"));
      artifact = path.join(temporary, "site");
      build(path.resolve(__dirname, "../.."), artifact);
    }
    const files = checkArtifact(artifact);
    console.log("PASS forbidden_files: " + files.length + " allowlisted artifact assets; internal/docs/AGENTS/SQL/secrets excluded");
    console.log("Artifact verification only; this does not certify the repository root or live publishing configuration.");
  } finally {
    if (temporary) fs.rmSync(temporary, { recursive: true, force: true });
  }
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (err) { console.error("FAIL forbidden files in served artifact: " + err.message); process.exitCode = 1; }
}
module.exports = { checkArtifact, main };
