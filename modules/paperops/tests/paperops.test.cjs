'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const paperops = require('../paperops.js');
const extraPacks = require('../form-packs.js');
const inventory = require('../legacy-inventory.json');
const extracted = require('../legacy-field-index.json');
const obligations = require('../control-obligations.json');
const ruleCandidates = require('../legacy-rule-candidates.json');
const repoRoot = path.resolve(__dirname, '../../..');

const baseJob = {
  industry: 'sweets', scope: 'business', groupName: 'Group',
  businessName: 'Sweets', siteName: '', lang: 'bn', tableRows: 8
};

test('the printable registry is consistent and deliberately small', () => {
  assert.equal(paperops.validateCatalog(), true);
  assert.equal(paperops.TEMPLATES.length, 30);
  assert.equal(extraPacks.length, 21);
  assert.equal(new Set(paperops.TEMPLATES.map(f => f.id)).size, 30);
  assert.ok(paperops.TEMPLATES.every(f => f.status !== 'live'));
  assert.equal(paperops.availableForms('generic').some(f => f.id === 'PAINT-TINT'), false);
  assert.equal(paperops.availableForms('paint').some(f => f.id === 'PAINT-TINT'), true);
  assert.equal(paperops.availableForms('sweets').some(f => f.id === 'MFG-DAILY'), true);
});

test('32 distinct legacy forms are inventoried from 5 byte-preserved sources', () => {
  assert.equal(inventory.forms.length, 32);
  assert.equal(inventory.sources.length, 5);
  assert.equal(new Set(inventory.forms.map(f => f.legacy_code)).size, 32);
  assert.equal(inventory.sources.reduce((sum, s) => sum + s.form_count, 0), 32);
  for (const src of inventory.sources) {
    const atRoot = path.join(repoRoot, src.original_path);
    const inLegacy = path.join(repoRoot, src.quarantine_path);
    const target = fs.existsSync(atRoot) ? atRoot : inLegacy;
    assert.ok(fs.existsSync(target), 'frozen legacy source missing: ' + src.original_path);
    const buf = fs.readFileSync(target);
    const gitBlobSha = crypto.createHash('sha1').update('blob ' + buf.length + '\0').update(buf).digest('hex');
    assert.equal(gitBlobSha, src.git_blob_sha, 'frozen legacy source changed: ' + src.original_path);
    assert.equal(inventory.forms.filter(f => f.original_source === src.original_path).length, src.form_count);
  }
});

