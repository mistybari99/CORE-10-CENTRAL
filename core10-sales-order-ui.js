/* NP03B: embeddable Sales Order workspace. The Central host owns navigation,
 * signed Supabase configuration and session lifecycle. No independent shell. */
(function(root,factory){"use strict";const a=factory();if(typeof module==="object"&&module.exports)module.exports=a;if(root)root.CORE10_SALES_ORDER_UI=a;})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const WORDS={
  title:['বিক্রয় অর্ডার','Sales orders'],subtitle:['একই ব্যবসা ও সাইটে খসড়া, অনুমোদন এবং অডিট।','Drafts, approvals and audit in one business and site.'],
  synthetic:['সিনথেটিক প্রদর্শনী · বাস্তব গ্রাহক, টাকা বা স্টক নয়','Synthetic demonstration · no real customers, money or stock'],
  signed:['সাইন-ইন করা backend · অনুমতি ও ফলাফল server যাচাই করে','Signed backend · permissions and results are verified by the server'],
  boundary:['এই ধাপে invoice, টাকা সংগ্রহ বা স্টক পোস্ট হয় না।','This step does not issue invoices, collect money or post stock.'],
  business:['ব্যবসা','Business'],site:['সাইট','Site'],refresh:['পুনরায় লোড','Refresh'],newOrder:['নতুন অর্ডার','New order'],
  orders:['অর্ডার তালিকা','Order list'],empty:['এই সাইটে অর্ডার নেই। প্রথম খসড়া তৈরি করুন।','No orders at this site. Create the first draft.'],
  draft:['খসড়া','Draft'],confirmed:['নিশ্চিত','Confirmed'],cancelled:['বাতিল','Cancelled'],customer:['গ্রাহক','Customer'],
  priceList:['মূল্যতালিকা','Price list'],product:['পণ্য / ভ্যারিয়েন্ট / একক','Product / variant / unit'],quantity:['পরিমাণ','Quantity'],
  price:['একক মূল্য','Unit price'],discount:['ছাড় %','Discount %'],tax:['কর %','Tax %'],remove:['লাইন সরান','Remove line'],
  addLine:['পণ্য যোগ করুন','Add item'],save:['খসড়া সংরক্ষণ','Save draft'],confirm:['অর্ডার নিশ্চিত করুন','Confirm order'],
  cancel:['খসড়া বাতিল করুন','Cancel draft'],audit:['অডিট ইতিহাস','Audit history'],auditEmpty:['কোনো অডিট ইভেন্ট নেই।','No audit events.'],actor:['যিনি করেছেন','Performed by'],
  total:['Server-যাচাইকৃত মোট','Server-validated total'],estimate:['আনুমানিক মোট · সংরক্ষণে server যাচাই করবে','Estimated total · server validates on save'],
  loading:['অনুমোদিত তথ্য লোড হচ্ছে…','Loading authorized records…'],ready:['সাইটের তথ্য হালনাগাদ।','Site records refreshed.'],
  saved:['Server খসড়া সংরক্ষণ করেছে।','The server saved the draft.'],done:['Server অর্ডারের অবস্থা বদলেছে।','The server changed the order status.'],
  denied:['এই Sales workspace-এর অনুমতি নেই বা সেশন শেষ। আবার সাইন ইন করুন।','Sales workspace access is denied or the session ended. Sign in again.'],
  missingMaster:['Master catalog সংযুক্ত হয়নি। সংরক্ষিত অর্ডার দেখা যাবে; নতুন খসড়া ও সংশোধন বন্ধ।','Master catalog is not connected. Existing orders remain readable; new drafts and amendments are locked.'],
  disabled:['Owner এই অর্ডার কার্যক্রম বন্ধ রেখেছেন। Control Centre-এ পর্যালোচনা করুন।','The Owner has disabled this order action. Review it in the Control Centre.'],
  disconnected:['প্রয়োজনীয় backend সংযোগ নেই। সংযোগ চালু হলে পুনরায় লোড করুন।','A required backend connection is unavailable. Refresh after it is connected.'],
  stale:['অর্ডারটি অন্য কেউ বদলেছেন। পুনরায় লোড করে সর্বশেষ অর্ডার খুলুন।','Someone changed this order. Refresh and open the latest revision.'],
  rejected:['Server আবেদন গ্রহণ করেনি। পণ্য, মূল্য, অনুমোদন ও বর্তমান সীমা যাচাই করুন।','The server rejected the request. Check items, prices, approval and current limits.'],
  network:['ফলাফল নিশ্চিত হয়নি। একই তথ্য রেখে আবার চেষ্টা করলে একই request ব্যবহার হবে।','The result is uncertain. Retry with unchanged input to reuse the same request.'],
  approval:['অনুমোদন আবেদনের নম্বর','Approval request reference'],approvalHelp:['অনুমোদন বর্তমান অর্ডার ও revision-এর সঙ্গে মিলতে হবে।','Approval must match this order and its current revision.'],
  approvalNeeded:['প্রয়োজনীয় অনুমোদন সম্পূর্ণ হয়নি। Approval desk-এ বর্তমান আবেদন পর্যালোচনা করুন।','Required approval is incomplete. Review the current request in the approval desk.'],
  immutable:['এই অর্ডার আর সম্পাদনাযোগ্য নয়। অডিট ইতিহাস দেখা যাবে।','This order is no longer editable. Its audit history remains available.'],
  select:['অর্ডার খুলুন অথবা নতুন খসড়া তৈরি করুন।','Open an order or start a new draft.'],revision:['Revision','Revision'],
  scopeHint:['ব্যবসা বা সাইট বদলালে অসম্পূর্ণ ফর্ম পরিষ্কার হবে।','Changing business or site clears the unfinished form.'],
  retry:['আবার চেষ্টা করুন','Retry'],saveFirst:['আগে খসড়া সংরক্ষণ করুন।','Save the draft first.'],
  unsaved:['ফর্মে অসংরক্ষিত তথ্য আছে। আগে সংরক্ষণ করুন, অথবা স্পষ্টভাবে বাদ দিয়ে এগোন।','The form has unsaved input. Save it first, or explicitly discard it to continue.'],
  discard:['অসম্পূর্ণ ফর্ম বাদ দিয়ে এগোন','Discard unfinished form and continue']
 };
 const obj=x=>!!x&&typeof x==='object'&&!Array.isArray(x),id=x=>Number.isSafeInteger(x)&&x>0;
 function mount(host,options){
  if(!host?.ownerDocument||!options?.api)throw Error('SALES_UI_HOST_REQUIRED');
  const doc=host.ownerDocument,api=options.api,mode=options.backendMode;
  if(!['signed','synthetic'].includes(mode))throw Error('SALES_UI_MODE_REQUIRED');
  let lang=options.lang==='en'?'en':'bn',epoch=0,disposed=false,busy=false,context=null,business=null,site=null;
  let orders=[],controls=[],catalog=null,selected=null,draft=null,audits=null,notice='',tone='',requests=new Map(),pendingNav=null,uncertain=null,focusHint=null;
  const t=k=>WORDS[k]?.[lang==='bn'?0:1]||k;
  function el(tag,cls,text){const x=doc.createElement(tag);if(cls)x.className=cls;if(text!=null)x.textContent=String(text);return x;}
  function button(text,fn,disabled=false,cls='outline'){const x=el('button',cls,text);x.type='button';const semantic=Object.keys(WORDS).find(k=>t(k)===text);if(semantic)x.dataset.soFocus=semantic;x.disabled=disabled;x.addEventListener('click',fn);return x;}
  function label(text,input){const x=el('label','so-label');x.append(el('span',null,text),input);return x;}
  function money(v,currency='BDT'){return new Intl.NumberFormat(lang==='bn'?'bn-BD':'en-GB',{style:'currency',currency,maximumFractionDigits:6}).format(v);}
  function currentControl(key){return controls.find(c=>c.feature_key===key);}
  function allowed(key){return !busy&&!uncertain&&currentControl(key)?.enabled===true;}
  function validCatalog(c){
   if(!obj(c)||c.businessId!==business||c.siteId!==site||!(c.source==='canonical_master'||mode==='synthetic'&&c.source==='synthetic_fixture'))return null;
   if(!['customers','priceLists','items'].every(k=>Array.isArray(c[k])&&c[k].length&&c[k].every(r=>obj(r)&&id(r.id)&&typeof r.label==='string')))return null;
   if(c.priceLists.some(r=>!/^[A-Z]{3}$/.test(r.currency))||c.items.some(r=>!id(r.uomId)||!obj(r.prices)||r.variantId!=null&&!id(r.variantId)||c.priceLists.some(p=>typeof r.prices[p.id]!=='number'||!Number.isFinite(r.prices[p.id])||r.prices[p.id]<0)))return null;
   return structuredClone(c);
  }
  function message(error){const x=String(error?.code||error?.message||error);
   if(/RPC_UNAVAILABLE|NO_RECEIPT|NETWORK|fetch|timeout/i.test(x))return ['network','error'];
   if(/AUTH|SESSION|SCOPE|FORBIDDEN|DENIED|actor/i.test(x))return ['denied','error'];
   if(/CONTROL_DISABLED/.test(x))return ['disabled','error'];
   if(/NOT_CONNECTED|function .*does not exist|PGRST202|42883/.test(x))return ['disconnected','error'];
   if(/STALE|TOTAL_CHANGED/.test(x))return ['stale','error'];
   if(/APPROVAL|approval_/.test(x))return ['approvalNeeded','error'];
   if(/network|fetch|uncertain|SERVER_RESPONSE/i.test(x))return ['network','error'];return ['rejected','error'];
  }
  function clearScope(){epoch++;orders=[];controls=[];catalog=null;selected=null;draft=null;audits=null;requests.clear();pendingNav=null;uncertain=null;focusHint=null;notice='';tone='';}
  function clearPrivate(){clearScope();context=null;business=null;site=null;}
  function keyFor(kind,input){const signature=JSON.stringify(input),old=requests.get(kind);if(old?.signature===signature)return old.key;
   if(!globalThis.crypto?.randomUUID)throw Error('SECURE_ID_REQUIRED');const key='sales-'+crypto.randomUUID().replaceAll('-','');requests.set(kind,{signature,key});return key;}
  function rowLabel(r){return r?(lang==='en'?r.labelEn:r.labelBn)||r.label:'';}
  function uomLabel(r){return (lang==='en'?r.uomLabelEn:r.uomLabelBn)||r.uomLabel||String(r.uomId);}
  function selectBox(rows,value,onChange,focusId){const x=el('select');if(focusId)x.dataset.soFocus=focusId;for(const r of rows){const o=el('option',null,rowLabel(r));o.value=String(r.id);x.append(o);}x.value=String(value??'');x.disabled=busy||!!uncertain;x.addEventListener('change',()=>onChange(Number(x.value)));return x;}
  function selectedPriceList(){return catalog?.priceLists.find(p=>p.id===draft?.price_list_id);}
  function itemFor(line){return catalog?.items.find(p=>p.id===line.item_id&&(p.variantId??null)===(line.variant_id??null)&&p.uomId===line.uom_id);}
  function newLine(item){return {item_id:item.id,variant_id:item.variantId??null,uom_id:item.uomId,quantity:1,unit_price:Number(item.prices[draft.price_list_id]),discount_percent:0,tax_percent:0};}
  function canEdit(){return !!catalog&&!!draft&&(!selected||selected.status==='draft')&&!busy&&allowed('sales.order_draft');}
  function isDirty(){return !!draft&&(!selected||selected.status==='draft'&&JSON.stringify(draft)!==JSON.stringify(selected.document));}
  function navigate(fn){if(busy)return;if(uncertain){notice='network';tone='error';render();return;}if(isDirty()){pendingNav=fn;notice='unsaved';tone='error';render();return;}return fn();}
  function markDirty(){if(!selected||!draft)return;const dirty=JSON.stringify(draft)!==JSON.stringify(selected.document);for(const b of host.querySelectorAll('.so-transitions button'))b.disabled=dirty||!allowed('sales.order_transition');}
  function openOrder(o){epoch++;selected=o;draft=structuredClone(o.document);audits=null;notice='';render();focusDetail();}
  function startDraft(){if(!catalog)return;epoch++;selected=null;audits=null;draft={customer_id:catalog.customers[0].id,price_list_id:catalog.priceLists[0].id,currency:catalog.priceLists[0].currency,lines:[]};draft.lines.push(newLine(catalog.items[0]));notice='';render();focusDetail();}
  async function action(fn,success,mutation=false){const mine=epoch;busy=true;notice='loading';tone='';render();try{await fn();if(mine===epoch&&!disposed){notice=success;tone='';}}
   catch(e){if(mine===epoch&&!disposed){[notice,tone]=message(e);if(notice==='network'&&mutation)uncertain={fn,success};if(notice==='denied'){clearPrivate();notice='denied';tone='error';busy=false;render();}}}
   finally{if(mine===epoch&&!disposed){busy=false;render();}}}
  async function loadScope(){const mine=epoch,b=business,s=site;if(!b||!s){render();return;}
   await action(async()=>{const [r,c,m]=await Promise.all([api.read({businessId:b,siteId:s}),api.controls({businessId:b,siteId:s}),options.catalogProvider?options.catalogProvider({businessId:b,siteId:s}):null]);
    if(mine!==epoch||disposed)return;orders=r.items;controls=c;catalog=validCatalog(m);},'ready');}
  async function boot(){clearPrivate();busy=true;notice='loading';render();const mine=epoch;try{const c=await api.context();if(mine!==epoch||disposed)return;
    if(!Array.isArray(c.sites))throw Error('SALES_UI_SCOPE_DENIED');context=c;
    const list=c.businesses.filter(b=>b.can_manage===true);if(!list.length)throw Error('SALES_UI_SCOPE_DENIED');
    const wanted=options.initialScope;
    if(wanted&&(!obj(wanted)||!id(wanted.businessId)||!id(wanted.siteId)||!list.some(b=>b.id===wanted.businessId)||!c.sites.some(s=>s.id===wanted.siteId&&s.business_id===wanted.businessId)))throw Error('SALES_UI_SCOPE_DENIED');
    business=wanted?wanted.businessId:list[0].id;site=wanted?wanted.siteId:c.sites.find(s=>s.business_id===business)?.id??null;busy=false;await loadScope();
   }catch(e){if(mine===epoch&&!disposed){clearPrivate();[notice,tone]=message(e);busy=false;render();}}}
  function drawHeader(){const top=el('div','so-heading'),heading=el('div');heading.append(el('h2',null,t('title')),el('p','so-muted',t('subtitle')));
   top.append(heading,button(lang==='bn'?'English':'বাংলা',()=>{lang=lang==='bn'?'en':'bn';render();},busy));top.querySelector('button').dataset.soFocus='language';host.append(top);
   const boundary=el('div','so-boundary');boundary.dataset.mode=mode;boundary.append(el('strong',null,t(mode)),el('p',null,t('boundary')));host.append(boundary);
  }
  function drawScope(){if(!context)return;const box=el('div','so-scope');
   const bs=context.businesses.filter(b=>b.can_manage===true).map(b=>({id:b.id,label:b.label||b.slug||String(b.id)}));
   box.append(label(t('business'),selectBox(bs,business,b=>navigate(()=>{clearScope();business=b;site=context.sites.find(s=>s.business_id===b)?.id??null;render();loadScope();}),'business')),
    label(t('site'),selectBox(context.sites.filter(s=>s.business_id===business).map(s=>({id:s.id,label:s.label})),site,s=>navigate(()=>{clearScope();site=s;render();loadScope();}),'site')),
    button(t('refresh'),()=>navigate(()=>{clearScope();render();loadScope();}),busy||!!uncertain));host.append(box,el('p','so-muted',t('scopeHint')));
  }
  function drawList(root){const head=el('div','so-section-heading');head.append(el('h3',null,t('orders')),button(t('newOrder'),()=>navigate(startDraft),!catalog||!allowed('sales.order_draft'),'primary'));root.append(head);
   if(!orders.length)root.append(el('p','so-empty',busy?t('loading'):t('empty')));
   const list=el('ul','so-orders');for(const o of orders){const li=el('li'),b=button('',()=>navigate(()=>openOrder(o)),busy||!!uncertain,'so-order');b.dataset.order=String(o.id);b.setAttribute('aria-pressed',String(selected?.id===o.id));
    const line=el('span','so-order-top');line.append(el('strong',null,'#'+o.id),el('span','so-state',t(o.status)));b.append(line,el('span',null,rowLabel(catalog?.customers.find(c=>c.id===o.customer_id))||t('customer')+' #'+o.customer_id),el('span','so-muted',money(o.total,o.currency)+' · '+t('revision')+' '+o.version));li.append(b);list.append(li);}root.append(list);
  }
  function numberField(key,line,index,min,max){const input=el('input');input.type='number';input.step='any';if(key==='quantity'){const item=itemFor(line),decimals=item?.quantityDecimals;if(Number.isInteger(decimals)&&decimals>=0&&decimals<=6){input.step=String(10**-decimals);min=Math.max(10**-decimals,item.minQuantity||0);}}input.min=String(min);if(max!=null)input.max=String(max);input.required=true;input.value=String(line[key]);input.disabled=!canEdit()||(key==='tax_percent'&&currentControl('sales.order_draft')?.params?.tax_enabled!==true);
   input.dataset.field=key;input.dataset.line=String(index);input.addEventListener('input',()=>{line[key]=input.value===''?null:Number(input.value);updateEstimate();markDirty();});return label(t({unit_price:'price',discount_percent:'discount',tax_percent:'tax'}[key]||key),input);}
  function estimate(){if(!draft)return null;let sum=0;for(const l of draft.lines){if(['quantity','unit_price','discount_percent','tax_percent'].some(k=>typeof l[k]!=='number'||!Number.isFinite(l[k])))return null;sum+=l.quantity*l.unit_price*(1-l.discount_percent/100)*(1+l.tax_percent/100);}return sum;}
  function updateEstimate(){const x=host.querySelector('.so-estimate-value');if(x){const v=estimate();x.textContent=v===null?'—':money(v,draft.currency);}}
  function drawForm(root){if(!draft){root.append(el('p','so-empty',t('select')));return;}
   const h=el('div','so-section-heading');h.append(el('h3',null,selected?'#'+selected.id+' · '+t(selected.status):t('newOrder')));root.append(h);
   if(selected)root.append(el('p','so-muted',t('revision')+' '+selected.version+' · '+t('total')+': '+money(selected.total,selected.currency)));
   if(!catalog){root.append(el('p','so-note',t('missingMaster')));drawReadLines(root);drawAudit(root);return;}
   const form=el('form','so-form'),top=el('div','so-form-grid');
   const customer=selectBox(catalog.customers,draft.customer_id,v=>{draft.customer_id=v;markDirty();});customer.dataset.soFocus='customer';customer.disabled=!canEdit();
   const pricelist=selectBox(catalog.priceLists,draft.price_list_id,v=>{draft.price_list_id=v;draft.currency=selectedPriceList().currency;for(const l of draft.lines){const p=itemFor(l);l.unit_price=Number(p?.prices[v]);}render();});pricelist.dataset.soFocus='priceList';pricelist.disabled=!canEdit();
   top.append(label(t('customer'),customer),label(t('priceList'),pricelist));form.append(top);
   draft.lines.forEach((line,index)=>{const group=el('fieldset','so-line');group.append(el('legend',null,t('product')+' '+(index+1)));
    const pick=el('select');catalog.items.forEach((p,i)=>{const o=el('option',null,rowLabel(p)+' · '+uomLabel(p));o.value=String(i);pick.append(o);});pick.value=String(catalog.items.indexOf(itemFor(line)));pick.required=true;pick.disabled=!canEdit();pick.dataset.product=String(index);
    pick.addEventListener('change',()=>{draft.lines[index]=newLine(catalog.items[Number(pick.value)]);render();});group.append(label(t('product'),pick));
    const fields=el('div','so-line-numbers');fields.append(numberField('quantity',line,index,0.000001,currentControl('sales.order_draft')?.params?.max_quantity),numberField('unit_price',line,index,0),numberField('discount_percent',line,index,0,currentControl('sales.order_draft')?.params?.max_discount_percent??100),numberField('tax_percent',line,index,0,100));group.append(fields,button(t('remove'),()=>{draft.lines.splice(index,1);render();host.querySelector('[data-product="'+Math.min(index,draft.lines.length-1)+'"]')?.focus();},!canEdit()||draft.lines.length===1));form.append(group);
   });
   const lineMax=currentControl('sales.order_draft')?.params?.max_lines??100;
   form.append(button(t('addLine'),()=>{draft.lines.push(newLine(catalog.items[0]));render();host.querySelector('[data-product="'+(draft.lines.length-1)+'"]')?.focus();},!canEdit()||draft.lines.length>=lineMax));
   const total=el('p','so-estimate');total.append(el('span',null,t('estimate')),el('strong','so-estimate-value'));form.append(total);
   const submit=el('button','primary',t('save'));submit.type='submit';submit.disabled=!canEdit();submit.dataset.action='save';form.append(submit);
   form.addEventListener('submit',e=>{e.preventDefault();if(!canEdit()||!form.reportValidity())return;const document=structuredClone(draft),b=business,s=site,mine=epoch;
    const input={businessId:b,siteId:s,orderId:selected?.id??null,expectedVersion:selected?.version??0,document};
    action(async()=>{const r=await api.save({...input,requestKey:keyFor('save',input)});if(mine!==epoch||disposed)return;const fresh=await api.read({businessId:b,siteId:s});if(mine!==epoch||disposed)return;orders=fresh.items;selected=orders.find(o=>o.id===r.order_id)||null;draft=selected?structuredClone(selected.document):null;audits=null;pendingNav=null;},'saved',true);});root.append(form);updateEstimate();
   if(selected?.status==='draft')drawTransitions(root);else if(selected)root.append(el('p','so-note',t('immutable')));drawAudit(root);
  }
  function drawReadLines(root){const list=el('ul','so-read-lines');for(const l of draft.lines)list.append(el('li',null,t('product')+' #'+l.item_id+' · '+l.quantity+' × '+money(l.unit_price,draft.currency)));root.append(list);}
  function drawTransitions(root){const group=el('div','so-transitions');const c=currentControl('sales.order_transition'),stages=c?.stages??0,dirty=JSON.stringify(draft)!==JSON.stringify(selected.document);let approval=null;
   if(dirty)group.append(el('p','so-note',t('saveFirst')));
   if(stages>0){const input=el('input');input.type='number';input.min='1';input.step='1';input.placeholder='';input.dataset.approval='true';input.disabled=busy;input.addEventListener('input',()=>{approval=input.value?Number(input.value):null;});group.append(label(t('approval')+' · '+stages, input),el('p','so-muted',t('approvalHelp')));}
   for(const name of ['confirm','cancel'])group.append(button(t(name),()=>{if(stages>0&&!id(approval)){notice='approvalNeeded';tone='error';render();return;}
    const b=business,s=site,o=selected.id,mine=epoch,input={businessId:b,siteId:s,orderId:o,action:name,expectedVersion:selected.version,approvalId:approval};
    action(async()=>{await api.transition({...input,requestKey:keyFor(name,input)});if(mine!==epoch||disposed)return;const fresh=await api.read({businessId:b,siteId:s});if(mine!==epoch||disposed)return;orders=fresh.items;selected=orders.find(x=>x.id===o);draft=selected?structuredClone(selected.document):null;audits=null;},'done',true);},dirty||!allowed('sales.order_transition'),name==='cancel'?'outline so-danger':'outline'));
   root.append(group);
  }
  function drawAudit(root){if(!selected)return;const section=el('section','so-audit');section.append(button(t('audit'),()=>{const b=business,s=site,o=selected.id,mine=epoch;action(async()=>{const r=await api.audit({businessId:b,siteId:s,orderId:o});if(mine===epoch&&!disposed)audits=r.items;},'ready');},busy));
   if(audits){if(!audits.length)section.append(el('p','so-muted',t('auditEmpty')));const list=el('ol');for(const a of audits){const li=el('li'),actionName={'sales.draft_saved':'saved','sales.confirm':'confirm','sales.cancel':'cancel'}[a.action];li.append(el('strong',null,t(actionName||a.action)),el('span','so-muted',new Date(a.event_at).toLocaleString(lang==='bn'?'bn-BD':'en-GB')+' · #'+a.stream_seq),el('span','so-muted',t('actor')+': '+a.actor_id));list.append(li);}section.append(list);}root.append(section);
  }
  function rememberFocus(){const a=doc.activeElement;if(host.contains(a)){
   if(a.dataset.field)focusHint='[data-field="'+a.dataset.field+'"][data-line="'+a.dataset.line+'"]';
   else if(a.dataset.product)focusHint='[data-product="'+a.dataset.product+'"]';
   else if(a.dataset.action)focusHint='[data-action="'+a.dataset.action+'"]';
   else if(a.dataset.order)focusHint='[data-order="'+a.dataset.order+'"]';
   else if(a.dataset.soFocus)focusHint='[data-so-focus="'+a.dataset.soFocus+'"]';
  }else if(a&&a!==doc.body)focusHint=null;
  }
  function restoreFocus(){if(busy||!focusHint)return;const target=host.querySelector(focusHint);if(target&&!target.disabled){target.focus({preventScroll:true});return;}const heading=host.querySelector('.so-detail h3,h2');if(heading){heading.tabIndex=-1;heading.focus({preventScroll:true});}}
  function focusDetail(){const x=(host.querySelector('.so-detail select:enabled,.so-detail button:enabled')||host.querySelector('.so-detail h3'));if(x){if(x.tagName==='H3')x.tabIndex=-1;x.focus({preventScroll:false});}}
  function render(){if(disposed)return;rememberFocus();host.replaceChildren();host.classList.add('so-workspace');host.lang=lang;host.setAttribute('aria-busy',String(busy));drawHeader();drawScope();
   const status=el('p','so-status',notice?t(notice):'');status.setAttribute('role',tone==='error'?'alert':'status');status.setAttribute('aria-live','polite');status.dataset.tone=tone;host.append(status);
   if(pendingNav)host.append(button(t('discard'),()=>{const next=pendingNav;pendingNav=null;next();},busy||!!uncertain));
   if(uncertain){const retry=button(t('retry'),()=>{const held=uncertain;uncertain=null;action(held.fn,held.success,true);},busy,'primary');retry.dataset.retry='true';host.append(retry);}
   if(!context){restoreFocus();return;}if(!catalog)host.append(el('p','so-note',t('missingMaster')));if(!currentControl('sales.order_draft')?.enabled)host.append(el('p','so-note',t('disabled')));
   const layout=el('div','so-layout'),list=el('section','so-list'),detail=el('section','so-detail');list.setAttribute('aria-label',t('orders'));detail.setAttribute('aria-label',t('title'));drawList(list);drawForm(detail);layout.append(list,detail);host.append(layout);updateEstimate();restoreFocus();
  }
  const ready=boot();return Object.freeze({ready,refresh:()=>navigate(boot),reset(){clearPrivate();busy=false;render();},destroy(){clearPrivate();busy=false;disposed=true;host.replaceChildren();},getState(){return {businessId:business,siteId:site,mode,lang,busy};}});
 }
 return Object.freeze({mount});
});
