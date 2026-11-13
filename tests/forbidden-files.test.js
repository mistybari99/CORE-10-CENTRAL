"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { build, REQUIRED } = require("../internal/core10-pages-package");
const { checkArtifact, main } = require("./e2e/forbidden_files");

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "c10-forbidden-test-"));
const source = path.join(temporary, "repo");
const artifact = path.join(temporary, "site");
function put(base, relative, content = "fixture") {
  const file = path.join(base, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}
try {
  for (const name of REQUIRED) put(source, name);
  const forbidden = ["AGENTS.md", "README.md", "internal/private.js", "docs/guide.md", "schema.sql", "v2/private.sql", "setup-admin.html", "audit-admin.html", ".env", "vendor/private.key"];
  for (const name of forbidden) put(source, name, "DO_NOT_SERVE");
  build(source, artifact);
  assert.equal(checkArtifact(artifact).length, REQUIRED.length);
  for (const name of forbidden) {
    assert.equal(fs.existsSync(path.join(artifact, name)), false, name + " must be excluded by packaging");
    put(artifact, name);
    assert.throws(() => checkArtifact(artifact), /FORBIDDEN_PUBLISHED_ASSET/, name + " injected into artifact must fail");
    fs.unlinkSync(path.join(artifact, name));
    let parent = path.dirname(path.join(artifact, name));
    while (parent !== artifact && fs.readdirSync(parent).length === 0) {
      fs.rmdirSync(parent);
      parent = path.dirname(parent);
    }
  }
  fs.symlinkSync(path.join(source, "schema.sql"), path.join(artifact, "leak.js"));
  assert.throws(() => checkArtifact(artifact), /SYMLINK_IN_PUBLISH_SCOPE/);
  fs.unlinkSync(path.join(artifact, "leak.js"));
  main([artifact]);
  assert.throws(() => main([artifact, "unexpected"]), /Usage:/);
  put(artifact, "AGENTS.md");
  assert.throws(() => main([artifact]), /FORBIDDEN_PUBLISHED_ASSET:AGENTS.md/);
  console.log("PASS forbidden artifact gate: private checkout files excluded; injected private files and symlinks rejected; invalid arguments rejected");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
