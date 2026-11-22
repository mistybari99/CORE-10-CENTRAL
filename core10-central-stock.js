// Signed, read-only view of the existing canonical movement ledger.
(function (root) {
  "use strict";

  function mount({ host, client, scope, authorize, lang }) {
    const pageSize = 25;
    let offset = 0;
    let closed = false;
    let generation = 0;
    const t = (bn, en) => lang === "bn" ? bn : en;
    const element = (tag, text = "", className = "") => {
      const node = host.ownerDocument.createElement(tag);
      node.textContent = text;
      node.className = className;
      return node;
    };
    const panel = element("section", "", "op-panel");
    const title = element("h2", t("সাইটের স্টক", "Site Stock"));
    const status = element("p", "", "op-status");
    status.setAttribute("role", "status");
    const rows = element("div");
    const navigation = element("div", "", "b01-actions");
    function button(label, action) {
      const node = element("button", label, "outline");
      node.type = "button";
      node.onclick = action;
      return node;
    }
    const refresh = button(t("হালনাগাদ", "Refresh"), () => void load(0));
    const previous = button(t("আগের পৃষ্ঠা", "Previous"), () => void load(offset - pageSize));
    const next = button(t("পরের পৃষ্ঠা", "Next"), () => void load(offset + pageSize));
    navigation.append(refresh, previous, next);
    panel.append(title, status, rows, navigation);
    host.replaceChildren(panel);

    function select(table, columns, siteScoped = true) {
      const query = client.schema("core10").from(table).select(columns)
        .eq("tenant_id", scope.tenantId).eq("business_id", scope.businessId);
      return siteScoped ? query.eq("site_id", scope.siteId) : query;
    }

    function records(result) {
      if (result.error || !Array.isArray(result.data)) throw Error("CENTRAL_STOCK_READ_FAILED");
      return result.data;
    }

    async function load(start) {
      const version = ++generation;
      if (closed) return;
      rows.replaceChildren();
      refresh.disabled = previous.disabled = next.disabled = true;
      status.dataset.error = "false";
      status.textContent = t("স্টক পড়া হচ্ছে…", "Reading stock…");
      try {
        await authorize();
        const balance = records(await select("stock_summary", "location_id,item_id,net_movement")
          .order("location_id").order("item_id").range(start, start + pageSize));
        if (closed || generation !== version) return;
        const page = balance.slice(0, pageSize);
        if (page.some(row => !Number.isSafeInteger(row.location_id) || row.location_id < 1 ||
            !Number.isSafeInteger(row.item_id) || row.item_id < 1 || !Number.isFinite(row.net_movement))) {
          throw Error("CENTRAL_STOCK_READ_FAILED");
        }
        const locationIds = [...new Set(page.map(row => row.location_id))];
        const itemIds = [...new Set(page.map(row => row.item_id))];
        const [locations, items] = page.length ? await Promise.all([
          select("stock_locations", "id,code").in("id", locationIds),
          select("items", "id,sku", false).in("id", itemIds)
        ]).then(results => results.map(records)) : [[], []];
        await authorize();
        if (closed || generation !== version) return;
        const codes = new Map(locations.map(location => [location.id, location.code]));
        const skus = new Map(items.map(item => [item.id, item.sku]));
        const quantity = new Intl.NumberFormat(lang === "bn" ? "bn-BD" : "en", { maximumFractionDigits: 3 });
        for (const row of page) {
          // Both canonical metadata lookups must still be visible to this actor.
          if (!codes.has(row.location_id) || !skus.has(row.item_id)) throw Error("CENTRAL_STOCK_READ_FAILED");
        }
        for (const row of page) {
          const card = element("article", "", "op-record");
          card.append(element("strong", skus.get(row.item_id)),
            element("small", codes.get(row.location_id) + " · #" + row.location_id),
            element("p", t("নথিভুক্ত মজুত ", "Recorded on hand ") + quantity.format(row.net_movement)));
          rows.append(card);
        }
        offset = start;
        status.textContent = page.length
          ? t("রেকর্ড ", "Records ") + (start + 1) + "–" + (start + page.length)
          : t("এই সাইটে দৃশ্যমান স্টক রেকর্ড নেই।", "No visible stock records at this site.");
        previous.disabled = start === 0;
        next.disabled = balance.length <= pageSize;
      } catch {
        if (closed || generation !== version) return;
        status.dataset.error = "true";
        status.textContent = t("স্টক তথ্য পড়া যায়নি। হালনাগাদ করে দেখুন।", "Stock could not be read. Refresh to try again.");
      } finally {
        if (!closed && generation === version) refresh.disabled = false;
      }
    }

    void load(0);
    return () => { closed = true; generation++; host.replaceChildren(); };
  }

  root.CORE10_CENTRAL_STOCK = Object.freeze({ mount });
})(window);
