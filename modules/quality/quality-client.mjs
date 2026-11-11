/**
 * CORE10 A058 quality client contract — disposable/staging transport adapter.
 * No network, secrets or production feature switch is bundled here.
 * Server-side C10-A058 RLS/RPC, not this client, is the authorization boundary.
 * Never use "mode" alone as authority to deploy to live IMG-ERP-SG.
 */
export const QUALITY_RPC = Object.freeze({
  enableTracking: "quality_enable_item_v1",
  registerLot: "quality_register_lot_v1",
  inspect: "quality_inspect_v1",
  decide: "quality_decide_lot_v1",
  postStock: "quality_stock_v1",
  transfer: "quality_transfer_v1",
  linkGenealogy: "quality_link_genealogy_v1",
  startRecall: "quality_start_recall_v1",
  closeRecall: "quality_close_recall_v1",
  fefo: "quality_fefo_v1"
});
export const QUALITY_VIEWS = Object.freeze({
  lots: "quality_lot_summary_v1",
  balances: "quality_balances_v1",
  movements: "quality_movements_v1",
  inspections: "quality_inspections_v1",
  recalls: "quality_recalls_v1",
  impacts: "quality_recall_impacts_v1",
  genealogy: "quality_genealogy_v1",
  reconciliation: "quality_reconciliation_v1",
  audit: "quality_audit_v1"
});
export const QUALITY_STATUS = Object.freeze({
  pending_qc: "In quarantine", released: "Released",
  held: "Held", rejected: "Rejected", recalled: "Recalled"
});
const id = (value, key) => {
  if (!Number.isSafeInteger(value) || value <= 0) throw new TypeError("quality_invalid_" + key);
  return value;
};
const str = (value, key, min=1, max=120) => {
  if (typeof value !== "string" || value.trim().length < min || value.length > max) {
    throw new TypeError("quality_invalid_" + key);
  }
  return value.trim();
};
const optDate = (value, key) => {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new TypeError("quality_invalid_" + key);
  }
  const [y,m,d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y,m-1,d));
  if (date.getUTCFullYear()!==y || date.getUTCMonth()+1!==m || date.getUTCDate()!==d) {
    throw new TypeError("quality_invalid_" + key);
  }
  return value;
};
const amount = (value, key="quantity") => {
  // Require decimal input as a string so JS floats cannot silently round money/stock.
  if (typeof value !== "string" || !/^(?:0|[1-9]\d{0,6})(?:\.\d{1,3})?$/.test(value)) {
    throw new TypeError("quality_invalid_" + key);
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n<=0 || n>1000000) throw new TypeError("quality_invalid_" + key);
  return value;
};
const checks = value => {
  if (!Array.isArray(value) || value.length<1 || value.length>30) {
    throw new TypeError("quality_invalid_inspection_checks");
  }
  const codes = new Set();
  const clean = value.map(v => {
    if (!v || typeof v!=="object" || Array.isArray(v) || typeof v.ok!=="boolean") {
      throw new TypeError("quality_invalid_inspection_check");
    }
    const code = str(v.code,"inspection_check_code",1,60);
    if (codes.has(code)) throw new TypeError("quality_duplicate_inspection_check");
    codes.add(code);
    return {code,ok:v.ok};
  });
  return clean;
};
const union = (value, values, key) => {
  if (!values.includes(value)) throw new TypeError("quality_invalid_"+key);
  return value;
};
const request = v => str(v,"request_key",3,120);
export class QualityTransportError extends Error {
  constructor(message, cause) {super(message);this.name="QualityTransportError";this.cause=cause;}
}
export function createQualityClient({ rpc, read, enabled=false, environment="disposable-only" }={}) {
  if (!enabled || environment!=="disposable-only") {
    throw new Error("quality_isolated_demo_only_not_authorized_for_production");
  }
  if (typeof rpc!=="function" || typeof read!=="function") {
    throw new TypeError("quality_rpc_and_read_transports_required");
  }
  const call=async(method,params)=>{
    let result;
    try {result=await rpc({schema:"c10_demo",method,params:Object.freeze({...params})});}
    catch(error){throw new QualityTransportError("quality_transport_failed",error);}
    if (result && typeof result==="object" && Object.hasOwn(result,"error")) {
      if (result.error) throw new QualityTransportError(result.error.message||"quality_rpc_error",result.error);
      return result.data;
    }
    return result;
  };
  const get=async(view,filters)=>{
    let result;
    try {result=await read({schema:"c10_demo",view,filters:Object.freeze({...filters})});}
    catch(error){throw new QualityTransportError("quality_read_failed",error);}
    if (result && typeof result==="object" && Object.hasOwn(result,"error")) {
      if (result.error) throw new QualityTransportError(result.error.message||"quality_read_error",result.error);
      return result.data;
    }
    return result;
  };
  return Object.freeze({
    enableTracking:({businessId,itemId})=>call(QUALITY_RPC.enableTracking,{
      p_business:id(businessId,"business_id"),p_item:id(itemId,"item_id")}),
    registerLot:({businessId,itemId,siteId,code,source,reference,manufacturedOn,expiresOn,key})=>{
      const made=optDate(manufacturedOn,"manufacture_date"),expires=optDate(expiresOn,"expiry_date");
      if(made && expires && expires<made)throw new TypeError("quality_expiry_precedes_manufacture");
      return call(QUALITY_RPC.registerLot,{p_business:id(businessId,"business_id"),
        p_item:id(itemId,"item_id"),p_origin_site:id(siteId,"site_id"),
        p_code:str(code,"lot_code",2,80),
        p_source:union(source,["purchase","production","opening","return","adjustment"],"lot_source"),
        p_reference:str(reference,"source_reference",2,120),p_made:made,p_expiry:expires,p_key:request(key)});
    },
    inspect:({lotId,result,checks:inputChecks,notes="",key})=>{
      const clean=checks(inputChecks);
      const decision=union(result,["pass","fail"],"inspection_result");
      if(decision==="pass" && clean.some(x=>!x.ok))throw new TypeError("quality_false_pass");
      if(typeof notes!=="string"||notes.length>1000)throw new TypeError("quality_invalid_notes");
      return call(QUALITY_RPC.inspect,{p_lot:id(lotId,"lot_id"),p_result:decision,p_checks:clean,p_notes:notes,p_key:request(key)});
    },
    decide:({lotId,action,reason,key})=>call(QUALITY_RPC.decide,{
      p_lot:id(lotId,"lot_id"),p_decision:union(action,["release","hold","reject"],"decision"),
      p_reason:str(reason,"reason",3,1000),p_key:request(key)}),
    receipt:({lotId,locationId,quantity,reason,key})=>call(QUALITY_RPC.postStock,{
      p_lot:id(lotId,"lot_id"),p_location:id(locationId,"location_id"),
      p_quantity:amount(quantity),p_kind:"receipt",p_reason:str(reason,"reason",3,200),p_key:request(key)}),
    issue:({lotId,locationId,quantity,reason,key})=>call(QUALITY_RPC.postStock,{
      p_lot:id(lotId,"lot_id"),p_location:id(locationId,"location_id"),
      p_quantity:amount(quantity),p_kind:"issue",p_reason:str(reason,"reason",3,200),p_key:request(key)}),
    dispose:({lotId,locationId,quantity,reason,key})=>call(QUALITY_RPC.postStock,{
      p_lot:id(lotId,"lot_id"),p_location:id(locationId,"location_id"),
      p_quantity:amount(quantity),p_kind:"disposal",p_reason:str(reason,"reason",3,200),p_key:request(key)}),
    transfer:({lotId,fromLocationId,toLocationId,quantity,key})=>{
      const from=id(fromLocationId,"source_location"),to=id(toLocationId,"destination_location");
      if(from===to)throw new TypeError("quality_same_location_transfer");
      return call(QUALITY_RPC.transfer,{p_lot:id(lotId,"lot_id"),p_source:from,
        p_destination:to,p_quantity:amount(quantity),p_key:request(key)});
    },
    link:({parentLotId,childLotId,key})=>{
      const parent=id(parentLotId,"parent_lot"),child=id(childLotId,"child_lot");
      if(parent===child)throw new TypeError("quality_self_genealogy");
      return call(QUALITY_RPC.linkGenealogy,{p_parent:parent,p_child:child,p_key:request(key)});
    },
    recall:({rootLotId,severity,reason,key})=>call(QUALITY_RPC.startRecall,{
      p_root:id(rootLotId,"root_lot"),p_severity:union(severity,["internal","customer","critical"],"severity"),
      p_reason:str(reason,"reason",5,1000),p_key:request(key)}),
    closeRecall:({recallId,key})=>call(QUALITY_RPC.closeRecall,{
      p_recall:id(recallId,"recall_id"),p_key:request(key)}),
    fefo:({businessId,itemId,siteId,quantity})=>call(QUALITY_RPC.fefo,{
      p_business:id(businessId,"business_id"),p_item:id(itemId,"item_id"),p_site:id(siteId,"site_id"),
      p_needed:amount(quantity)}),
    listLots:({businessId})=>get(QUALITY_VIEWS.lots,{business_id:id(businessId,"business_id")}),
    listMovements:({businessId})=>get(QUALITY_VIEWS.movements,{business_id:id(businessId,"business_id")}),
    listRecalls:({businessId})=>get(QUALITY_VIEWS.recalls,{business_id:id(businessId,"business_id")}),
    getReconciliation:({businessId})=>get(QUALITY_VIEWS.reconciliation,{business_id:id(businessId,"business_id")}),
    readAudit:({businessId})=>get(QUALITY_VIEWS.audit,{business_id:id(businessId,"business_id")})
  });
}
