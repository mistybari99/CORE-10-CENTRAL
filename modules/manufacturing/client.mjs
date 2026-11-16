// Shell-injected signed RPC client only. No keys, stored role, URL-derived scope or endpoint here.
export function manufacturingClient(rpc, context) {
  if (typeof rpc !== 'function' || !context?.tenant_id || !context?.business_id || !context?.site_id) throw Error('MFG_SIGNED_CONTEXT_REQUIRED');
  const scope = Object.freeze({p_business: context.business_id, p_site: context.site_id});
  const names = new Set(['mfg_inspect_v1','mfg_material_requirements_v1','mfg_create_recipe_v1','mfg_approve_recipe_v1','mfg_plan_batch_v1','mfg_release_batch_v1','mfg_record_output_v1','mfg_cancel_batch_v1','mfg_request_handoff_v1']);
  let closed = false;
  return {
    async call(name, args = {}) {
      if (closed) throw Error('MFG_CONTEXT_CLOSED');
      if (!names.has(name)) throw Error('MFG_RPC_NOT_ALLOWED');
      // Scope is applied last: caller arguments cannot override the shell context.
      const result = await rpc(name, {...args, ...scope});
      if (closed) throw Error('MFG_CONTEXT_CLOSED');
      if (result.error) throw Error(result.error.message || 'MFG_RPC_FAILED');
      return result.data;
    },
    close() {closed = true;}
  };
}
