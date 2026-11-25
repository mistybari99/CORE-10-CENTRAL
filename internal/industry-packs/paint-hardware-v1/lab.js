
const token=document.querySelector('meta[name="demo-token"]').content;
const $=id=>document.getElementById(id);
const fmt=n=>n==null?'UNKNOWN':new Intl.NumberFormat('en-BD',{maximumFractionDigits:2}).format(n/100)+' BDT';
const set=(id,v)=>{$(id).textContent=String(v??'—')};
let state=null,busy=false;
async function getState(){
  const r=await fetch('/api/state',{cache:'no-store'});if(!r.ok)throw new Error('Unable to load lab state');return r.json();
}
function render(s){
  state=s;
  const t=s.ticket,st=t?.status||'NOT_STARTED';
  set('workflow-status',st);$('workflow-status').className='status '+(st==='QC_PASSED'?'passed':st==='QC_FAILED'?'failed':'');
  set('formula-id',s.recipe.code);set('formula-version','Revision v'+s.recipe.version);
  set('base-volume',t?(t.baseML/1000).toFixed(2)+' L':'2.50 L planned');
  set('qc-rounds',t?.qcChecks?.length||0);
  set('ticket-id',t?.id||'Not created');set('output-sku',t?.outputSku||s.recipe.outputSku);
  set('tint-doses',t?.doses?.map(p=>p.sku+' '+p.expectedUL+'µL').join(' · ')||'—');
  set('qc-evidence',t?.qcChecks?.at(-1)?.evidenceRef||'No evidence');
  set('notice',s.lastNote||'Synthetic only');
  set('quote-value',s.quote?fmt(s.quote.netBeforeUnknownTaxMinor):'QC pass required');
  set('quote-source',s.quote?'Price version '+s.quote.priceVersion+' · Tax unknown · NOT payable':'No sale invoice or stock posting');
  set('credit-status',s.credit.withinLimit?'Within limit':'Over limit · Block');
  set('credit-detail',fmt(s.credit.projectedExposureMinor)+' exposure vs '+fmt(s.credit.creditLimitMinor)+' approved credit');
  set('scheme-value',fmt(s.scheme.estimatedRebateMinor));
  set('scheme-detail',fmt(s.scheme.eligibleMinor)+' eligible purchase · Pending approval');
  set('profit-value',s.profitability.grossMarginMinor===null?'UNKNOWN':fmt(s.profitability.grossMarginMinor));
  set('profit-detail','Pending rebate '+fmt(s.profitability.pendingRebatesExcludedFromProfitMinor)+' excluded · Net profit unknown');
  set('sds-status',s.sds.allowedForDraftHandling?'Storage class compatible':'Handling blocked');
  set('sds-detail','SDS revision '+s.sds.revision+' · Dispatch not authorized');
  set('pdc-detail',s.pdc);set('serial-detail',s.hardware);
  const audit=$('audit-list');audit.replaceChildren();
  const events=s.trail||[];
  if(!events.length){const li=document.createElement('li');li.textContent='No events';audit.append(li);}
  for(const event of events){
    const li=document.createElement('li'),left=document.createElement('span'),right=document.createElement('span');
    left.textContent=event.op;right.textContent=event.actor+' · '+event.id;
    li.append(left,right);audit.append(li);
  }
  const options={start:!t,mix:st==='DRAFT','qc-fail':st==='MIXED',rework:st==='QC_FAILED','qc-pass':st==='MIXED',reset:true};
  for(const b of document.querySelectorAll('[data-action]')) b.disabled=busy||!options[b.dataset.action];
}
async function step(action){
  if(busy)return;busy=true;for(const b of document.querySelectorAll('[data-action]'))b.disabled=true;
  try{
    const r=await fetch('/api/step',{method:'POST',headers:{'Content-Type':'application/json','X-Demo-Token':token},body:JSON.stringify({action})});
    const s=await r.json();
    if(!r.ok){set('notice','Blocked: '+s.error);return;}
    render(s);
  }catch(e){set('notice','Preview error: '+e.message)}
  finally{busy=false;if(state)render(state);}
}
document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',()=>step(b.dataset.action)));
getState().then(render).catch(e=>set('notice',e.message));
