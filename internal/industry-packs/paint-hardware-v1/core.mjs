
/** C10-CAP-PAINT-001 Build05: synthetic-only; never call as production authority. */
import { createHash } from 'node:crypto';
const bad = c => { throw new Error(c); };
const token = (s,n='ID') => (typeof s==='string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/.test(s)) ? s : bad('INVALID_'+n);
const count = (n,k,lo=0,hi=Number.MAX_SAFE_INTEGER) => Number.isSafeInteger(n)&&n>=lo&&n<=hi ? n : bad('INVALID_'+k);
const clone = x => structuredClone(x);
const round = (x,d) => (x+d/2n)/d;
const context = c => {
  if(c?.mode!=='synthetic-only') bad('REAL_SIGNED_AUTH_NOT_CONNECTED');
  return {tenant:token(c.tenant,'TENANT'),business:token(c.business,'BUSINESS'),actor:token(c.actor,'ACTOR')};
};
const digest = x => createHash('sha256').update(JSON.stringify(x)).digest('hex');
export const BUILD05_MODE='SYNTHETIC_NON_POSTING_ONLY';
export class PaintPackDraft {
  #recipes=new Map(); #tickets=new Map(); #receipts=new Map(); #events=[];
  #call(ctx,op,rid,payload,fn) {
    const c=context(ctx), key=[c.tenant,c.business,op,token(rid,'REQUEST')].join('/');
    const hash=digest({actor:c.actor,payload}), prior=this.#receipts.get(key);
    if(prior){ if(prior.hash!==hash) bad('IDEMPOTENCY_CONFLICT'); return clone(prior.result); }
    const result=fn(c); this.#receipts.set(key,{hash,result:clone(result)}); return clone(result);
  }
  #log(c,op,id,rid,detail={}) {
    this.#events.push({seq:this.#events.length+1,tenant:c.tenant,business:c.business,actor:c.actor,op,id,requestId:rid,detail:clone(detail)});
  }
  #get(map,c,id) {
    const normalized=token(id);
    const key=map===this.#tickets ? [c.tenant,c.business,normalized].join(':') : normalized;
    const row=map.get(key);
    if(!row||row.tenant!==c.tenant||row.business!==c.business) bad('NOT_FOUND_IN_SCOPE');
    return row;
  }
  addRecipe(ctx,requestId,input) {
    return this.#call(ctx,'RECIPE',requestId,input,c=>{
      const code=token(input?.code,'RECIPE'),version=count(input?.version,'VERSION',1,9999);
      const recipeId=[c.tenant,c.business,code,'v'+version].join(':');
      if(this.#recipes.has(recipeId)) bad('IMMUTABLE_RECIPE_VERSION');
      if(typeof input?.name!=='string'||!input.name.trim()||input.name.length>120) bad('INVALID_NAME');
      if(!Array.isArray(input.pigments)||input.pigments.length===0||input.pigments.length>32) bad('INVALID_PIGMENTS');
      const names=new Set();
      const pigments=input.pigments.map(p=>{
        const sku=token(p?.sku,'PIGMENT');
        if(names.has(sku)) bad('DUPLICATE_PIGMENT'); names.add(sku);
        return {sku,ulPerL:count(p.ulPerL,'PIGMENT_UL',1,250000)};
      }).sort((a,b)=>a.sku.localeCompare(b.sku));
      if(pigments.reduce((n,p)=>n+p.ulPerL,0)>250000) bad('TINT_EXCEEDS_25_PERCENT_OF_BASE');
      const row={id:recipeId,tenant:c.tenant,business:c.business,code,version,name:input.name.trim(),
        baseSku:token(input.baseSku,'BASE'),outputSku:token(input.outputSku,'OUTPUT'),
        qcMaxDE100:count(input.qcMaxDE100,'QC_MAX',0,2000),
        doseToleranceBps:count(input.doseToleranceBps,'TOLERANCE_BPS',0,1000),
        pigments,previewOnly:true};
      this.#recipes.set(recipeId,row);this.#log(c,'RECIPE_CREATED',recipeId,requestId,{version});
      return row;
    });
  }
  openTicket(ctx,requestId,input) {
    return this.#call(ctx,'OPEN',requestId,input,c=>{
      const id=token(input?.ticketId,'TICKET'), ticketKey=[c.tenant,c.business,id].join(':');
      if(this.#tickets.has(ticketKey)) bad('DUPLICATE_TICKET_ID');
      const r=this.#get(this.#recipes,c,input.recipeId), baseML=count(input.baseML,'BASE_ML',100,200000);
      const doses=r.pigments.map(p=>({sku:p.sku,expectedUL:Number(round(BigInt(p.ulPerL)*BigInt(baseML),1000n))}));
      const t={id,tenant:c.tenant,business:c.business,recipeId:r.id,recipeVersion:r.version,
        outputSku:r.outputSku,baseSku:r.baseSku,baseML,doses,status:'DRAFT',
        mixes:[],qcChecks:[],previewOnly:true};
      this.#tickets.set(ticketKey,t);this.#log(c,'TICKET_OPENED',id,requestId,{recipeId:r.id,baseML});return t;
    });
  }
  mix(ctx,requestId,input) {
    return this.#call(ctx,'MIX',requestId,input,c=>{
      const t=this.#get(this.#tickets,c,input?.ticketId);
      if(!['DRAFT','QC_FAILED'].includes(t.status)) bad('INVALID_MIX_TRANSITION');
      const r=this.#get(this.#recipes,c,t.recipeId);
      if(!Array.isArray(input.readings)||input.readings.length!==t.doses.length) bad('INCOMPLETE_READINGS');
      const reading=new Map();
      for(const p of input.readings){const sku=token(p?.sku,'READING_PIGMENT');if(reading.has(sku))bad('DUPLICATE_READING');reading.set(sku,count(p.actualUL,'ACTUAL_UL',0,50000000));}
      const values=t.doses.map(p=>{
        if(!reading.has(p.sku))bad('MISSING_PIGMENT');
        const actualUL=reading.get(p.sku);
        if(BigInt(Math.abs(actualUL-p.expectedUL))*10000n>BigInt(p.expectedUL)*BigInt(r.doseToleranceBps))bad('DOSAGE_OUT_OF_TOLERANCE');
        return {sku:p.sku,expectedUL:p.expectedUL,actualUL};
      });
      t.mixes.push({round:t.mixes.length+1,operator:c.actor,values});t.status='MIXED';
      this.#log(c,'MIX_RECORDED',t.id,requestId,{round:t.mixes.length});return t;
    });
  }
  inspect(ctx,requestId,input) {
    return this.#call(ctx,'QC',requestId,input,c=>{
      const t=this.#get(this.#tickets,c,input?.ticketId);
      if(t.status!=='MIXED')bad('INVALID_QC_TRANSITION');
      if(t.mixes.at(-1).operator===c.actor)bad('INDEPENDENT_QC_CHECKER_REQUIRED');
      const r=this.#get(this.#recipes,c,t.recipeId);
      const deltaE100=count(input.deltaE100,'DELTA_E_100',0,10000);
      const evidenceRef=token(input.evidenceRef,'EVIDENCE');
      const pass=deltaE100<=r.qcMaxDE100;
      t.qcChecks.push({round:t.qcChecks.length+1,checker:c.actor,deltaE100,evidenceRef,pass});
      t.status=pass?'QC_PASSED':'QC_FAILED';
      this.#log(c,'QC_RECORDED',t.id,requestId,{pass,evidenceRef});return t;
    });
  }
  quote(ctx,input) {
    const c=context(ctx),t=this.#get(this.#tickets,c,input?.ticketId);
    if(t.status!=='QC_PASSED')bad('QC_PASS_REQUIRED');
    const p=input?.price;
    if(p?.source!=='canonical-readonly'||typeof p.version!=='string'||!p.version.trim())bad('VERIFIED_PRICE_SOURCE_REQUIRED');
    const unitMinor=count(p.unitMinor,'PRICE_MINOR',0,100000000000);
    const tintFeeMinor=count(p.tintFeeMinor,'TINT_FEE_MINOR',0,100000000000);
    const rebateBps=count(p.rebateBps,'REBATE_BPS',0,5000);
    const paintMinor=Number(round(BigInt(unitMinor)*BigInt(t.baseML),1000n));
    const grossMinor=paintMinor+tintFeeMinor;
    if(!Number.isSafeInteger(grossMinor))bad('MONETARY_OVERFLOW');
    const rebateMinor=Number(round(BigInt(grossMinor)*BigInt(rebateBps),10000n));
    return {ticketId:t.id,priceVersion:p.version,currency:token(p.currency,'CURRENCY'),
      paintMinor,tintFeeMinor,grossMinor,rebateBps,rebateMinor,netBeforeUnknownTaxMinor:grossMinor-rebateMinor,
      taxStatus:'UNRESOLVED',payableMinor:null,stockAvailability:'UNVERIFIED',canPost:false,previewOnly:true};
  }
  canonicalIntent(ctx,ticketId){
    const c=context(ctx),t=this.#get(this.#tickets,c,ticketId);
    if(t.status!=='QC_PASSED')bad('QC_PASS_REQUIRED');
    return {kind:'paint_tint_sale_proposal_v1',tenant:c.tenant,business:c.business,ticketId:t.id,
      outputSku:t.outputSku,volumeML:t.baseML,recipeId:t.recipeId,recipeVersion:t.recipeVersion,
      evidenceRef:t.qcChecks.at(-1).evidenceRef,
      requires:['signed_actor','canonical_stock','approved_sale','tax_policy','balanced_journal','idempotent_post'],
      canSubmit:false,canPost:false,stockChanged:false,ledgerChanged:false};
  }
  readTicket(ctx,id){return clone(this.#get(this.#tickets,context(ctx),id));}
  listTickets(ctx){const c=context(ctx);return [...this.#tickets.values()].filter(x=>x.tenant===c.tenant&&x.business===c.business).map(clone).sort((a,b)=>a.id.localeCompare(b.id));}
  audit(ctx){const c=context(ctx);return clone(this.#events.filter(x=>x.tenant===c.tenant&&x.business===c.business));}
  summary(ctx){const t=this.listTickets(ctx);const states={DRAFT:0,MIXED:0,QC_FAILED:0,QC_PASSED:0};
    for(const x of t)states[x.status]++;return {business:context(ctx).business,tickets:t.length,states,
      qcRuns:t.reduce((n,x)=>n+x.qcChecks.length,0),actualSalesMinor:null,stockRemaining:null,
      label:'SYNTHETIC_TINT_WORKFLOW_NOT_FINANCIAL'};}
}