test('business-common and site-specific branding are separate', () => {
  const job = {
    ...baseJob, scope: 'site', siteName: 'Khulna Branch',
    groupBrand: { color: '#112233', headerName: 'Group header' },
    businessBrand: { color: '#445566', headerName: 'Business header' },
    siteBrand: { color: '#abcdef', headerName: 'Branch header', formTitles: {'OPS-DAILY': 'Branch closing'} }
  };
  const site = paperops.renderPrintMarkup('OPS-DAILY', job);
  assert.match(site, /Branch closing/);
  assert.match(site, /Branch header/);
  assert.match(site, /Khulna Branch/);
  assert.match(site, /--accent:#abcdef/);
  const common = paperops.renderPrintMarkup('OPS-DAILY', { ...job, scope: 'business' });
  assert.doesNotMatch(common, /Branch closing/);
  assert.doesNotMatch(common, /Branch header/);
  assert.match(common, /Business header/);
  assert.match(common, /--accent:#445566/);
});

test('untrusted branding and free text are escaped; logo requires a safe data image', () => {
  const malicious = '<img src=x onerror=alert(1)>';
  const html = paperops.renderPrintMarkup('OPS-DAILY', {
    ...baseJob, businessName: malicious,
    businessBrand: { headerName: malicious, color: 'red;position:fixed', logo: 'javascript:alert(1)',
      formTitles: { 'OPS-DAILY': '<script>alert(1)</script>' } }
  });
  assert.doesNotMatch(html, /<script>/i);
  assert.doesNotMatch(html, /<img src=x/i);
  assert.doesNotMatch(html, /javascript:/i);
  assert.match(html, /&lt;script&gt;/);
  assert.match(html, /--accent:#174c4c/);
  assert.doesNotMatch(html, /paperops-logo/);
  const png = 'data:image/png;base64,iVBORw0KGgo=';
  assert.match(paperops.renderPrintMarkup('OPS-DAILY',
    { ...baseJob, businessBrand: { logo: png } }), /paperops-logo/);
});

test('invalid scope, missing context and cross-industry drafts cannot print', () => {
  assert.throws(() => paperops.renderPrintMarkup('OPS-DAILY', { ...baseJob, businessName: '' }), /BUSINESS_REQUIRED/);
  assert.throws(() => paperops.renderPrintMarkup('OPS-DAILY', { ...baseJob, scope: 'site' }), /SITE_REQUIRED/);
  assert.throws(() => paperops.renderPrintMarkup('PAINT-TINT', baseJob), /FORM_NOT_FOR_INDUSTRY/);
  assert.throws(() => paperops.renderPrintMarkup('NO-SUCH-FORM', baseJob), /UNKNOWN_FORM/);
  assert.throws(() => paperops.renderPrintMarkup('OPS-DAILY', { ...baseJob, industry: 'invalid' }), /UNKNOWN_INDUSTRY/);
});

test('industry-specific GRN controls show only for the relevant business', () => {
  const sweet = paperops.renderPrintMarkup('PUR-GRN', baseJob);
  const paint = paperops.renderPrintMarkup('PUR-GRN', { ...baseJob, industry: 'paint' });
  assert.match(sweet, /মেয়াদ/);
  assert.doesNotMatch(sweet, /শেড \/ বেস \/ লট পরীক্ষা/);
  assert.match(paint, /শেড \/ বেস \/ লট পরীক্ষা/);
  assert.doesNotMatch(paint, /মেয়াদ \/ সংরক্ষণ অবস্থা/);
});

test('large paper tables are capped and signatures are retained', () => {
  const html = paperops.renderPrintMarkup('STK-COUNT', { ...baseJob, tableRows: 5000 });
  assert.equal((html.match(/<tbody>/g) || []).length, 1);
  assert.equal((html.match(/<tbody>[\s\S]*?<\/tbody>/g) || [])[0].match(/<tr>/g).length, 18);
  assert.match(html, /সমন্বয় অনুমোদনকারী/);
  assert.match(html, /ERP পোস্টিংয়ের আগে/);
});

test('print studio has no network dependency and no ERP posting routine', () => {
  const html = fs.readFileSync(path.join(repoRoot,'modules/paperops/index.html'),'utf8');
  const js = fs.readFileSync(path.join(repoRoot,'modules/paperops/paperops.js'),'utf8');
  assert.match(html, /@media print/);
  assert.match(html, /input id="logo"/);
  assert.match(html, /scope/);
  assert.doesNotMatch(html + js, /fetch\(|XMLHttpRequest|\.rpc\(|service_role/);
});

test('all 32 legacy forms have a reproducible candidate field-key index', () => {
  assert.equal(extracted.forms.length, 32);
  assert.equal(extracted.total_extracted_fields, 1246);
  assert.deepEqual(new Set(extracted.forms.map(f=>f.legacy_code)),
    new Set(inventory.forms.map(f=>f.legacy_code)));
  for(const form of extracted.forms) {
    assert.ok(form.count_extracted > 0, 'no extracted fields: '+form.legacy_code);
    assert.equal(form.count_extracted, form.extracted_field_keys.length);
    assert.equal(new Set(form.extracted_field_keys).size, form.count_extracted);
    const fromInventory=inventory.forms.find(f=>f.legacy_code===form.legacy_code);
    assert.equal(fromInventory.original_source, form.source);
  }
  const daily=extracted.forms.find(f=>f.legacy_code==='R-01');
  assert.ok(daily.count_extracted>=150, 'critical daily form extraction weakened');
  assert.ok(daily.signals.conditional_display_syntax_mentions>=10);
  const factory=extracted.forms.find(f=>f.legacy_code==='F-05');
  assert.ok(factory.count_extracted>=55, 'factory daily controls extraction weakened');
});

test('critical control obligations are source-backed and cannot be claimed complete', () => {
  assert.equal(obligations.records.length, 20);
  assert.equal(new Set(obligations.records.map(o => o.id)).size, obligations.records.length);
  assert.ok(obligations.records.some(o => o.coverage === 'gap'), 'lost-control gaps must remain visible');
  assert.equal(obligations.records.filter(o=>o.coverage==='gap').length,11);
  assert.equal(obligations.records.filter(o=>o.coverage==='partial').length,9);
  assert.ok(obligations.records.every(o=>o.draft_target),'all historic obligations should have a draft target');
  assert.ok(obligations.records.every(o=>o.release_gate==='FIELD_PARITY_PLUS_OWNER_PRACTICAL_ACCEPTANCE'));

  for (const obligation of obligations.records) {
    const legacy = extracted.forms.find(f => f.legacy_code === obligation.legacy_form);
    assert.ok(legacy, 'unknown source form: ' + obligation.id);
    for (const key of obligation.legacy_field_keys) {
      assert.ok(legacy.extracted_field_keys.includes(key),
        'untraceable source field in ' + obligation.id + ': ' + key);
    }
    assert.ok(['gap','partial'].includes(obligation.coverage),
      'field parity or Owner acceptance has not yet been proved');
    if (obligation.draft_target) {
      assert.ok(paperops.TEMPLATES.some(f => f.id === obligation.draft_target));
    }
    if (obligation.coverage === 'partial') assert.ok(obligation.draft_target);
  }
});

test('early daily and factory paper forms visibly retain safety controls', () => {
  const daily = paperops.renderPrintMarkup('OPS-DAILY', baseJob);
  const factory = paperops.renderPrintMarkup('MFG-DAILY', baseJob);
  const grn = paperops.renderPrintMarkup('PUR-GRN', baseJob);
  assert.match(daily, /পরিচ্ছন্নতা/);
  assert.match(daily, /মেয়াদোত্তীর্ণ/);
  assert.match(factory, /যন্ত্র \/ পাল্লা \/ নিরাপত্তা/);
  assert.match(grn, /অর্ডারে/);
  assert.match(grn, /আটক\/ফেরত/);
});

test('source-derived rule candidates cover all old forms without being certified', () => {
  assert.equal(ruleCandidates.status,'REQUIRES_FIELD_BY_FIELD_OWNER_VALIDATION');
  assert.equal(ruleCandidates.totals.forms,32);
  assert.equal(ruleCandidates.totals.field_keys,1246);
  assert.ok(ruleCandidates.totals.always_required_candidate_fields>200);
  assert.ok(ruleCandidates.totals.conditionally_required_candidate_fields>100);
  assert.ok(ruleCandidates.totals.conditional_visibility_candidate_fields>170);
  assert.ok(ruleCandidates.totals.calculator_candidates>=30);
  assert.ok(ruleCandidates.totals.flag_candidates>100);
  for (const sourceForm of ruleCandidates.forms) {
    const indexed = extracted.forms.find(x=>x.legacy_code===sourceForm.legacy_code);
    assert.ok(indexed,'unindexed old form: '+sourceForm.legacy_code);
    assert.equal(indexed.source,sourceForm.source);
    assert.deepEqual(new Set(sourceForm.fields.map(x=>x.key)),
      new Set(indexed.extracted_field_keys),
      'lost original field key: '+sourceForm.legacy_code);
    for (const field of sourceForm.fields) {
      assert.ok(field.label_bn && field.label_en);
      assert.ok(['ALWAYS','CONDITIONAL','NOT_DECLARED'].includes(field.required_candidate));
      assert.ok(['CONDITIONAL','NOT_DECLARED'].includes(field.visible_candidate));
      assert.ok(['CHECKER','DEFAULT_OR_UNDECLARED'].includes(field.role_candidate));
    }
  }
});

test('all ten official business catalog IDs are recognized and industry packs stay scoped', () => {
  const catalog=require(path.join(repoRoot,'data/core10_capability_catalog_v1.json'));
  assert.equal(catalog.templates.length,10);
  for(const original of catalog.templates){
    assert.ok(paperops.INDUSTRIES.includes(original.id),'missing official industry '+original.id);
    assert.ok(paperops.availableForms(original.id).length>=8);
    assert.equal(paperops.industryClass(original.id)===null,false);
  }
  const specific=[
    ['sweets_bakery','SWT-JALEBI'],
    ['paint_hardware','PAINT-TINT'],
    ['restaurant','REST-KITCHEN'],
    ['retail_wholesale','RETAIL-REPLENISH'],
    ['general_manufacturing','MFG-QC'],
    ['construction','PROJECT-DAILY'],
    ['import_export','TRADE-CLEARANCE'],
    ['ecommerce','ECOM-FULFILL'],
    ['technology_digital','TECH-DELIVERY'],
    ['services','SERVICE-JOB']
  ];
  for(const [industry,id] of specific){
    assert.ok(paperops.availableForms(industry).some(x=>x.id===id),'industry missing '+id);
    assert.doesNotThrow(()=>paperops.renderPrintMarkup(id,{...baseJob,industry}));
  }
  assert.equal(paperops.availableForms('restaurant').some(x=>x.id==='SWT-JALEBI'),false);
  assert.equal(paperops.availableForms('ecommerce').some(x=>x.id==='PAINT-TINT'),false);
  assert.throws(()=>paperops.registerTemplates([paperops.TEMPLATES[0]]),/INVALID_FORM_ID/);
});
