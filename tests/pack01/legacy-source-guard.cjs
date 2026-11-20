"use strict";
// D051 partial evidence: protect specific legacy source bytes against the
// verified PREVIEW branch base. Not a live render/DB/production parity proof.
const assert=require("node:assert/strict"),{execFileSync}=require("node:child_process"),path=require("node:path");
const root=path.resolve(__dirname,"../..");
const base="e76cf8a3db1a385726a1637683c972e99a193fec";
const protectedBlobs=Object.freeze({
 "index.html":"f2f74144e13ed865f45d84d6e683d49d2972cb5d",
 "app.css":"396ff2ed4e3142d7a3a98a943680bbc45671d3d4",
 "core.js":"fb5f4ba58d11e86eea046fa31463af2b301b52dd",
 "app.js":"8ea2359e943494452a3caa2192c688138be5827d",
 "config.js":"0f4fe5035973a6d032cbc906061cb2ace4b2ba12",
 "manifest.json":"c5407831e5851c0d946c523a9161aaa7cf609416",
 "sw.js":"cd4d0e3016948407374df56c52392790228a955d",
 "pos.js":"f4e6b4a2456fbec448cae875a019ca6a56fb0f1a",
 "prodplan.js":"6569ecbe3d77d393fe05b2764497613486550a51"
});
for(const [file,wanted] of Object.entries(protectedBlobs)){
 const actual=execFileSync("git",["hash-object",file],{cwd:root,encoding:"utf8"}).trim();
 assert.match(actual,/^[a-f0-9]{40}$/);
 assert.equal(actual,wanted,"D051 legacy source modified against frozen Preview base "+base+": "+file);
}
// D051 reconciliation: the original main/archive HTML and Preview HTML
// differ by exactly ONE additive script tag (Control Studio entry).
// Prove that removing that known Preview-only line recreates main's exact
// original git blob. This is static-source evidence, NOT UI/run parity.
const fs=require("node:fs"),crypto=require("node:crypto");
const html=fs.readFileSync(path.join(root,"index.html"),"utf8");
const extra='<script src="core10-control-studio-entry.js"></script>\n';
assert.equal(html.split(extra).length,2,
 "D051 index divergence changed: expected precisely one Preview Control Studio script");
const originalHtml=html.replace(extra,"");
const gitBlob=data=>crypto.createHash("sha1")
 .update("blob "+Buffer.byteLength(data)+"\0").update(data).digest("hex");
assert.equal(gitBlob(originalHtml),"fa1856bae67fed10764d7e797c6922378a209361",
 "D051 original main HTML must be reconstructible with only known additive Preview script");
assert.equal(gitBlob(html),protectedBlobs["index.html"],
 "D051 Preview index Git blob unexpected");
assert.ok(fs.existsSync(path.join(root,"core10-control-studio-entry.js")),
 "D051 additive Preview script source must exist");
console.log("PASS D051 main-vs-Preview index difference: only 1 additional Control Studio script tag; VISUAL PARITY NOT CERTIFIED");

// IMPORTANT: main/archive protected index.html blob is DIFFERENT before PACK01
// (fa1856bae... vs Preview f2f74144...). Do not label this a visual parity pass.
assert.notEqual(protectedBlobs["index.html"],
 "fa1856bae67fed10764d7e797c6922378a209361",
 "D051 preexisting main/Preview index divergence must remain explicit");
console.log("PASS D051 PACK01 SOURCE-BYTE GUARD 9/9 vs frozen Preview base "+base+
 " (NOT main index.html parity, UI screenshots, live DB or operational certification)");
