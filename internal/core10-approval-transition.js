'use strict';
// Isolated domain transition planner. NOT an authorization boundary or DB writer.
const ACTIONS = Object.freeze({approve:'approved',reject:'rejected',defer:'deferred'});
function planApproval(input) {
  const fail = reason => ({ok:false,reason});
  if (!input || !['approve','reject','defer'].includes(input.action)) return fail('invalid_action');
  const {request,actor} = input;
  if (!request || !actor || !Number.isSafeInteger(request.business_id) || request.business_id<=0 ||
      !Number.isSafeInteger(actor.business_id) || actor.business_id<=0 ||
      request.business_id!==actor.business_id) return fail('business_scope_mismatch');
  if (typeof actor.user_id!=='string' || !actor.user_id || !actor.active || actor.revoked ||
      !['business_owner','approver'].includes(actor.role)) return fail('approver_not_authorized');
  if (request.created_by===actor.user_id) return fail('maker_approver_conflict');
  if (request.status!=='pending') return fail('invalid_transition');
  if (typeof request.id!=='string' || !request.id || typeof input.idempotency_key!=='string' ||
      !/^[A-Za-z0-9_-]{8,128}$/.test(input.idempotency_key)) return fail('invalid_identity');
  return {ok:true,command:Object.freeze({request_id:request.id,business_id:request.business_id,
    expected_status:'pending',next_status:ACTIONS[input.action],actor_id:actor.user_id,
    idempotency_key:input.idempotency_key}),simulation_only:true};
}
module.exports={planApproval};
