"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const vm=require("node:vm");
const html=fs.readFileSync("core10-business-builder.html","utf8");
const ui=fs.readFileSync("core10-business-builder-ui.js","utf8");
const engine=fs.readFileSync("core10-business-builder.js","utf8");
new vm.Script(ui,{filename:"core10-business-builder-ui.js"});
new vm.Script(engine,{filename:"core10-business-builder.js"});
for(const id of ["template","businessName","slug","brand","mode","moduleChoices","siteName","siteKind","addSite","siteRows","review","jsonPreview","export","next","back","notice"]){
 assert.ok(html.includes('id="'+id+'"'),"Missing "+id);
}
assert.match(html,/core10-business-builder\.js/);
assert.match(html,/core10-business-builder-ui\.js/);
assert.match(ui,/releaseEnabled:false/);
assert.match(engine,/production_ready:false/);
assert.doesNotMatch(ui,/\.rpc\(|service_role|method:\s*["']POST/);
assert.match(html,/@media\(max-width:560px\)/);
console.log("PASS: browser wizard syntax, DOM wiring and fail-closed preview");
