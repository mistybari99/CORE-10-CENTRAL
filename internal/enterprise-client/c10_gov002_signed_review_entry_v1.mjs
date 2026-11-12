/** Optional GOV002 staging integration, never auto-mounts into Islamiya ERP.
 * The browser Supabase client must already have a signed user. Business choices
 * are labels only; canonical RPC and RLS decide all access and side effects.
 */
import {createGov002ReviewClient} from './c10_gov002_signed_review_client_v1.mjs';
import {createGov002SessionBoundReviewClient} from './c10_gov002_session_bound_review_v1.mjs';
import {mountGov002ApprovalUI} from './c10_gov002_review_ui_v1.mjs';

export function mountSignedGov002Workspace({root,supabaseClient,businessId,businesses,
 allowSignedMutations=false,environmentLabel='STAGING · NOT CERTIFIED'}={}){
  if(!root||typeof root.replaceChildren!=='function')throw new Error('dedicated_approval_root_required');
  let screen=null,guard=null;
  const signed=createGov002ReviewClient(supabaseClient);
  function clearOnSessionSwitch(){
    screen?.destroy();
    root.replaceChildren();
    // Plain DOM text; never render error/SQL/client message as HTML.
    const note=root.ownerDocument.createElement('p');
    note.textContent='সেশন বা ব্যবহারকারী পরিবর্তিত হয়েছে। নিরাপদভাবে আবার লগইন করে Approval খুলুন।';
    note.setAttribute('role','alert');
    root.append(note);
  }
  guard=createGov002SessionBoundReviewClient({supabaseClient,reviewClient:signed,
    onInvalidated:clearOnSessionSwitch});
  try{
    screen=mountGov002ApprovalUI({root,reviewClient:guard,businessId,businesses,
      actionsEnabled:allowSignedMutations===true,environmentLabel});
  }catch(error){guard.destroy();throw error;}
  return Object.freeze({
    refresh:()=>screen.refresh(),selectBusiness:(next)=>screen.selectBusiness(next),
    getState:()=>Object.freeze({...screen.getState(),session:guard.getState()}),
    destroy:()=>{guard.destroy();screen.destroy();}
  });
}