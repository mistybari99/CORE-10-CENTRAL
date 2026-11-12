/** Optional integration entry for a future Owner-approved authenticated staging host.
 * Does not auto-initialize or replace existing Islamiya ERP / preview pages.
 * Requires an injected browser Supabase client with an existing signed session.
 * Business labels/choices are presentation-only, not trusted permissions.
 */
import { createGov002ReviewClient } from './c10_gov002_signed_review_client_v1.mjs';
import { mountGov002ApprovalUI } from './c10_gov002_review_ui_v1.mjs';
export function mountSignedGov002Workspace({root,supabaseClient,businessId,businesses,
    allowSignedMutations=false,environmentLabel='STAGING · NOT CERTIFIED'}={}){
  const signed = createGov002ReviewClient(supabaseClient);
  return mountGov002ApprovalUI({root,reviewClient:signed,businessId,businesses,
    actionsEnabled:allowSignedMutations === true,environmentLabel});
}