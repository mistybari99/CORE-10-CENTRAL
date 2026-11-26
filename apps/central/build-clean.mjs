import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import {fileURLToPath} from "node:url";
import {build} from "./build.mjs";
import {ALLOW,cleanFromPreview} from "./clean/transform.mjs";
const here=path.dirname(fileURLToPath(import.meta.url));
export function buildClean(){
 const base=build();
 const worker=cleanFromPreview(base.worker,fs.readFileSync(path.join(here,"clean/index.html")).toString("base64"),fs.readFileSync(path.join(here,"clean/app.js")).toString("base64"));
 const sha256=crypto.createHash("sha256").update(worker).digest("hex");
 return {worker,sha256,routes:ALLOW};
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const b=buildClean();fs.mkdirSync(path.join(here,"dist-clean"),{recursive:true});
 fs.writeFileSync(path.join(here,"dist-clean/worker.mjs"),b.worker);
 console.log(b.sha256+"  apps/central/dist-clean/worker.mjs");
}
