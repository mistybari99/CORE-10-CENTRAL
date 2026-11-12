
/**
 * Loopback-only, clearly labelled SYNTHETIC Build05 review preview.
 * No Supabase/Auth, no real data, no real transactions, no remote serving.
 */
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {dirname,join} from 'node:path';
import {PaintPackDraft} from './core.mjs';
import {PaintDealerDraft} from './dealership.mjs';
const ROOT=dirname(fileURLToPath(import.meta.url));
const actor=(actor='owner')=>({mode:'synthetic-only',tenant:'DEMO-T',business:'DEMO-PAINT',actor});
const evidence=(type,data={})=>({source:'canonical-readonly',type,tenant:'DEMO-T',business:'DEMO-PAINT',version:'demo-v1',...data});
const json=(res,status,data)=>{
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(JSON.stringify(data));
};
const asError=e=>({ok:false,error:e?.message||'UNEXPECTED_ERROR'});
const fixture=()=>{
  const tint=new PaintPackDraft(),dealer=new PaintDealerDraft();
  const recipe=tint.addRecipe(actor('owner'),'demo-f01',{
    code:'GOLD-WARM',version:1,name:'Demo Warm Gold',baseSku:'BASE-WHITE',
    outputSku:'TINT-WARM-GOLD',qcMaxDE100:180,doseToleranceBps:200,
    pigments:[{sku:'YELLOW',ulPerL:12000},{sku:'RED',ulPerL:4000}]
  });
  dealer.addPack(actor(),'demo-p01',{packId:'PK4',sku:'TINT-WARM-GOLD',uom:'L',capacityML:4000});
  dealer.addDealer(actor(),'demo-d01',{dealerId:'DL1',status:'ACTIVE',currency:'BDT',creditLimitMinor:200000,termsVersion:'T1'});
  dealer.addPrincipalScheme(actor(),'demo-s01',{
    schemeId:'S1',version:1,principalId:'PRINCIPAL1',sku:'BASE-WHITE',
    validFrom:'2026-01-01',validTo:'2026-12-31',rateBps:1000,currency:'BDT'
  });
  dealer.addCheque(actor(),'demo-c01',{
    bankCode:'BANK1',issuerId:'DL1',chequeNumber:'000123',
    maturityDate:'2026-11-25',currency:'BDT',amountMinor:100000
  });
  dealer.addSds(actor(),'demo-sds01',{
    sku:'PIGMENT-RED',revision:'R3',documentRef:'SDS-DEMO-R3',
    expiresOn:'2026-11-30',hazardClass:'FLAMMABLE',allowedStorageClasses:['SAFE-FLAM']
  });
  dealer.addSerial(actor(),'demo-h01',{
    sku:'DRILL',serial:'S0001',variant:'12MM',unit:'PCS',warrantyMonths:12
  });
  return {tint,dealer,recipe,step:0,ticket:null,lastNote:'ডেমো প্রস্তুত—Start Tint চাপুন।'};
};
const sample=g=>{
  const price=g.ticket&&g.ticket.status==='QC_PASSED'
    ?g.tint.quote(actor(),{ticketId:g.ticket.id,price:{
      source:'canonical-readonly',version:'P-01',currency:'BDT',unitMinor:19999,tintFeeMinor:2500,rebateBps:1000}})
    :null;
  const dealerCredit=g.dealer.creditCheck(actor(),{dealerId:'DL1',asOf:'2026-11-12',requestedMinor:30000,
    exposureSnapshot:evidence('receivables-exposure',{
      dealerId:'DL1',currency:'BDT',status:'VERIFIED',termsVersion:'T1',asOf:'2026-11-12',
      approvedReceivablesMinor:150000,pendingOrdersMinor:30000
    })});
  const scheme=g.dealer.previewScheme(actor(),{schemeId:'S1:v1',asOf:'2026-11-12',
    invoiceSnapshot:evidence('principal-purchase-invoice',{
      date:'2026-06-15',principalId:'PRINCIPAL1',sku:'BASE-WHITE',invoiceId:'INV-01',
      status:'APPROVED',returnStatus:'PARTIAL_RETURN',currency:'BDT',approvedMinor:100000,returnedMinor:20000
    })});
  const sds=g.dealer.storageCheck(actor(),{sdsId:'PIGMENT-RED:R3',asOf:'2026-11-12',storageClass:'SAFE-FLAM'});
  const profitability=g.dealer.profitability(actor(),{
    sales:evidence('sales-return-summary',{currency:'BDT',grossMinor:100000,returnsMinor:10000}),
    cost:evidence('certified-cost-summary',{currency:'BDT',certification:'UNVERIFIED',allFreightIncluded:false,cogsMinor:50000}),
    rebates:evidence('rebate-reconciliation',{currency:'BDT',pendingMinor:10000,receivedEvidenceMinor:0}),
    credit:evidence('credit-summary',{currency:'BDT',outstandingMinor:150000})
  });
  return {
    ok:true,mode:'SYNTHETIC_ONLY',step:g.step,recipe:{code:g.recipe.code,version:g.recipe.version,
      pigments:g.recipe.pigments,outputSku:g.recipe.outputSku},
    ticket:g.ticket,quote:price,credit:dealerCredit,scheme,sds,profitability,
    pack:g.dealer.packPrice(actor(),{packId:'PK4',priceSnapshot:evidence('approved-pack-price',{
      packId:'PK4',sku:'TINT-WARM-GOLD',currency:'BDT',priceMinor:120000
    })}),
    pdc:'INSTRUMENT_HELD · NOT CASH',hardware:'DRILL 12MM · Serial S0001 · UNSOLD',
    trail:g.tint.audit(actor()).slice(-8),summary:g.tint.summary(actor()),lastNote:g.lastNote,
    postingAllowed:false};
};
export function createDemoServer({port=4377}={}){
  let scenario=fixture();
  const secret=randomBytes(24).toString('hex');
  const files={'/lab.css':'text/css; charset=utf-8','/lab.js':'text/javascript; charset=utf-8'};
  const server=createServer(async(req,res)=>{
    try {
      // Deny DNS-rebinding and remote host aliases. This is a local synthetic lab.
      if(!/^127\.0\.0\.1(?::\d+)?$/.test(req.headers.host||'')) return json(res,403,asError(new Error('LOOPBACK_ONLY')));
      const uri=new URL(req.url,'http://127.0.0.1');
      if(req.method==='GET'&&(uri.pathname==='/'||uri.pathname in files)){
        const name=uri.pathname==='/'?'lab.html':uri.pathname.slice(1);
        let body=await readFile(join(ROOT,name),'utf8');
        if(uri.pathname==='/')body=body.replace('__DEMO_TOKEN__',secret);
        res.writeHead(200,{'Content-Type':uri.pathname==='/'?'text/html; charset=utf-8':files[uri.pathname],
          'Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
          'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
        return res.end(body);
      }
      if(req.method==='GET'&&uri.pathname==='/api/state')return json(res,200,sample(scenario));
      if(req.method==='POST'&&uri.pathname==='/api/step'){
        if(req.headers['x-demo-token']!==secret||!['','http://127.0.0.1:'+server.address().port].includes(req.headers.origin||''))
          return json(res,403,asError(new Error('DEMO_TOKEN_REQUIRED')));
        let body='';for await(const piece of req){body+=piece;if(body.length>1024)return json(res,413,asError(new Error('PAYLOAD_TOO_LARGE')));}
        let action;try{({action}=JSON.parse(body))}catch{return json(res,400,asError(new Error('INVALID_JSON')))}
        if(!['start','mix','qc-fail','rework','qc-pass','reset'].includes(action))
          return json(res,400,asError(new Error('INVALID_DEMO_ACTION')));
        if(action==='reset'){scenario=fixture();return json(res,200,sample(scenario));}
        const g=scenario,round=g.step+1;
        try{
          switch(action){
            case 'start':
              if(g.ticket)throw new Error('TICKET_ALREADY_EXISTS');
              g.ticket=g.tint.openTicket(actor('operator'),'demo-start-'+round,{ticketId:'T-0001',
                recipeId:g.recipe.id,baseML:2500});g.lastNote='Tint ticket তৈরি হয়েছে; এখন Mix করুন।';break;
            case 'mix':
              g.ticket=g.tint.mix(actor('mixer'),'demo-mix-'+round,{
                ticketId:'T-0001',readings:[{sku:'YELLOW',actualUL:30000},{sku:'RED',actualUL:10000}]});
              g.lastNote='Measured mixing শেষ। আলাদা QC reviewer প্রয়োজন।';break;
            case 'qc-fail':
              g.ticket=g.tint.inspect(actor('checker'),'demo-qcf-'+round,{
                ticketId:'T-0001',deltaE100:230,evidenceRef:'QC-FAIL'});
              g.lastNote='QC failed; output quarantine/rework প্রয়োজন।';break;
            case 'rework':
              g.ticket=g.tint.mix(actor('mixer'),'demo-rework-'+round,{
                ticketId:'T-0001',readings:[{sku:'YELLOW',actualUL:30000},{sku:'RED',actualUL:10000}]});
              g.lastNote='Rework logged; QC আবার করুন।';break;
            case 'qc-pass':
              g.ticket=g.tint.inspect(actor('checker'),'demo-qcp-'+round,{
                ticketId:'T-0001',deltaE100:120,evidenceRef:'QC-PASS'});
              g.lastNote='QC passed; Quote preview দেখা যাবে। কোনো stock বা sale post হয়নি।';break;
          }
          g.step++;return json(res,200,sample(g));
        }catch(e){return json(res,422,asError(e));}
      }
      return json(res,404,asError(new Error('NOT_FOUND')));
    }catch(e){return json(res,500,asError(e));}
  });
  return {server,listen:()=>new Promise(resolve=>server.listen(port,'127.0.0.1',()=>resolve(server.address().port))),
    close:()=>new Promise((resolve,reject)=>server.close(err=>err?reject(err):resolve()))};
}
if(process.argv.includes('--demo-run')){
  const demo=createDemoServer({port:Number(process.env.PAINT_DEMO_PORT||4377)});
  demo.listen().then(port=>process.stdout.write('SYNTHETIC PAINT LAB ONLY http://127.0.0.1:'+port+'\n'));
}
