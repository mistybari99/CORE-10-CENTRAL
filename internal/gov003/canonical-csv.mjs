// NP01 B-007: pure CSV allowlist for signed GOV-003 audit metadata RPC results.
// This is a formatter, never an authorization layer. The RPC must authenticate and
// scope-check before these rows reach the client.
export const COLUMNS=Object.freeze(["stream_seq","source_domain","source_ref",
  "action","event_at","payload_sha256","event_digest"]);
function fail(){throw new TypeError("GOV003_EXPORT_INVALID");}
function csvCell(x){
 const s=String(x);
 // Protect Excel/Sheets formula interpretation; quote every field and escape quotes.
 const safe=/^[\s]*[=+@\-]/u.test(s) ? "'"+s : s;
 return '"'+safe.replace(/"/g,'""')+'"';
}
export function canonicalAuditCsv(rows){
 if(!Array.isArray(rows)||rows.length>500)fail();
 const lines=[COLUMNS.join(",")];
 for(const row of rows){
  if(!row||typeof row!=="object"||Array.isArray(row)||
    Object.keys(row).some(k=>!COLUMNS.includes(k))||
    COLUMNS.some(k=>row[k]===undefined||row[k]===null))fail();
  if(!/^[1-9]\d*$/.test(String(row.stream_seq)))fail();
  if(!/^[a-z][a-z0-9_]{1,63}$/.test(row.source_domain)||
    !/^[a-z][a-z0-9_.]{1,100}$/.test(row.action)||
    !/^[a-f0-9]{64}$/.test(row.payload_sha256)||
    !/^[a-f0-9]{64}$/.test(row.event_digest))fail();
  for(const key of COLUMNS)if(String(row[key]).length>200)fail();
  lines.push(COLUMNS.map(k=>csvCell(row[k])).join(","));
 }
 return lines.join("\r\n")+"\r\n";
}
