/* Central operations routes reuse the Build 01 client and its signed scope. */
(function (root) {
  "use strict";

  function create({ client, host, onChange, onError, onSessionChanged }) {
    let active = null;
    let generation = 0;
    let actor = null;

    function clear() {
      generation++;
      const route = active;
      active = null;
      route?.dispose?.();
      host.replaceChildren();
      host.hidden = true;
      onChange();
    }

    async function authenticate(expectedActor) {
      const result = await client.auth.getUser();
      if (result.error || result.data?.user?.id !== expectedActor) {
        throw Error("BUILD01_SESSION_CHANGED");
      }
    }

    async function open({ module, businessId, siteId, context, workspace, lang }) {
      if (active) return;
      const business = context.businesses.find((item) =>
        Number(item.id) === businessId && item.can_manage === true);
      const site = workspace?.sites?.find((item) =>
        Number(item.id) === siteId && Number(item.business_id) === businessId &&
        Number(item.tenant_id) === Number(business?.tenant_id) && item.allowed_actions?.includes("stock.read"));
      if (!business || !site || Number(workspace.business_id) !== businessId ||
          workspace.actor_uid !== context.actor_uid) {
        throw Error("CENTRAL_OPERATION_SCOPE_DENIED");
      }
      if (module !== "sales" && module !== "manufacturing") throw Error("CENTRAL_OPERATION_UNKNOWN");

      const version = ++generation;
      actor = context.actor_uid;
      const expectedActor = actor;
      active = { module };
      onChange();
      try {
        await authenticate(expectedActor);
        if (generation !== version) return;
        host.hidden = false;
        if (module === "sales") {
          const sales = root.CORE10_SALES_ORDER_ENTRY.attach(host, {
            client, backendMode: "signed", lang, scopeLocked: true,
            initialScope: { businessId, siteId }
          });
          active.dispose = sales.destroy;
          active.requestLeave = sales.requestLeave;
          await sales.ready;
        } else {
          const { mountManufacturing } = await import("./modules/manufacturing/workbench.mjs");
          if (generation !== version) return;
          const manufacturing = mountManufacturing(host, {
            lang,
            central: true,
            context: { business_id: businessId, tenant_id: Number(site.tenant_id),
              site_id: siteId, label: business.label || business.slug },
            async rpc(name, args) {
              await authenticate(expectedActor);
              if (generation !== version) throw Error("BUILD01_SESSION_CHANGED");
              const result = await client.schema("core10").rpc(name, args);
              await authenticate(expectedActor);
              if (generation !== version) throw Error("BUILD01_SESSION_CHANGED");
              return result;
            }
          });
          active.dispose = manufacturing;
          active.requestLeave = manufacturing.requestLeave;
        }
      } catch (error) {
        if (generation !== version) return;
        clear();
        if (error.message === "BUILD01_SESSION_CHANGED") onSessionChanged();
        throw error;
      }
    }

    function close() {
      if (active?.requestLeave) active.requestLeave(clear);
      else clear();
    }

    function clearSession() {
      actor = null;
      clear();
      onSessionChanged();
    }

    // Supabase dispatches Auth events inside its session lock. Cleanup is
    // synchronous and never starts another Auth request in the callback.
    const auth = client.auth.onAuthStateChange?.((event, session) => {
      if (event === "SIGNED_OUT" || (event === "SIGNED_IN" && actor && session?.user?.id !== actor)) {
        clearSession();
      } else if (event !== "INITIAL_SESSION" && active?.module === "sales") {
        clear();
      }
    });
    if (!auth?.data?.subscription?.unsubscribe) {
      onError(Error("CENTRAL_AUTH_SUBSCRIPTION_REQUIRED"));
      return null;
    }
    return Object.freeze({ open, close, clear, isOpen: () => active !== null });
  }

  root.CORE10_CENTRAL_OPERATIONS = Object.freeze({ create });
})(window);
