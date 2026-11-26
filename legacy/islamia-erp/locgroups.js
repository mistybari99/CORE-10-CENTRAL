(function () {
  'use strict';
  var B = window.BOS = window.BOS || {};
  var GROUPS = [
    { key: 'showrooms', bn: 'শোরুম / ব্রাঞ্চ', en: 'Showrooms / Branches', icon: '▣' },
    { key: 'factories', bn: 'কারখানা', en: 'Factories', icon: '⚙' },
    { key: 'stores', bn: 'গোডাউন / স্টোরহাউস', en: 'Godowns / Storehouses', icon: '▤' },
    { key: 'other', bn: 'অন্যান্য লোকেশন', en: 'Other Locations', icon: '•' }
  ];
  var MAIN_GROUPS = GROUPS.slice(0, 3);
  function escapeHTML(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function (char) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char];
    });
  }
  function classify(place) {
    var kind = String(place && (place.kind || place.place_kind || '') || '').toLowerCase().trim();
    if (['showroom', 'branch', 'retail', 'retail_shop'].indexOf(kind) !== -1) return 'showrooms';
    if (['factory', 'production', 'production_house'].indexOf(kind) !== -1) return 'factories';
    if (['godown', 'warehouse', 'store', 'storehouse', 'storage'].indexOf(kind) !== -1) return 'stores';
    return 'other';
  }
  function grouped(items) {
    var bucket = { showrooms: [], factories: [], stores: [], other: [] };
    (items || []).forEach(function (place) { bucket[classify(place)].push(place); });
    return GROUPS.map(function (group) {
      return { key: group.key, bn: group.bn, en: group.en, icon: group.icon, items: bucket[group.key] };
    }).filter(function (group) { return group.items.length > 0; });
  }
  function title(group) {
    return B.L && B.lab ? B.lab(B.L(group.bn, group.en)) : group.en;
  }
  function optionsHTML(items, selected, labelOf, placeholder) {
    var getLabel = typeof labelOf === 'function' ? labelOf : function (place) {
      return place.name_en || place.name_bn || place.code || String(place.id);
    };
    var empty = placeholder === undefined ? '' : '<option value="">' + escapeHTML(placeholder) + '</option>';
    return empty + grouped(items).map(function (group) {
      return '<optgroup label="' + escapeHTML(title(group)) + '">' +
        group.items.map(function (place) {
          return '<option value="' + escapeHTML(place.id) + '"' +
            (String(place.id) === String(selected) ? ' selected' : '') + '>' +
            escapeHTML(getLabel(place)) + '</option>';
        }).join('') + '</optgroup>';
    }).join('');
  }
  function isFilteredLocationList() {
    try {
      if (!/^#\/?locations(?:\/|$)/.test(window.location.hash)) return false;
      var search = document.getElementById('lo_q');
      var activeStatus = document.querySelector('#lo_chips .on');
      return !!(search && search.value.trim()) || !!(activeStatus && activeStatus.dataset.v !== 'all');
    } catch (_) { return false; }
  }
  function listHTML(items, renderItem, options) {
    if (!Array.isArray(items) || !items.length) return '';
    options = options || {};
    var visible = grouped(items);
    var buckets = {};
    visible.forEach(function (group) { buckets[group.key] = group; });
    var isFiltered = !!options.expandAll || isFilteredLocationList();
    var sections = isFiltered ? visible : MAIN_GROUPS.map(function (group) {
      return buckets[group.key] || { key: group.key, bn: group.bn, en: group.en, icon: group.icon, items: [] };
    }).concat(buckets.other ? [buckets.other] : []);
    return sections.map(function (group) {
      var emptyText = B.L && B.lab ? B.lab(B.L('এই গ্রুপে এখনো কোনো লোকেশন নেই', 'No locations in this group yet')) : 'No locations in this group yet';
      return '<details class="lg-group" data-group="' + escapeHTML(group.key) + '"' +
        (isFiltered ? ' open' : '') + '>' +
        '<summary class="lg-summary"><span class="lg-summary-name">' +
        '<span class="lg-symbol" aria-hidden="true">' + escapeHTML(group.icon) + '</span>' +
        '<span>' + escapeHTML(title(group)) + '</span></span>' +
        '<span class="lg-summary-end"><span class="lg-count">' + group.items.length +
        '</span><span class="lg-chevron" aria-hidden="true">⌄</span></span></summary>' +
        '<div class="lg-items">' + (group.items.length ? group.items.map(renderItem).join('') :
          '<p class="lg-empty">' + escapeHTML(emptyText) + '</p>') + '</div></details>';
    }).join('');
  }
  B.locGroups = { GROUPS: GROUPS, classify: classify, grouped: grouped,
    title: title, optionsHTML: optionsHTML, listHTML: listHTML };
  try {
    var style = document.getElementById('lg-css');
    if (!style) {
      style = document.createElement('style');
      style.id = 'lg-css';
      document.head.appendChild(style);
    }
    style.textContent = [
      '.lg-group{margin:10px 0;border:1px solid var(--line,#ddd);border-radius:14px;background:var(--card,#fff);overflow:hidden}',
      '.lg-summary{cursor:pointer;list-style:none;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:13px 14px;min-height:54px;font-weight:700;color:var(--text,inherit)}',
      '.lg-summary::-webkit-details-marker{display:none}',
      '.lg-summary:focus-visible{outline:2px solid var(--ruby,#a1111e);outline-offset:-3px}',
      '.lg-summary-name,.lg-summary-end{display:inline-flex;align-items:center;gap:10px;min-width:0}',
      '.lg-summary-name{font-size:.98rem}',
      '.lg-symbol{display:inline-flex;align-items:center;justify-content:center;width:30px;height:30px;flex:none;border-radius:9px;color:var(--ruby,#a1111e);background:color-mix(in srgb,var(--ruby,#a1111e) 9%,transparent)}',
      '.lg-count{min-width:27px;padding:1px 7px;border-radius:20px;text-align:center;font-size:.78rem;background:var(--bg,#f8f8f8);color:var(--muted,#666)}',
      '.lg-chevron{display:inline-block;transition:transform .16s ease;font-size:1.25rem;color:var(--muted,#666)}',
      '.lg-group[open] .lg-chevron{transform:rotate(180deg)}',
      '.lg-items{padding:7px 10px 10px;border-top:1px solid var(--line,#ddd)}',
      '.lg-items>.card{margin:7px 0}',
      '.lg-empty{padding:10px 5px;margin:0;color:var(--muted,#666);font-size:.9rem}',
      '@media(min-width:768px){.lg-summary{padding:14px 18px}.lg-items{padding:8px 16px 14px}}'
    ].join('');
  } catch (_) { /* grouping remains functional when the stylesheet cannot be injected */ }
})();
