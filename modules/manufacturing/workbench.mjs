import {manufacturingClient} from './client.mjs';
const esc = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const key = () => 'mfg_ui_' + crypto.randomUUID().replaceAll('-','');
export function mountManufacturing(root, {rpc, context, lang = 'bn', synthetic = false}) {
  const api = manufacturingClient(rpc, context);
  let active = true, data = {recipes:[],batches:[]}, tab = 'recipes', generation = 0, busy = false;
  const t = (bn,en) => lang === 'en' ? en : bn;
  const $ = q => root.querySelector(q);
  const status = (msg,error=false) => {if (!active) return; $('[role=status]').textContent=msg; $('[role=status]').dataset.error=String(error);};
  function render() {
    root.innerHTML = `<div class="mfg-top"><div><small>CORE10 / NP05A · ${synthetic ? t('কৃত্রিম QA • আসল SQL, পরীক্ষার Master adapter','Synthetic QA • real SQL, test Master adapter') : t('উন্নয়ন পৃষ্ঠ • shell সংযোগ বাকি','Development surface • shell integration pending')}</small><h1>${t('মিষ্টি ও বেকারি উৎপাদন','Sweets & bakery manufacturing')}</h1><p>${esc(context.label || '')} · ${t('সাইট','Site')} ${esc(context.site_id)}</p></div><button data-lang>${lang==='bn'?'English':'বাংলা'}</button></div>
    <div class="safety">${t('প্রকৃত স্টক বা অর্থ পোস্ট হয় না। Master UOM ও অনুমোদন সংযোগ ছাড়া ছাড়পত্র বন্ধ। ব্যয়ের অঙ্ক শুধু উদাহরণ ও পরিকল্পনা।','No real Stock or Money posting. Master UOM and approval completion gate releases. Costs are planning examples only.')}</div>
    <div class="mfg-pills"><span>Master UOM · NOT_CONNECTED</span><span>Stock · NOT_CONNECTED</span><span>Finance · NOT_CONNECTED</span><span>Approval completion · NOT_CONNECTED</span></div>
    <nav class="mfg-nav" aria-label="${t('উৎপাদন বিভাগ','Manufacturing sections')}">${[['recipes','রেসিপি','Recipes'],['batches','উৎপাদন ব্যাচ','Batches'],['reports','ফলন ও অপচয়','Yield & waste']].map(([id,bn,en])=>`<button data-tab="${id}" aria-pressed="${tab===id}">${t(bn,en)}</button>`).join('')}<button data-refresh>${t('হালনাগাদ','Refresh')}</button></nav>
    <p class="op-status" role="status" aria-live="polite"></p><section id="mfg-content"></section>`;
    $('[data-lang]').onclick=()=>{lang=lang==='bn'?'en':'bn';render();};
    root.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;render();});
    $('[data-refresh]').onclick=load;
    const content = $('#mfg-content');
    if (tab==='recipes') {
      content.innerHTML=`<div class="op-grid"><section class="op-panel"><h2>${t('রেসিপি ও সংস্করণ','Recipes & versions')}</h2>${data.recipes.length ? data.recipes.map(r=>`<article class="op-record"><strong>${esc(r.recipe_code)} · v${r.version}</strong><small>${esc(r.status)} · ${r.yield_quantity} ${esc(r.yield_uom_ref)} · ID ${r.id}</small><details><summary>${t('উপাদান ও প্যাকেজিং','Ingredients & packaging')}</summary><pre>${esc(JSON.stringify(r.ingredients_payload,null,2))}</pre></details><button data-approve="${r.id}" ${r.status!=='draft'?'hidden':''}>${t('অনুমোদন অনুরোধ','Request approval')}</button><button data-plan="${r.id}" ${r.status!=='approved'?'hidden':''}>${t('ব্যাচ পরিকল্পনা','Plan batch')}</button></article>`).join('') : `<p>${t('রেসিপি নেই। নতুন সংস্করণ তৈরি করুন।','No recipes yet. Create a version.')}</p>`}</section>
      <section class="op-panel"><h2>${t('নতুন রেসিপি সংস্করণ','New recipe version')}</h2><form class="op-form" id="mfg-recipe-form">
      <label>${t('রেসিপি কোড','Recipe code')}<input name="code" required minlength="2" maxlength="80"></label>
      <label>${t('পণ্যের Master ID','Finished item Master ID')}<input name="item" required type="number" min="1" step="1"></label>
      <label>${t('প্রত্যাশিত ফলন','Expected yield')}<input name="yield" required type="number" min="0.000001" step="0.000001"></label>
      <label>${t('Master UOM reference (যাচাই বাকি)','Master UOM reference (pending validation)')}<input name="uom" required maxlength="80"></label>
      <label>${t('আনুমানিক অতিরিক্ত ব্যয়','Estimated overhead')}<input name="overhead" required type="number" min="0" step="0.01" value="0"></label>
      <label>${t('উপাদান তালিকা JSON • উন্নয়ন ইনপুট','Component JSON • development input')}<textarea name="lines" required placeholder='[{"item":123,"qty":1,"uom_ref":"...","kind":"ingredient","waste_pct":0,"estimated_unit_cost":0}]'></textarea></label>
      <button type="submit">${t('খসড়া সংস্করণ সংরক্ষণ','Save draft version')}</button></form></section></div>`;
      $('#mfg-recipe-form').onsubmit = e => {e.preventDefault();const f=new FormData(e.target);command('mfg_create_recipe_v1',()=>({p_finished_item:Number(f.get('item')),p_code:f.get('code'),p_yield:Number(f.get('yield')),p_uom:f.get('uom'),p_lines:JSON.parse(f.get('lines')),p_overhead:Number(f.get('overhead'))}));};
      root.querySelectorAll('[data-approve]').forEach(b=>b.onclick=()=>command('mfg_approve_recipe_v1',()=>({p_recipe:Number(b.dataset.approve),p_effective:new Date().toISOString()})));
      root.querySelectorAll('[data-plan]').forEach(b=>b.onclick=()=>planForm(Number(b.dataset.plan)));
    } else if (tab==='batches') {
      content.innerHTML=`<section class="op-panel"><h2>${t('ব্যাচের অগ্রগতি','Batch progress')}</h2>${data.batches.map(b=>`<article class="op-record"><strong>${t('ব্যাচ','Batch')} #${b.id} · ${esc(b.status)}</strong><small>${t('পরিকল্পিত','Planned')} ${b.expected_output} ${esc(b.yield_uom_ref)} · BOM ${b.bom_id}</small><button data-release="${b.id}" ${b.status!=='planned'?'hidden':''}>${t('ছাড়পত্র অনুরোধ','Request release')}</button><button data-cancel="${b.id}" ${b.status!=='planned'?'hidden':''}>${t('বাতিল','Cancel')}</button><button data-record="${b.id}" ${b.status!=='released'?'hidden':''}>${t('ফলন লিখুন','Record output')}</button><button data-handoff="${b.id}">${t('সংযোগ পরীক্ষা','Check handoff')}</button></article>`).join('') || t('কোনো ব্যাচ নেই।','No batches.')}</section>`;
      root.querySelectorAll('[data-release]').forEach(b=>b.onclick=()=>command('mfg_release_batch_v1',()=>({p_batch:Number(b.dataset.release)})));
      root.querySelectorAll('[data-cancel]').forEach(b=>b.onclick=()=>reasonForm(Number(b.dataset.cancel)));
      root.querySelectorAll('[data-record]').forEach(b=>b.onclick=()=>outputForm(Number(b.dataset.record)));
      root.querySelectorAll('[data-handoff]').forEach(b=>b.onclick=()=>command('mfg_request_handoff_v1',()=>({p_batch:Number(b.dataset.handoff),p_kind:data.batches.find(x=>x.id===Number(b.dataset.handoff)).status==='recorded'?'finance':'ingredients'})));
    } else {
      content.innerHTML=`<section class="op-panel"><h2>${t('ফলন, অপচয় ও ব্যয় পার্থক্য','Yield, waste & planning variance')}</h2><p>${t('উপাদানের কেজি ও পণ্যের পিস যোগ করা হয় না। হিসাব সংশ্লিষ্ট UOM অনুযায়ী।','Ingredient kg and output pieces are never added. Quantities retain their UOM.')}</p>${data.batches.filter(b=>b.status==='recorded').map(b=>`<article class="op-record"><strong>${t('ব্যাচ','Batch')} #${b.id} · ${esc(b.output_payload.lot_ref)}</strong><div class="mfg-kpis"><div><strong>${b.yield_pct}%</strong><small>${t('ভাল পণ্যের ফলন','Good output yield')}</small></div><div><strong>${b.output_payload.loss} ${esc(b.yield_uom_ref)}</strong><small>${t('প্রক্রিয়াগত অপচয়','Process loss')}</small></div><div><strong>${b.planning_cost_variance} BDT</strong><small>${t('উদাহরণ • পরিকল্পিত ব্যয় পার্থক্য','Example • planning cost variance')}</small></div></div><p>${t('প্রত্যাখ্যাত','Rejected')}: ${b.output_payload.rejected} · ${t('পুনঃকাজ','Rework')}: ${b.output_payload.rework} · ${esc(b.output_payload.reason)}</p><details><summary>${t('ব্যবহার ও লট সূত্র','Consumption & lot references')}</summary><pre>${esc(JSON.stringify(b.output_payload.consumption,null,2))}</pre></details><small>NOT_CONNECTED · Stock / Finance · actual_cogs_certified=false</small></article>`).join('') || t('ফলন নথি নেই।','No output records.')}</section>`;
    }
  }
  function inlineForm(title,html,submit) {$('#mfg-content').innerHTML=`<section class="op-panel"><h2>${title}</h2><form class="op-form">${html}<button type="submit">${t('জমা দিন','Submit')}</button></form></section>`;$('#mfg-content form').onsubmit=e=>{e.preventDefault();submit(new FormData(e.target));};}
  function planForm(id) {inlineForm(t('ব্যাচ পরিকল্পনা','Plan batch'),`<label>${t('Stock location ID','Stock location ID')}<input name="location" required type="number" min="1"></label><label>${t('গুণক','Multiplier')}<input name="multiplier" required type="number" min="0.000001" step="0.000001" value="1"></label>`,f=>command('mfg_plan_batch_v1',()=>({p_recipe:id,p_location:Number(f.get('location')),p_multiplier:Number(f.get('multiplier'))})));}
  function reasonForm(id) {inlineForm(t('বাতিলের কারণ','Cancellation reason'),'<label>কারণ / Reason<input name="reason" required minlength="5" maxlength="500"></label>',f=>command('mfg_cancel_batch_v1',()=>({p_batch:id,p_reason:f.get('reason')})));}
  function outputForm(id) {inlineForm(t('ফলন নথি • পরিকল্পিত মোটের সাথে মেলাতে হবে','Record output • categories must reconcile to planned total'),'<label>Output JSON<textarea name="output" required></textarea></label>',f=>command('mfg_record_output_v1',()=>({p_batch:id,p_output:JSON.parse(f.get('output'))})));}
  async function load() {const current=++generation;try {const r=await api.call('mfg_inspect_v1');if (!active||current!==generation)return;data=r;render();}catch(e){if(active&&current===generation)status(t('অনুমতি বা সংযোগ ত্রুটি: ','Permission or connection error: ')+e.message,true);}}
  async function command(name,args) {
    if(busy||!active)return;busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
    try {const r=await api.call(name,{...args(),p_key:key()});await load();if(active)status(r.status==='NOT_CONNECTED'?'NOT_CONNECTED · '+r.reason:t('সংরক্ষিত • Audit #','Saved • Audit #')+r.audit_event_id);}
    catch(e){status(t('অনুমতি বা যাচাই ত্রুটি: ','Permission or validation error: ')+e.message,true);}
    finally {busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
  }
  render();load();
  return ()=>{active=false;++generation;api.close();data={recipes:[],batches:[]};root.replaceChildren();};
}
