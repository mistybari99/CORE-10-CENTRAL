"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,"..");
const baseline=require("../data/core10_legacy_preservation_v1.json");
const registry=require("../data/report_registry.json");
const catalog=require("../data/core10_capability_catalog_v1.json");
const parity=require("../core10-legacy-parity.js");
const files=fs.readdirSync(root).filter(n=>/\.(?:js|css|html|webmanifest|svg)$/i.test(n)).sort();
const good=parity.check(baseline,registry,catalog,files);
assert.deepEqual(good.errors,[],JSON.stringify(good.errors.slice(0,5)));
assert.equal(good.checked.reports,193);
assert.equal(good.checked.protectedModules,7);
assert.equal(good.checked.legacyFiles,baseline.legacy_files.length);
function copy(o){return JSON.parse(JSON.stringify(o))}
function fail(result,expected){assert.equal(result.ok,false);assert.ok(result.errors.some(x=>x.startsWith(expected)),result.errors.join("|"))}
const absent=copy(registry);absent.reports=absent.reports.filter(x=>x.id!=="r193");absent.total=absent.reports.length;
fail(parity.check(baseline,absent,catalog,files),"MISSING_REPORT:r193");
const downgraded=copy(registry);const prev=downgraded.reports.find(x=>x.status==="implemented");prev.status="incomplete";
fail(parity.check(baseline,downgraded,catalog,files),"REPORT_STATUS_REGRESSED:"+prev.id);
const rerouted=copy(registry);rerouted.reports[0].route="#/nothing";
fail(parity.check(baseline,rerouted,catalog,files),"REPORT_ROUTE_CHANGED:r001");
const renamed=copy(registry);renamed.reports[1].name.en="Renamed";
fail(parity.check(baseline,renamed,catalog,files),"REPORT_NAME_CHANGED:r002");
fail(parity.check(baseline,registry,catalog,files.filter(x=>x!=="pos.js")),"LEGACY_FILE_REMOVED:pos.js");
const lostModule=copy(catalog);lostModule.templates.find(t=>t.id==="sweets_bakery").modules=
  lostModule.templates.find(t=>t.id==="sweets_bakery").modules.filter(m=>m.id!=="production");
fail(parity.check(baseline,registry,lostModule,files),"LEGACY_FOOD_MODULE_MISSING:production");
const duplicate=copy(registry);duplicate.reports.push(duplicate.reports[0]);duplicate.total++;
fail(parity.check(baseline,duplicate,catalog,files),"DUPLICATE_OR_INVALID_REPORT");
assert.equal(parity.check(baseline,registry,catalog).checked.legacyFiles,null);
assert.match(fs.readFileSync(path.join(root,"core10-business-builder.html"),"utf8"),/core10-legacy-parity-ui\.js/);
console.log("PASS: legacy asset paths "+baseline.legacy_files.length+", report identities "+baseline.legacy_reports.length+", no status regression, 7 food modules, negative loss scenarios");
