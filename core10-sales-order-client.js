/* NP03B Sales Order adapter. Reuses the canonical reviewer client's session
 * binding pattern and Build01 context. SQL Auth/Control remains the authority.
 * No direct table access, implicit config, credential creation or posting API.
 */
(function(root,factory){
 "use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_SALES_ORDER_CLIENT=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const object=x=>!!x&&typeof x==="object"&&!Array.isArray(x);
 const statuses=new Set(["draft","confirmed","cancelled"]);
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 function shape(x,keys){if(!object(x)||Object.keys(x).some(k=>!keys.includes(k)))fail("SALES_CLIENT_INVALID_INPUT");}
 function id(x){if(!Number.isSafeInteger(x)||x<1)fail("SALES_CLIENT_INVALID_ID");return x;}
 function version(x,min){if(!Number.isSafeInteger(x)||x<min)fail("SALES_CLIENT_INVALID_VERSION");return x;}
 function uid(x){if(typeof x!=="string"||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x))fail("SALES_CLIENT_SIGNED_SESSION_REQUIRED");return x.toLowerCase();}
 function key(x){if(typeof x!=="string"||!/^[A-Za-z0-9_-]{8,100}$/.test(x))fail("SALES_CLIENT_INVALID_REQUEST_KEY");return x;}
 function finite(x,min){if(typeof x!=="number"||!Number.isFinite(x)||Math.abs(x)>Number.MAX_SAFE_INTEGER||x<min)fail("SALES_CLIENT_INVALID_NUMBER");return x;}
 function snapshot(value){
  const seen=new Set();
  function inspect(v){
   if(v===null||typeof v==="string"||typeof v==="boolean")return;
   if(typeof v==="number"){finite(v,-Number.MAX_SAFE_INTEGER);return;}
   if(!object(v)&&!Array.isArray(v)||seen.has(v))fail("SALES_CLIENT_INVALID_JSON");
   const prototype=Object.getPrototypeOf(v);
   if(prototype!==Object.prototype&&prototype!==Array.prototype&&prototype!==null)fail("SALES_CLIENT_INVALID_JSON");
   seen.add(v);for(const k of Object.keys(v))inspect(v[k]);seen.delete(v);
  }
  inspect(value);
  try{return JSON.parse(JSON.stringify(value));}catch{fail("SALES_CLIENT_INVALID_JSON");}
 }
 function documentCopy(value){
  const d=snapshot(value);
  shape(d,["customer_id","price_list_id","currency","lines"]);
  id(d.customer_id);id(d.price_list_id);
  if(typeof d.currency!=="string"||!/^[A-Z]{3}$/.test(d.currency)||!Array.isArray(d.lines)||d.lines.length<1||d.lines.length>1000)fail("SALES_CLIENT_INVALID_DOCUMENT");
  for(const l of d.lines){
   shape(l,["item_id","variant_id","uom_id","quantity","unit_price","discount_percent","tax_percent"]);
   id(l.item_id);id(l.uom_id);if(l.variant_id!=null)id(l.variant_id);
   if(finite(l.quantity,0)<=0)fail("SALES_CLIENT_INVALID_NUMBER");finite(l.unit_price,0);
   if(finite(l.discount_percent,0)>100||finite(l.tax_percent,0)>100)fail("SALES_CLIENT_INVALID_NUMBER");
  }
  return d;
 }
 function scoped(x,b,s){
  if(!object(x)||x.business_id!==b||x.site_id!==s)fail("SALES_CLIENT_SCOPE_MISMATCH");
  return x;
 }
 function noPosting(x){if(x.stock_posted!==false||x.financial_posted!==false)fail("SALES_CLIENT_UNEXPECTED_POSTING");}
 function receipt(x,b,s,order,expected,status){
  scoped(x,b,s);noPosting(x);id(x.order_id);version(x.version,1);finite(x.total,0);
  if(order!==null&&x.order_id!==order||x.version!==expected+1||x.status!==status)fail("SALES_CLIENT_INVALID_RECEIPT");
  return snapshot(x);
 }
 // Invoice receipts are deliberately draft-only. A successful validation is
 // neither issuance nor a claim that Stock/Money were connected.
 function invoiceBoundary(x){
  if(!object(x))fail("SALES_CLIENT_INVALID_INVOICE");noPosting(x);
  const c=x.connections;
  if(x.issued!==false||!object(c)||c.issuance!=="NOT_CONNECTED"||c.stock!=="NOT_CONNECTED"||c.money!=="NOT_CONNECTED"||c.tax!=="ZERO_ONLY")fail("SALES_CLIENT_UNEXPECTED_POSTING");
 }
 function invoiceReceipt(x,b,s,invoice=null,expected=null,validated=null,order=null,orderVersion=null){
  scoped(x,b,s);invoiceBoundary(x);id(x.invoice_id);id(x.source_order_id);version(x.source_order_version,1);version(x.version,1);finite(x.total,0);
  if(x.status!=="draft"||typeof x.validated!=="boolean"||typeof x.currency!=="string"||!/^[A-Z]{3}$/.test(x.currency)
   ||typeof x.source_sha256!=="string"||!/^[a-f0-9]{64}$/.test(x.source_sha256)
   ||invoice!==null&&x.invoice_id!==invoice||expected!==null&&x.version!==expected+1||validated!==null&&x.validated!==validated
   ||order!==null&&x.source_order_id!==order||orderVersion!==null&&x.source_order_version!==orderVersion)fail("SALES_CLIENT_INVALID_INVOICE_RECEIPT");
  return x;
 }
 function selectionCopy(value){
  const rows=snapshot(value);if(!Array.isArray(rows)||rows.length<1||rows.length>1000)fail("SALES_CLIENT_INVALID_SELECTION");
  const seen=new Set();for(const l of rows){shape(l,["order_line_no","quantity"]);id(l.order_line_no);
   if(l.order_line_no>1000||seen.has(l.order_line_no)||finite(l.quantity,0)<=0)fail("SALES_CLIENT_INVALID_SELECTION");seen.add(l.order_line_no);}
  return rows;
 }
 function equal(a,b){
  if(a===b)return true;if(!a||!b||typeof a!=="object"||typeof b!=="object"||Array.isArray(a)!==Array.isArray(b))return false;
  const keys=Object.keys(a);return keys.length===Object.keys(b).length&&keys.every(k=>Object.hasOwn(b,k)&&equal(a[k],b[k]));
 }
 function stages(x){if(!Number.isSafeInteger(x)||x<0||x>5)fail("SALES_CLIENT_INVALID_CONTROLS");return x;}
 function memoCopy(x){if(typeof x!=="string"||[...x].length>4000)fail("SALES_CLIENT_INVALID_MEMO");return x;}
 function moneyScale(x){if(!Number.isSafeInteger(x)||x<0||x>6)fail("SALES_CLIENT_INVALID_INVOICE");return x;}
 function amountUnits(x,scale){finite(x,0);const f=x.toFixed(scale);if(Number(f)!==x)fail("SALES_CLIENT_INVALID_INVOICE");return BigInt(f.replace(".",""));}
 function totalMatches(values,total,scale){if(values.reduce((n,x)=>n+amountUnits(x,scale),0n)!==amountUnits(total,scale))fail("SALES_CLIENT_INVALID_INVOICE");}
 function invoiceDocument(doc,selection,source){
  documentCopy(doc);const choices=selectionCopy(selection).sort((a,b)=>a.order_line_no-b.order_line_no);
  if(doc.customer_id!==source.customer_id||doc.price_list_id!==source.price_list_id||doc.currency!==source.currency||doc.lines.length!==choices.length)fail("SALES_CLIENT_INVALID_INVOICE");
  choices.forEach((choice,n)=>{
   const original=source.lines[choice.order_line_no-1],line=doc.lines[n];
   if(!original||choice.quantity>original.quantity||line.quantity!==choice.quantity)fail("SALES_CLIENT_INVALID_SELECTION");
   for(const k of ["item_id","uom_id","unit_price","discount_percent","tax_percent"])
    if(line[k]!==original[k]||line.tax_percent!==0)fail("SALES_CLIENT_INVALID_INVOICE");
   if((line.variant_id??null)!==(original.variant_id??null))fail("SALES_CLIENT_INVALID_INVOICE");
  });return choices;
 }
 function invoiceApproval(p,row,expectedVersion,requiredStages=null){
  if(!object(p)||p.invoice_id!==row.invoice_id||p.site_id!==row.site_id||p.version!==expectedVersion
   ||p.source_order_id!==row.source_order_id||p.source_order_version!==row.source_order_version||p.source_sha256!==row.source_sha256
   ||p.money_scale!==row.money_scale||p.action!=="invoice_validate")fail("SALES_CLIENT_INVALID_APPROVAL");
  stages(p.required_stages);if(requiredStages!==null&&p.required_stages!==requiredStages)fail("SALES_CLIENT_INVALID_APPROVAL");
  memoCopy(p.memo);finite(p.total,0);documentCopy(p.document);
 }
 function invoiceRow(row,b,s,invoice,requiredStages){
  invoiceReceipt(row,b,s,invoice);const scale=moneyScale(row.money_scale),src=scoped(row.source_snapshot,b,s);
  if(src.order_id!==row.source_order_id||src.order_version!==row.source_order_version||src.money_scale!==scale)fail("SALES_CLIENT_SCOPE_MISMATCH");
  id(src.confirmation_audit_event_id);const original=documentCopy(src.document);
  if(original.lines.some(l=>l.tax_percent!==0)||!Array.isArray(src.line_totals)||src.line_totals.length!==original.lines.length)fail("SALES_CLIENT_INVALID_INVOICE");
  totalMatches(src.line_totals,src.total,scale);
  id(row.customer_id);id(row.price_list_id);memoCopy(row.memo);uid(row.changed_by);
  if(row.customer_id!==original.customer_id||row.price_list_id!==original.price_list_id||row.currency!==original.currency)fail("SALES_CLIENT_INVALID_INVOICE");
  const choices=invoiceDocument(row.document,row.selection,original);
  if(!Array.isArray(row.lines)||row.lines.length!==choices.length)fail("SALES_CLIENT_INVALID_INVOICE");
  let tenant=null;
  row.lines.forEach((l,n)=>{
   scoped(l,b,s);id(l.tenant_id);if(tenant===null)tenant=l.tenant_id;
   if(l.tenant_id!==tenant||l.invoice_id!==row.invoice_id||l.source_order_id!==row.source_order_id||l.line_no!==n+1||l.source_line_no!==choices[n].order_line_no)fail("SALES_CLIENT_SCOPE_MISMATCH");
   for(const k of ["item_id","uom_id","quantity","unit_price","discount_percent","tax_percent"])
    if(l[k]!==row.document.lines[n][k])fail("SALES_CLIENT_INVALID_INVOICE");
   if((l.variant_id??null)!==(row.document.lines[n].variant_id??null))fail("SALES_CLIENT_INVALID_INVOICE");
  });totalMatches(row.lines.map(l=>l.line_total),row.total,scale);
  if(row.validated){uid(row.validated_by);if(typeof row.validated_at!=="string"||!Number.isFinite(Date.parse(row.validated_at)))fail("SALES_CLIENT_INVALID_INVOICE");}
  else if(row.validated_by!==null||row.validated_at!==null)fail("SALES_CLIENT_INVALID_INVOICE");
  invoiceApproval(row.approval_payload,row,row.version,requiredStages);
  if(!equal(row.approval_payload.document,row.document)||row.approval_payload.memo!==row.memo||row.approval_payload.total!==row.total)fail("SALES_CLIENT_INVALID_APPROVAL");
  if(!Array.isArray(row.audit)||row.audit.length<1)fail("SALES_CLIENT_INVALID_AUDIT");
  let seq=0,last=null,lastDocument=null,lastMemo=null,lastSelection=null;const seen=new Set();
  for(const event of row.audit){
   if(!object(event)||seen.has(id(event.id))||id(event.stream_seq)<=seq||typeof event.event_at!=="string"||!Number.isFinite(Date.parse(event.event_at))||!object(event.payload))fail("SALES_CLIENT_INVALID_AUDIT");
   seen.add(event.id);seq=event.stream_seq;uid(event.actor_id);
   const validating=event.action==="sales.invoice_draft_validated";
   if(!validating&&event.action!=="sales.invoice_draft_saved")fail("SALES_CLIENT_INVALID_AUDIT");
   const r=invoiceReceipt(event.payload.receipt,b,s,row.invoice_id,null,validating,row.source_order_id,row.source_order_version);
   if(r.source_sha256!==row.source_sha256||r.currency!==row.currency||r.version!==(last?last.version+1:1)||r.version>row.version)fail("SALES_CLIENT_INVALID_AUDIT");
   if(validating){
    if(event.payload.approval_id!==null)id(event.payload.approval_id);invoiceApproval(event.payload.approval_payload,row,r.version-1);
    if(!last||!equal(event.payload.approval_payload.document,lastDocument)||event.payload.approval_payload.memo!==lastMemo||event.payload.approval_payload.total!==last.total||r.total!==last.total)fail("SALES_CLIENT_INVALID_AUDIT");
   } else {memoCopy(event.payload.memo);invoiceDocument(event.payload.document,event.payload.selection,original);
    lastDocument=event.payload.document;lastMemo=event.payload.memo;lastSelection=event.payload.selection;}
   last=r;
  }
  // Rows add presentation fields; compare each last receipt field.
  if(Object.keys(last).some(k=>!equal(last[k],row[k])))fail("SALES_CLIENT_INVALID_AUDIT");
  if(!equal(lastDocument,row.document)||lastMemo!==row.memo||!equal(lastSelection,row.selection))fail("SALES_CLIENT_INVALID_AUDIT");
 }
 function create(options){
  shape(options,["client","backendMode"]);
  const client=options.client,backendMode=options.backendMode;
  if(!["signed","synthetic"].includes(backendMode))fail("SALES_CLIENT_BACKEND_MODE_REQUIRED");
  if(!client?.auth||typeof client.auth.getUser!=="function"||typeof client.auth.onAuthStateChange!=="function"||typeof client.schema!=="function")fail("SALES_CLIENT_SIGNED_CLIENT_REQUIRED");
  let actor=null,revision=0,closed=false,invalidated=false;
  // A new adapter is created by the signed host after a session change. Even a
  // same-user sign-out/sign-in cannot let an earlier request repopulate the UI.
  const subscription=client.auth.onAuthStateChange((event)=>{
   if(closed||event==="INITIAL_SESSION")return;
   invalidated=true;revision++;
  })?.data?.subscription;
  if(!subscription||typeof subscription.unsubscribe!=="function")fail("SALES_CLIENT_SESSION_SUBSCRIPTION_REQUIRED");
  function active(){if(closed||invalidated)fail("SALES_CLIENT_SESSION_INVALIDATED");}
  async function authenticated(){
   active();const before=revision;
   let result;
   try{result=await client.auth.getUser();}catch{invalidated=true;revision++;fail("SALES_CLIENT_SIGNED_SESSION_REQUIRED");}
   active();
   if(before!==revision)fail("SALES_CLIENT_SESSION_INVALIDATED");
   if(!result||result.error||!result.data?.user){invalidated=true;revision++;fail("SALES_CLIENT_SIGNED_SESSION_REQUIRED");}
   let who;
   try{who=uid(result.data.user.id);}catch(e){invalidated=true;revision++;throw e;}
   if(actor!==null&&actor!==who){invalidated=true;revision++;fail("SALES_CLIENT_SESSION_INVALIDATED");}
   actor=who;return who;
  }
  async function rpc(name,args){
   const revisionBefore=revision,before=await authenticated();
   if(revisionBefore!==revision)fail("SALES_CLIENT_SESSION_INVALIDATED");
   let result,thrown=false;
   try{
    const db=client.schema("core10");
    if(!db||typeof db.rpc!=="function")fail("SALES_CLIENT_API_UNAVAILABLE");
    result=await db.rpc(name,args);
   }catch{thrown=true;}
   const after=await authenticated();
   if(before!==after||revisionBefore!==revision)fail("SALES_CLIENT_SESSION_INVALIDATED");
   if(thrown)fail("SALES_CLIENT_RPC_UNAVAILABLE");
   if(!result||result.data==null&&!result.error)fail("SALES_CLIENT_RPC_NO_RECEIPT");
   if(result.error){
    const raw=typeof result.error==="string"?result.error:result.error.message;
    const errorCode=typeof result.error.code==="string"?result.error.code:"";
    // A write may already have committed when its HTTP response is lost. The
    // host must preserve its request key on transport failures, not sign out or
    // announce a rejection. SDKs may return Error objects instead of throwing.
    if(result.error.name==="AbortError"||/^(ECONNRESET|ECONNREFUSED|ETIMEDOUT|FETCH_ERROR)$/.test(errorCode)
      ||typeof raw==="string"&&/failed to fetch|fetch failed|network|connection (?:timed? ?out|reset|refused|closed)|timeout|timed out|load failed|request aborted/i.test(raw))
     fail("SALES_CLIENT_RPC_UNAVAILABLE");
    // PostgREST uses prose for missing functions. Keep the stable machine code
    // so an unconnected dependency is distinguishable from permission denial.
    if(["PGRST202","42883"].includes(errorCode))fail(errorCode);
    const code=typeof raw==="string"&&/^[A-Za-z0-9_.:-]{1,160}$/.test(raw)?raw:"SALES_CLIENT_RPC_DENIED";
    fail(code);
   }
   try{return snapshot(result.data);}catch(error){
    // The server returned data, but this adapter cannot trust its shape. A
    // mutation may have committed; the host must retain its exact retry key.
    error.responseUntrusted=true;throw error;
   }
  }
  async function context(){
   const x=await rpc("build01_context_v1",{});
   if(!object(x)||x.actor_uid!==actor||!Array.isArray(x.businesses)||!Array.isArray(x.sites)||!Array.isArray(x.legal_entities))fail("SALES_CLIENT_INVALID_CONTEXT");
   const businesses=new Map(),sites=new Set();
   for(const b of x.businesses){
    if(!object(b)||typeof b.can_manage!=="boolean"||typeof b.label!=="string"||businesses.has(id(b.id)))fail("SALES_CLIENT_INVALID_CONTEXT");
    businesses.set(b.id,id(b.tenant_id));
   }
   for(const s of x.sites){
    if(!object(s)||sites.has(id(s.id))||!businesses.has(id(s.business_id))||typeof s.label!=="string"||!Array.isArray(s.allowed_actions))fail("SALES_CLIENT_INVALID_CONTEXT");
    if(id(s.tenant_id)!==businesses.get(s.business_id))fail("SALES_CLIENT_INVALID_CONTEXT");
    sites.add(s.id);
   }
   return x;
  }
  async function read(input){
   shape(input,["businessId","siteId","orderId"]);
   const b=id(input.businessId),s=id(input.siteId),o=input.orderId==null?null:id(input.orderId);
   const x=scoped(await rpc("read_sales_orders_v1",{p_business:b,p_site:s,p_order:o}),b,s);
   noPosting(x);
   if(!Array.isArray(x.items)||x.items.length>100)fail("SALES_CLIENT_INVALID_ROWS");
   const seen=new Set();
   for(const row of x.items){
    if(!object(row)||row.site_id!==s||row.business_id!==undefined&&row.business_id!==b||seen.has(id(row.id))||o!==null&&row.id!==o)fail("SALES_CLIENT_SCOPE_MISMATCH");
    seen.add(row.id);version(row.version,1);finite(row.total,0);documentCopy(row.document);
    if(!statuses.has(row.status))fail("SALES_CLIENT_INVALID_STATUS");
   }
   return x;
  }
  async function controls(input){
   shape(input,["businessId","siteId"]);
   const b=id(input.businessId),s=id(input.siteId),rows=await rpc("control_read_v1",{p_business:b,p_site:s});
   if(!Array.isArray(rows))fail("SALES_CLIENT_INVALID_CONTROLS");
   const seen=new Set();
   for(const x of rows){
    if(!object(x)||typeof x.feature_key!=="string"||seen.has(x.feature_key)||typeof x.enabled!=="boolean"||!Number.isSafeInteger(x.stages)||x.stages<0||x.stages>5)fail("SALES_CLIENT_INVALID_CONTROLS");
    if(x.business_id!==undefined&&x.business_id!==b||x.site_id!=null&&x.site_id!==s)fail("SALES_CLIENT_SCOPE_MISMATCH");
    seen.add(x.feature_key);
   }
   return rows;
  }
  async function save(input){
   shape(input,["businessId","siteId","orderId","expectedVersion","document","requestKey"]);
   const b=id(input.businessId),s=id(input.siteId),o=input.orderId==null?null:id(input.orderId),v=version(input.expectedVersion,o===null?0:1);
   if(o===null&&v!==0)fail("SALES_CLIENT_INVALID_VERSION");
   const args={p_business:b,p_site:s,p_order:o,p_expected:v,p_document:documentCopy(input.document),p_key:key(input.requestKey)};
   return receipt(await rpc("save_sales_order_v1",args),b,s,o,v,"draft");
  }
  async function transition(input){
   shape(input,["businessId","siteId","orderId","action","expectedVersion","approvalId","requestKey"]);
   const b=id(input.businessId),s=id(input.siteId),o=id(input.orderId),v=version(input.expectedVersion,1),action=input.action;
   if(!["confirm","cancel"].includes(action))fail("SALES_CLIENT_INVALID_ACTION");
   const args={p_business:b,p_site:s,p_order:o,p_action:action,p_expected:v,p_approval:input.approvalId==null?null:id(input.approvalId),p_key:key(input.requestKey)};
   return receipt(await rpc("transition_sales_order_v1",args),b,s,o,v,action==="confirm"?"confirmed":"cancelled");
  }
  async function audit(input){
   shape(input,["businessId","siteId","orderId"]);
   const b=id(input.businessId),s=id(input.siteId),o=id(input.orderId);
   const x=scoped(await rpc("read_sales_order_audit_v1",{p_business:b,p_site:s,p_order:o}),b,s);
   if(x.order_id!==o||!Array.isArray(x.items)||x.items.length>100)fail("SALES_CLIENT_INVALID_AUDIT");
   const seen=new Set();
   for(const row of x.items){
    scoped(row,b,s);
    if(row.order_id!==o||seen.has(id(row.id)))fail("SALES_CLIENT_SCOPE_MISMATCH");
    seen.add(row.id);id(row.stream_seq);uid(row.actor_id);
    if(typeof row.action!=="string"||!/^sales\.[a-z_]+$/.test(row.action)||typeof row.event_at!=="string"||!Number.isFinite(Date.parse(row.event_at))||!object(row.payload))fail("SALES_CLIENT_INVALID_AUDIT");
   }
   return x;
  }
  async function readInvoices(input){
   shape(input,["businessId","siteId","invoiceId"]);
   const b=id(input.businessId),s=id(input.siteId),i=input.invoiceId==null?null:id(input.invoiceId);
   const x=await rpc("read_sales_invoice_drafts_v1",{p_business:b,p_site:s,p_invoice:i});invoiceBoundary(x);
   const c=x.validation_control;
   if(!object(c)||c.feature_key!=="sales.invoice_validate"||typeof c.enabled!=="boolean"||c.required!==(stages(c.stages)>0)||c.approval_domain!=="sales"||c.approval_action!=="invoice_validate")fail("SALES_CLIENT_INVALID_CONTROLS");
   if(!Array.isArray(x.invoices)||x.invoices.length>100)fail("SALES_CLIENT_INVALID_ROWS");
   const seen=new Set(),orders=new Set();
   for(const row of x.invoices){invoiceRow(row,b,s,i,c.stages);
    if(seen.has(row.invoice_id)||orders.has(row.source_order_id))fail("SALES_CLIENT_INVALID_ROWS");seen.add(row.invoice_id);orders.add(row.source_order_id);}
   return x;
  }
  async function saveInvoice(input){
   shape(input,["businessId","siteId","invoiceId","expectedVersion","orderId","orderVersion","lines","memo","requestKey"]);
   const b=id(input.businessId),s=id(input.siteId),i=input.invoiceId==null?null:id(input.invoiceId),v=version(input.expectedVersion,i===null?0:1),o=id(input.orderId),ov=version(input.orderVersion,1);
   if(i===null&&v!==0)fail("SALES_CLIENT_INVALID_VERSION");
   const lines=input.lines===null?null:selectionCopy(input.lines);if(i!==null&&lines===null)fail("SALES_CLIENT_INVALID_SELECTION");
   const args={p_business:b,p_site:s,p_invoice:i,p_expected:v,p_order:o,p_order_version:ov,p_lines:lines,p_memo:memoCopy(input.memo),p_key:key(input.requestKey)};
   const result=await rpc("save_sales_invoice_draft_v1",args);
   try{return invoiceReceipt(result,b,s,i,v,false,o,ov);}catch(error){error.writeOutcomeUncertain=true;throw error;}
  }
  async function validateInvoice(input){
   shape(input,["businessId","siteId","invoiceId","expectedVersion","approvalId","requestKey"]);
   const b=id(input.businessId),s=id(input.siteId),i=id(input.invoiceId),v=version(input.expectedVersion,1);
   const args={p_business:b,p_site:s,p_invoice:i,p_expected:v,p_approval:input.approvalId==null?null:id(input.approvalId),p_key:key(input.requestKey)};
   const result=await rpc("validate_sales_invoice_draft_v1",args);
   try{return invoiceReceipt(result,b,s,i,v,true);}catch(error){error.writeOutcomeUncertain=true;throw error;}
  }
  return Object.freeze({context,read,controls,save,transition,audit,readInvoices,saveInvoice,validateInvoice,
   getState:()=>Object.freeze({backendMode,connected:!closed&&!invalidated,actorBound:actor!==null}),
   destroy(){if(!closed){closed=true;revision++;subscription.unsubscribe();}}
  });
 }
 return Object.freeze({create});
});
