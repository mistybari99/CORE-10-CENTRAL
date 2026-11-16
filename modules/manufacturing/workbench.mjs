import {manufacturingClient} from './client.mjs';
const esc = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const key = () => 'mfg_ui_' + crypto.randomUUID().replaceAll('-','');
export function mountManufacturing(root, {rpc, context, lang = 'bn', synthetic = false}) {
  const api = manufacturingClient(rpc, context);
  let active = true, data = {recipes:[],batches:[]}, tab = 'recipes', generation = 0, busy = false;
  const t = (bn,en) => lang === 'en' ? en : bn;
  const errorText=e=>e.message==='MFG_CONTROL_CHANGED_RETRY'?t('Owner-এর সেটিং বদলেছে। হালনাগাদ করে আবার চেষ্টা করুন।','Owner settings changed. Refresh and retry.')+' [MFG_CONTROL_CHANGED_RETRY]':e.message;
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
      content.innerHTML=`<div class="op-grid"><section class="op-panel"><h2>${t('রেসিপি ও সংস্করণ','Recipes & versions')}</h2>${data.recipes.length ? data.recipes.map(r=>`<article class="op-record"><strong>${esc(r.recipe_code)} · v${r.version}</strong><small>${esc(r.status)} · ${r.yield_quantity} ${esc(r.yield_uom_ref)} · ID ${r.id}</small><details><summary>${t('উপাদান ও প্যাকেজিং','Ingredients & packaging')}</summary><pre>${esc(JSON.stringify(r.ingredients_payload,null,2))}</pre></details><button data-substitution="${r.id}">${t('বিকল্প উপকরণ','Substitutions')}</button><button data-materials="${r.id}">${t('উপকরণ চাহিদা','Material requirements')}</button><button data-approve="${r.id}" ${r.status!=='draft'?'hidden':''}>${t('অনুমোদন অনুরোধ','Request approval')}</button><button data-plan="${r.id}" ${r.status!=='approved'?'hidden':''}>${t('ব্যাচ পরিকল্পনা','Plan batch')}</button></article>`).join('') : `<p>${t('রেসিপি নেই। নতুন সংস্করণ তৈরি করুন।','No recipes yet. Create a version.')}</p>`}</section>
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
      root.querySelectorAll('[data-materials]').forEach(b=>b.onclick=()=>materialsForm(Number(b.dataset.materials)));
      root.querySelectorAll('[data-plan]').forEach(b=>b.onclick=()=>planForm(Number(b.dataset.plan)));
    } else if (tab==='batches') {
      content.innerHTML=`<section class="op-panel"><h2>${t('ব্যাচের অগ্রগতি','Batch progress')}</h2>${data.batches.map(b=>`<article class="op-record"><strong>${t('ব্যাচ','Batch')} #${b.id} · ${esc(b.status)}</strong><small>${t('পরিকল্পিত','Planned')} ${b.expected_output} ${esc(b.yield_uom_ref)} · BOM ${b.bom_id}</small><button data-release="${b.id}" ${b.status!=='planned'?'hidden':''}>${t('ছাড়পত্র অনুরোধ','Request release')}</button><button data-cancel="${b.id}" ${b.status!=='planned'?'hidden':''}>${t('বাতিল','Cancel')}</button><button data-record="${b.id}" ${b.status!=='released'?'hidden':''}>${t('ফলন লিখুন','Record output')}</button><button data-waste="${b.id}" ${b.status!=='recorded'?'hidden':''}>${t('উপকরণের অপচয়','Material waste')}</button><button data-handoff="${b.id}">${t('সংযোগ পরীক্ষা','Check handoff')}</button></article>`).join('') || t('কোনো ব্যাচ নেই।','No batches.')}</section>`;
      root.querySelectorAll('[data-release]').forEach(b=>b.onclick=()=>command('mfg_release_batch_v1',()=>({p_batch:Number(b.dataset.release)})));
      root.querySelectorAll('[data-cancel]').forEach(b=>b.onclick=()=>reasonForm(Number(b.dataset.cancel)));
      root.querySelectorAll('[data-record]').forEach(b=>b.onclick=()=>outputForm(Number(b.dataset.record)));
      root.querySelectorAll('[data-handoff]').forEach(b=>b.onclick=()=>command('mfg_request_handoff_v1',()=>({p_batch:Number(b.dataset.handoff),p_kind:data.batches.find(x=>x.id===Number(b.dataset.handoff)).status==='recorded'?'finance':'ingredients'})));
    } else {
      content.innerHTML=`<section class="op-panel"><h2>${t('ফলন, অপচয় ও ব্যয় পার্থক্য','Yield, waste & planning variance')}</h2><p>${t('উপাদানের কেজি ও পণ্যের পিস যোগ করা হয় না। হিসাব সংশ্লিষ্ট UOM অনুযায়ী।','Ingredient kg and output pieces are never added. Quantities retain their UOM.')}</p>${data.batches.filter(b=>b.status==='recorded').map(b=>`<article class="op-record"><strong>${t('ব্যাচ','Batch')} #${b.id} · ${esc(b.output_payload.lot_ref)}</strong><div class="mfg-kpis"><div><strong>${b.yield_pct}%</strong><small>${t('ভাল পণ্যের ফলন','Good output yield')}</small></div><div><strong>${b.output_payload.loss} ${esc(b.yield_uom_ref)}</strong><small>${t('প্রক্রিয়াগত অপচয়','Process loss')}</small></div><div><strong>${b.planning_cost_variance} BDT</strong><small>${t('উদাহরণ • পরিকল্পিত ব্যয় পার্থক্য','Example • planning cost variance')}</small></div></div><p>${t('প্রত্যাখ্যাত','Rejected')}: ${b.output_payload.rejected} · ${t('পুনঃকাজ','Rework')}: ${b.output_payload.rework} · ${esc(b.output_payload.reason)}</p><details><summary>${t('ব্যবহার ও লট সূত্র','Consumption & lot references')}</summary><pre>${esc(JSON.stringify(b.output_payload.consumption,null,2))}</pre></details><small>NOT_CONNECTED · Stock / Finance · actual_cogs_certified=false</small><button data-waste="${b.id}">${t('উপকরণের অপচয়','Material waste')}</button></article>`).join('') || t('ফলন নথি নেই।','No output records.')}</section>`;
    }
    root.querySelectorAll('[data-substitution]').forEach(b=>b.onclick=()=>substitutionForm(Number(b.dataset.substitution)));
    root.querySelectorAll('[data-waste]').forEach(b=>b.onclick=()=>wasteForm(Number(b.dataset.waste)));
  }
  function inlineForm(title,html,submit) {$('#mfg-content').innerHTML=`<section class="op-panel"><h2>${title}</h2><form class="op-form">${html}<button type="submit">${t('জমা দিন','Submit')}</button></form></section>`;$('#mfg-content form').onsubmit=e=>{e.preventDefault();submit(new FormData(e.target));};}
  function materialsForm(id) {
    inlineForm(t('উপকরণ ও প্যাকেজিং চাহিদা','Material & packaging requirements'),`<label>${t('ব্যাচের গুণক','Batch multiplier')}<input name="multiplier" type="number" min="0.000001" step="0.000001" value="1" required></label>`, async f=>{
      if(busy||!active)return;busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
      try {
        const r=await api.call('mfg_material_requirements_v1',{p_recipe:id,p_multiplier:Number(f.get('multiplier'))});
        if(!active)return;
        $('#mfg-content').innerHTML=`<section class="op-panel" id="mfg-material-report"><h2>${t('উপকরণ ও প্যাকেজিং চাহিদা','Material & packaging requirements')}</h2><p>${esc(r.recipe_code)} · v${r.recipe_version} · ${esc(r.recipe_status)}</p><p>${t('প্রত্যাশিত উৎপাদন','Expected output')}: ${esc(r.output.quantity)} ${esc(r.output.uom_ref)}</p>
        <p class="safety">${t('শুধু পরিকল্পনা। Stock/UOM সংযোগ বাকি; মজুত ও ঘাটতি অজানা। এখানে কোনো স্টক কাটা হয় না।','Planning only. Stock/UOM disconnected; available stock and shortage are unknown. No stock is issued here.')}</p>
        ${r.lines.map(l=>`<article class="op-record"><strong>${esc(l.sku)} · ${l.kind==='packaging'?t('প্যাকেজিং','Packaging'):t('উপকরণ','Ingredient')}</strong><p>${t('চাহিদা','Required')}: ${esc(l.quantity)} ${esc(l.uom_ref)}</p><small>${t('প্রত্যাশিত অপচয়','Expected waste')}: ${esc(l.expected_waste_quantity)} ${esc(l.uom_ref)} (${esc(l.expected_waste_pct)}%)</small><small>${t('মজুত ও ঘাটতি','Available & shortage')}: ${t('অজানা','Unknown')} · ${esc(l.availability_status)}</small><small>${t('পরিকল্পিত ব্যয়','Planning cost')}: ${esc(l.estimated_line_cost)} BDT</small></article>`).join('')}
        <p>${t('আনুমানিক মোট ব্যয়','Estimated total cost')}: ${esc(r.estimated_total_cost)} BDT · UNVERIFIED_PLANNING_ESTIMATE</p></section>`;
        status(t('চাহিদার হিসাব প্রস্তুত • কোনো লেনদেন হয়নি','Requirements ready • no transaction posted'));
      }catch(e){status(t('অনুমতি বা যাচাই ত্রুটি: ','Permission or validation error: ')+errorText(e),true);}
      finally{busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
    });
  }
  async function substitutionForm(id) {
    if(busy||!active)return;busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
    try {const r=await api.call('mfg_recipe_substitutions_v1',{p_recipe:id});if(active)renderSubstitutions(r);}
    catch(e){status(t('বিকল্পের নিয়ম দেখা যাচ্ছে না: ','Cannot inspect substitutions: ')+errorText(e),true);}
    finally{busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
  }
  function renderSubstitutions(r) {
    const draftKey=key();
    $('#mfg-content').innerHTML=`<section class="op-panel" id="mfg-substitutions"><h2>${t('বিকল্প উপকরণের প্রস্তাব','Substitution proposals')}</h2><p>${esc(r.recipe_code)} · v${r.recipe_version} · ${esc(r.recipe_status)}</p>
    <p class="safety">${t('শুধু রেসিপির পরিকল্পনা। Master যাচাই বাকি; কোনো ব্যাচে বিকল্প বাছাই বা stock issue হয়নি। নিয়ম বদলাতে নতুন রেসিপি সংস্করণ করুন।','Recipe planning only. Master validation pending; no batch substitution selected or stock issued. Changes require a new recipe version.')}</p>
    ${r.recipe_status==='draft'?`<form class="op-form" id="mfg-substitution-form">
    <label>${t('মূল উপকরণ / প্যাকেজিং','Original component')}<select name="sub_line">${r.lines.map(l=>`<option value="${l.line_no}">${esc(l.sku)} · ${l.quantity} ${esc(l.uom_ref)}</option>`).join('')}</select></label>
    <label>${t('বিকল্প পণ্যের Master ID','Alternative item Master ID')}<input name="sub_item" type="number" min="1" step="1" required></label>
    <label>${t('মূল লাইন পুরো বদলালে বিকল্পের প্রস্তাবিত পরিমাণ','Declared alternative quantity for full line replacement')}<input name="sub_quantity" type="number" min="0.000001" step="0.000001" required></label>
    <label>${t('বিকল্পের UOM reference (যাচাই বাকি)','Alternative UOM reference (pending validation)')}<input name="sub_uom" maxlength="80" required></label>
    <label>${t('বিকল্পের আনুমানিক একক খরচ','Alternative estimated unit cost')}<input name="sub_cost" type="number" min="0" step="0.0001" required></label>
    <label>${t('বিকল্পের প্রত্যাশিত অপচয় %','Alternative expected waste %')}<input name="sub_waste_pct" type="number" min="0" max="100" step="0.0001" value="0" required></label>
    <label>${t('সর্বোচ্চ কত শতাংশ বদলানো যাবে','Maximum line replacement %')}<input name="sub_max_pct" type="number" min="0.0001" max="${r.policy.params.max_replacement_pct}" step="0.0001" value="${Math.min(50,r.policy.params.max_replacement_pct)}" required></label>
    <label>${t('বিকল্পের কারণ ও ব্যাখ্যা','Reason and explanation')}<input name="sub_note" minlength="5" maxlength="500" required></label>
    <button type="submit">${t('খসড়া নিয়ম সংরক্ষণ','Save draft rule')}</button></form>`:''}
    <h3>${t('সংস্করণের নিয়ম ও Audit','Version rules & Audit')}</h3><div id="mfg-substitution-rules">${r.rules.map(rule=>`<article class="op-record" data-sub-rule="${rule.id}"><strong>#${rule.id} · ${t('লাইন','Line')} ${rule.line_no} → Master #${rule.alternative_item_id}</strong><p>${rule.alternative_qty_per_batch} ${esc(rule.uom_ref)} · ${t('সর্বোচ্চ','Maximum')} ${rule.max_replacement_pct}%</p><p>${esc(rule.note)}</p><small>Audit #${rule.audit_event_id} · NOT_CONNECTED</small><button data-sub-preview="${rule.id}">${t('পরিমাণ ও খরচের preview','Preview quantities & cost')}</button></article>`).join('')||t('এখনো বিকল্পের নিয়ম নেই।','No alternatives defined yet.')}</div></section>`;
    const form=$('#mfg-substitution-form');
    if(form)form.onsubmit=e=>{e.preventDefault();const f=new FormData(e.target);command('mfg_define_substitution_v1',()=>({p_recipe:r.recipe_id,p_line:Number(f.get('sub_line')),p_alternative_item:Number(f.get('sub_item')),p_quantity:Number(f.get('sub_quantity')),p_uom:f.get('sub_uom'),p_estimated_cost:Number(f.get('sub_cost')),p_waste_pct:Number(f.get('sub_waste_pct')),p_max_pct:Number(f.get('sub_max_pct')),p_note:f.get('sub_note')}),async saved=>{const fresh=await api.call('mfg_recipe_substitutions_v1',{p_recipe:saved.recipe_id});if(active)renderSubstitutions(fresh);},draftKey);};
    root.querySelectorAll('[data-sub-preview]').forEach(button=>button.onclick=()=>{
      const rule=r.rules.find(x=>x.id===Number(button.dataset.subPreview));
      inlineForm(t('বিকল্পের পরিকল্পনা preview','Substitution planning preview'),`<label>${t('ব্যাচের গুণক','Batch multiplier')}<input name="sub_multiplier" type="number" min="0.000001" step="0.000001" value="1" required></label><label>${t('কত শতাংশ বদলানোর হিসাব','Replacement percentage')}<input name="sub_percent" type="number" min="0.0001" max="${Math.min(rule.max_replacement_pct,r.policy.params.max_replacement_pct)}" step="0.0001" value="${Math.min(rule.max_replacement_pct,r.policy.params.max_replacement_pct)}" required></label>`,async f=>{
        if(busy||!active)return;busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
        try{const p=await api.call('mfg_preview_substitution_v1',{p_rule:rule.id,p_multiplier:Number(f.get('sub_multiplier')),p_replacement_pct:Number(f.get('sub_percent'))});if(!active)return;
          $('#mfg-content').innerHTML=`<section class="op-panel" id="mfg-substitution-preview"><h2>${t('বিকল্পের পরিকল্পনা preview','Substitution planning preview')}</h2><p class="safety">${t('প্রস্তাবিত পরিমাণের হিসাব; UOM conversion নয়। Master যাচাই ও ব্যাচে বাছাই হয়নি।','Declared replacement quantities; not a UOM conversion. Master validation and batch selection pending.')}</p><article class="op-record"><strong>${t('মূল উপকরণ বাকি','Original component remaining')}</strong><p>${p.original_component.remaining_quantity} ${esc(p.original_component.uom_ref)}</p></article><article class="op-record"><strong>${t('বিকল্পের চাহিদা','Alternative required')}</strong><p>${p.alternative_component.quantity} ${esc(p.alternative_component.uom_ref)}</p></article><p>${t('আগের আনুমানিক খরচ','Baseline estimate')}: ${p.baseline_estimated_cost} BDT</p><p>${t('বিকল্পসহ আনুমানিক খরচ','Estimate with substitution')}: ${p.estimated_total_cost} BDT</p><p>${t('পরিকল্পিত পার্থক্য','Planning variance')}: ${p.planning_cost_variance} BDT</p><small>UNVERIFIED_PLANNING_ESTIMATE · NOT_CONNECTED · batch_selected=false · stock_issued=false</small></section>`;
          status(t('হিসাব প্রস্তুত • কোনো ব্যাচ বা stock বদলায়নি','Preview ready • no batch or stock changed'));
        }catch(error){status(t('যাচাই ত্রুটি: ','Validation error: ')+errorText(error),true);}
        finally{busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
      });
    });
  }
  async function wasteForm(id) {
    if(busy||!active)return;
    busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
    try {const r=await api.call('mfg_material_waste_report_v1',{p_batch:id});if(active)renderWaste(r);}
    catch(e){status(t('অপচয়ের নথি দেখা যাচ্ছে না: ','Cannot inspect waste: ')+errorText(e),true);}
    finally{busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
  }
  function renderWaste(r) {
    let attempt=null;
    $('#mfg-content').innerHTML=`<section class="op-panel" id="mfg-waste-report"><h2>${t('উপকরণভিত্তিক অপচয়','Material waste observations')} · #${r.batch_id}</h2>
    <p class="safety">${t('এই অপচয় মোট ব্যবহারের ভেতরে রয়েছে। আবার stock কাটা বা খরচ যোগ হয় না। অবশিষ্ট ব্যবহারকে ভাল পণ্য ধরা হচ্ছে না।','Waste is part of recorded consumption. No additional stock issue or cost. Remaining consumption is not certified good use.')}</p>
    ${r.lines.map(l=>`<article class="op-record"><strong>${esc(l.sku)}</strong><p>${t('মোট ব্যবহার','Consumed')}: ${esc(l.consumed_quantity)} ${esc(l.uom_ref)} · ${t('নথিভুক্ত অপচয়','Recorded waste')}: ${esc(l.recorded_waste)} ${esc(l.uom_ref)}</p><small>${t('বাকি ব্যবহার অনির্ধারিত','Unclassified consumption')}: ${esc(l.unclassified_consumption)} ${esc(l.uom_ref)}</small><small>${t('লটের সূত্র','Lot reference')}: ${esc(l.lot_ref)} · ${t('যাচাই বাকি','Validation pending')}</small></article>`).join('')}
    <h3>${t('কারণসহ অপচয় লিখুন','Record waste with a reason')}</h3><form class="op-form" id="mfg-waste-form">
    <label>${t('উপকরণ / প্যাকেজিং','Material / packaging')}<select name="waste_line">${r.lines.map(l=>`<option value="${l.line_no}">${esc(l.sku)} · ${esc(l.uom_ref)}</option>`).join('')}</select></label>
    <label>${t('অপচয়ের পরিমাণ (নির্বাচিত উপকরণের এককে)','Waste quantity (selected material UOM)')}<input name="waste_quantity" type="number" min="0.000001" step="0.000001" required></label>
    <label>${t('কারণ','Reason')}<select name="waste_reason" required>${r.allowed_reason_codes.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join('')}</select></label>
    <label>${t('কী ঘটেছে','What happened')}<input name="waste_note" required minlength="5" maxlength="500"></label>
    <p>${t('Owner-এর সর্বোচ্চ অপচয়ের সীমা','Owner maximum waste threshold')}: ${r.max_waste_pct}% · ${t('অনুমোদনের ধাপ','Approval stages')}: ${r.approval_stages}</p>
    <button type="submit">${t('অপচয় সংরক্ষণ','Save waste observation')}</button></form>
    <p>${t('লট/UOM যাচাই','Lot/UOM validation')}: NOT_CONNECTED</p><h3>${t('আগের নথি','Observation history')}</h3>
    <div id="mfg-waste-events">${r.events.map(e=>`<article class="op-record" data-waste-event="${e.event_id}"><strong>#${e.event_id} · ${esc(e.reason_code)} · ${esc(e.quantity)} ${esc(e.uom_ref)}</strong><p>${esc(e.note)}</p><small>${esc(e.lot_ref)} · Audit #${e.audit_event_id}</small></article>`).join('')||t('এখনো কোনো অপচয় লেখা হয়নি।','No waste recorded yet.')}</div></section>`;
    $('#mfg-waste-form').onsubmit=async e=>{
      e.preventDefault();if(busy||!active)return;
      const f=new FormData(e.target),line=r.lines.find(l=>l.line_no===Number(f.get('waste_line')));
      const args={p_batch:r.batch_id,p_line:line.line_no,p_quantity:Number(f.get('waste_quantity')),p_reason:f.get('waste_reason'),p_lot_ref:line.lot_ref,p_note:f.get('waste_note')};
      const signature=JSON.stringify(args);
      if(attempt?.uncertain&&attempt.signature!==signature){status(t('আগের অনুরোধের ফল অজানা। হালনাগাদ করে নথি দেখে নিন।','Previous result is uncertain. Refresh and inspect the history first.'),true);return;}
      if(!attempt||attempt.signature!==signature)attempt={signature,key:key(),uncertain:false};
      busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
      try {
        const saved=await api.call('mfg_record_material_waste_v1',{...args,p_key:attempt.key});
        attempt=null;if(!active)return;
        let refreshMessage='';
        try{const fresh=await api.call('mfg_material_waste_report_v1',{p_batch:r.batch_id});if(active)renderWaste(fresh);}
        catch(refreshError){refreshMessage=t(' • রিপোর্ট হালনাগাদ হয়নি: ',' • Report refresh unavailable: ')+errorText(refreshError);}
        if(active)status(t('অপচয় সংরক্ষিত • Audit #','Waste saved • Audit #')+saved.audit_event_id+refreshMessage,Boolean(refreshMessage));
      }catch(error){
        if(attempt)attempt.uncertain=!/^(MFG_|CONTROL_|NOT_CONNECTED:|permission denied)/.test(error.message);
        status(attempt?.uncertain?t('সংযোগে সমস্যা; ফল অজানা। একই তথ্য দিয়ে আবার জমা দিলে একই request ব্যবহার হবে।','Connection failed; result uncertain. Retrying unchanged data reuses the same request.'):t('অনুমতি বা যাচাই ত্রুটি: ','Permission or validation error: ')+errorText(error),true);
      }finally{busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
    };
  }
  function showHandoff(r) {
    const e=r.source_envelope;
    $('#mfg-content').insertAdjacentHTML('beforeend',`<section class="op-panel" id="mfg-handoff"><h2>${t('সংযোগের জন্য প্রস্তুত সূত্র','Prepared handoff source')}</h2><p>NOT_CONNECTED · ${t('কোনো স্টক বা অর্থ পোস্ট হয়নি','No Stock or Money posted')}</p><p>${t('ব্যাচ','Batch')} #${esc(e.source.batch_id)} · ${t('রেসিপি সংস্করণ','Recipe version')} ${esc(e.source.recipe_version)}</p><details><summary>${t('পরিমাণ, লট ও Audit সূত্র দেখুন','Inspect quantities, lots & Audit source')}</summary><pre>${esc(JSON.stringify(e,null,2))}</pre></details><small>${t('সূত্রের পরিচায়ক','Source fingerprint')}: ${esc(e.source_fingerprint)}</small></section>`);
  }
  function planForm(id) {inlineForm(t('ব্যাচ পরিকল্পনা','Plan batch'),`<label>${t('Stock location ID','Stock location ID')}<input name="location" required type="number" min="1"></label><label>${t('গুণক','Multiplier')}<input name="multiplier" required type="number" min="0.000001" step="0.000001" value="1"></label>`,f=>command('mfg_plan_batch_v1',()=>({p_recipe:id,p_location:Number(f.get('location')),p_multiplier:Number(f.get('multiplier'))})));}
  function reasonForm(id) {inlineForm(t('বাতিলের কারণ','Cancellation reason'),'<label>কারণ / Reason<input name="reason" required minlength="5" maxlength="500"></label>',f=>command('mfg_cancel_batch_v1',()=>({p_batch:id,p_reason:f.get('reason')})));}
  function outputForm(id) {inlineForm(t('ফলন নথি • পরিকল্পিত মোটের সাথে মেলাতে হবে','Record output • categories must reconcile to planned total'),'<label>Output JSON<textarea name="output" required></textarea></label>',f=>command('mfg_record_output_v1',()=>({p_batch:id,p_output:JSON.parse(f.get('output'))})));}
  async function load() {const current=++generation;try {const r=await api.call('mfg_inspect_v1');if (!active||current!==generation)return;data=r;render();}catch(e){if(active&&current===generation)status(t('অনুমতি বা সংযোগ ত্রুটি: ','Permission or connection error: ')+errorText(e),true);}}
  async function command(name,args,onSaved,requestKey) {
    if(busy||!active)return;busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
    try {const r=await api.call(name,{...args(),p_key:requestKey||key()});await load();let warning='';if(active&&onSaved){try{await onSaved(r);}catch(error){warning=t(' • ইতিহাস হালনাগাদ হয়নি: ',' • History refresh unavailable: ')+errorText(error);}}if(active&&r.source_envelope)showHandoff(r);if(active)status((r.status==='NOT_CONNECTED'?'NOT_CONNECTED · '+r.reason:t('সংরক্ষিত • Audit #','Saved • Audit #')+r.audit_event_id)+warning,Boolean(warning));}
    catch(e){status(t('অনুমতি বা যাচাই ত্রুটি: ','Permission or validation error: ')+errorText(e),true);}
    finally {busy=false;if(active)root.querySelectorAll('button').forEach(b=>b.disabled=false);}
  }
  render();load();
  return ()=>{active=false;++generation;api.close();data={recipes:[],batches:[]};root.replaceChildren();};
}
