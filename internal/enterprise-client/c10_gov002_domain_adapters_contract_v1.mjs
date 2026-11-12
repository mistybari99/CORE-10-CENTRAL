/**
 * CORE 10 GOV-002 / source-bound future domain ports (DRAFT).
 * This intentionally cannot post stock, finance, payments, payroll or alter
 * enterprise authorization. A source ID/version from the UI is NOT proof of
 * canonical origin and an approval is NOT execution permission. Each real
 * adapter must be implemented by its owning domain and certified separately.
 */
const PORTS=Object.freeze({
  inventory_adjustment:Object.freeze({area:'inventory',allowedUnits:['KG','LB','PCS'],needsSite:true}),
  stock_transfer:Object.freeze({area:'stock_transfer',allowedUnits:['KG','LB','PCS'],needsSite:true}),
  purchase_operation:Object.freeze({area:'purchase',allowedUnits:['BDT'],needsSite:false}),
  sales_exception:Object.freeze({area:'sales',allowedUnits:['BDT','KG','LB','PCS'],needsSite:false}),
  production_exception:Object.freeze({area:'production',allowedUnits:['KG','LB','PCS'],needsSite:true}),
  financial_approval:Object.freeze({area:'finance',allowedUnits:['BDT'],needsSite:false}),
  administrative_high_risk:Object.freeze({area:'admin',allowedUnits:['BDT','KG','LB','PCS'],needsSite:false})
});
const SAFE_CLIENT_FIELDS=new Set(['operation','businessId','sourceId','sourceVersion','siteId','unit']);
const SOURCE_TOKEN=/^[A-Za-z0-9][A-Za-z0-9:_./-]{0,127}$/u;
export const GOV002_OPERATION_PORTS=Object.freeze(Object.keys(PORTS));

/** Returns only the requirements for creating a future domain-bound request.
 * Never accepts role, tenant, policy, fingerprint, authority or execution flags
 * from the UI; canonical signed server resolver must replace source metadata.
 */
export function describeGov002OperationPort(input) {
  if(!input || typeof input!=='object' || Array.isArray(input) ||
    Object.keys(input).some(k=>!SAFE_CLIENT_FIELDS.has(k))) throw new Error('untrusted_operation_authority');
  const {operation,businessId,sourceId,sourceVersion,siteId=null,unit}=input;
  const spec=PORTS[operation];
  if(!spec)throw new Error('unsupported_canonical_operation_port');
  if(!Number.isSafeInteger(businessId) || businessId<=0) throw new Error('invalid_operation_business');
  if(typeof sourceId!=='string' || !SOURCE_TOKEN.test(sourceId) ||
    !Number.isSafeInteger(sourceVersion) || sourceVersion<1)throw new Error('invalid_operation_source_binding');
  if(spec.needsSite && (!Number.isSafeInteger(siteId)||siteId<=0)) throw new Error('operation_requires_canonical_site');
  if(siteId!==null && (!Number.isSafeInteger(siteId)||siteId<=0))throw new Error('invalid_operation_site');
  if(!spec.allowedUnits.includes(unit)) throw new Error('unconfigured_approval_unit');
  // All domain operations deliberately remain blocked. No unknown "adapter"
  // function or client truthy flag can turn this intent into an execution API.
  return Object.freeze({
    contract:'c10-gov002-domain-integration-intent-v1',
    operation,business_id:businessId,site_id:siteId,
    source_reference:sourceId,observed_source_version:sourceVersion,
    requested_unit:unit,
    status:'BLOCKED_CANONICAL_DOMAIN_ADAPTER_NOT_CERTIFIED',
    side_effects_enabled:false,approval_is_not_posting:true,
    integration_requirements:Object.freeze([
      'signed_server_authoritative_actor_and_current_membership',
      'A034_effective_allow_explicit_deny_expiry_and_revocation',
      'server_issued_same_tenant_business_site_and_source_fingerprint',
      'immutable_policy_version_and_typed_threshold_match',
      'maker_checker_routing_and_live_approval_expiry',
      'domain_owned_atomic_command_and_compensating_reversal',
      'idempotency_concurrency_receipt_and_append_only_audit',
      'disposable_database_races_signed_staging_and_owner_release'
    ])
  });
}