# C10-A056 RPC Contract (Universal CRM, Customer Lifecycle & Sales Integration)

Status: DRAFT contract, source-built on disposable PostgreSQL only. Not production, not GoTrue-verified.
Schema: `c10_demo`. All RPC names end `_v1` and start `a056_`. Called through the signed client
`client.schema("c10_demo").rpc(name, args)` (same pattern as A050), wrapped by `core10-crm-lifecycle-client.js`.

## Conventions
- Args are named `p_*`. Every write takes `p_request text` matching `^[A-Za-z0-9_-]{8,100}$` (idempotency key, per business).
  Same key + same args => original receipt with `"replayed":true`. Same key + different args => `A056_REQUEST_REPLAY_CONFLICT`.
- Versioned rows: updates take `p_expected bigint`; mismatch => `A056_STALE_<ENTITY>`. Receipts return the new `version`.
- All RPCs return `jsonb`. Lists return `{"items":[...],"total":n,"limit":n,"offset":n}` (limit max 200, default 50).
- Money is `numeric` serialised as JSON number or **null** (null = unknown/unavailable, never zero). Currency `BDT`.
- Errors are raised as `A056_*` codes (message text only). Frontend must map codes to messages. Common:
  `A056_SIGNED_USER_REQUIRED, A056_DENIED, A056_MODULE_DISABLED, A056_NOT_FOUND, A056_INVALID, A056_STALE_*,
  A056_REQUEST_REPLAY_CONFLICT, A056_OPT_OUT_PRECEDENCE, A056_NO_CONSENT, A056_THROTTLED, A056_TOKEN_INVALID`.
- Authorization is server-side from live A018 memberships (tenant owner / business owner / manager / site grants);
  revoking a role takes effect on the next call. Investors and unknown users are denied. Action tiers
  (`owner` | `manager` | `site`) come from the versioned config (`a056_read_settings_v1`); defaults below.
  `site` tier = any active site grant for the record's site (managers/owners always pass). Site staff only see rows of their granted sites.
- Module is OFF until an Owner enables it (`a056_set_settings_v1`); all other RPCs raise `A056_MODULE_DISABLED`.
- Every write appends to the append-only audit trail (`a056_list_audit_v1`).

## Default action tiers (Owner-editable, invariants locked)
`customer.read/write, lead.write, enquiry.triage, opportunity.write, opportunity.stage, quote.write, followup.write,
ticket.write, ticket.resolve, consent.write, report.read` = site;
`customer.merge, customer.export, quote.approve, quote.convert, segment.write, campaign.write, campaign.dispatch,
intake.manage, finance.read, consent.lift_suppression` = manager;
`settings.write, customer.redact, finance.register` = owner (locked, cannot be lowered).

## Settings / access (owner = `settings.write`)
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_read_settings_v1 | p_business | `{business_id,enabled,version,config{stages[],permissions{},approval{},sla{},loyalty{},intake{}},defaults}` | any CRM-visible role |
| a056_set_settings_v1 | p_business,p_enabled,p_config jsonb,p_expected,p_request,p_reason | `{business_id,version,enabled,replayed}` | settings.write |
| a056_list_settings_history_v1 | p_business,p_limit | `{items:[{version,enabled,config,actor,reason,created_at}]}` | settings.write |
| a056_read_my_access_v1 | p_business | `{enabled,actions:{<action>:bool}}` | signed user |
| a056_list_audit_v1 | p_business,p_entity,p_limit | `{items:[{id,actor,action,entity,entity_id,created_at,detail}]}` | manager |

## Customers, contacts, duplicates
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_customer_v1 | p_business,p_site,p_kind('person'\|'organization'),p_display_name,p_legal_name,p_email,p_phone,p_tags text[],p_request | `{customer_id,version,replayed}` | customer.write |
| a056_update_customer_v1 | p_customer,p_patch jsonb{display_name,legal_name,email,phone,tags,site_id},p_expected,p_request | `{customer_id,version}` | customer.write |
| a056_list_customers_v1 | p_business,p_search,p_status,p_limit,p_offset | list of `{id,kind,display_name,legal_name,email,phone,site_id,status,tags,version}` | customer.read |
| a056_read_customer360_v1 | p_customer | `{customer,contacts[],consents[],leads[],enquiries[],opportunities[],quotations[],orders[],tickets[],followups[],timeline[],purchase{...},finance{status,...}}` | customer.read |
| a056_add_contact_v1 | p_customer,p_name,p_role,p_email,p_phone,p_primary,p_request | `{contact_id}` | customer.write |
| a056_deactivate_contact_v1 | p_contact,p_expected,p_request | `{contact_id,version}` | customer.write |
| a056_log_contact_v1 | p_customer,p_lead,p_opportunity,p_type('call'\|'visit'\|'email'\|'message'\|'note'),p_direction('in'\|'out'\|'internal'),p_summary,p_occurred_at,p_request | `{history_id}` | customer.write |
| a056_scan_duplicates_v1 | p_business,p_request | `{created,open}` | customer.merge |
| a056_list_duplicate_candidates_v1 | p_business,p_status,p_limit,p_offset | list of `{id,customer_a,customer_b,reason,score,status,names}` | customer.merge |
| a056_dismiss_duplicate_v1 | p_candidate,p_request | `{id,status:'dismissed'}` | customer.merge |
| a056_merge_customers_v1 | p_survivor,p_loser,p_expected_survivor,p_expected_loser,p_request,p_reason | `{survivor_id,loser_id,moved{...},version}` | customer.merge |

## Consent & communication preferences
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_record_consent_v1 | p_customer,p_channel('email'\|'sms'\|'phone'\|'whatsapp'\|'post'),p_purpose('marketing'\|'service'),p_status('granted'\|'revoked'\|'opt_out'),p_source,p_valid_until,p_lift_suppression,p_request | `{event_id,effective:{can_send,reason}}` | consent.write (lift: consent.lift_suppression) |
| a056_check_consent_v1 | p_customer,p_channel,p_purpose | `{can_send,reason}` reasons: `granted, no_consent, revoked, expired, opt_out_precedence, customer_inactive` | customer.read |
| a056_set_comm_prefs_v1 | p_customer,p_preferred_channel,p_language,p_request | `{customer_id}` | consent.write |

## Leads, enquiries
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_lead_v1 | p_business,p_site,p_source,p_name,p_email,p_phone,p_note,p_customer,p_request | `{lead_id,status:'new',version}` | lead.write |
| a056_qualify_lead_v1 | p_lead,p_decision('qualified'\|'disqualified'),p_reason,p_expected,p_request | `{lead_id,status,version}` | lead.write |
| a056_list_leads_v1 | p_business,p_status,p_limit,p_offset | list | lead.write |
| a056_create_enquiry_v1 | p_business,p_site,p_channel,p_subject,p_body,p_customer,p_lead,p_request | `{enquiry_id,status:'RECEIVED'}` | lead.write |
| a056_triage_enquiry_v1 | p_enquiry,p_action('triage'\|'to_lead'\|'close'),p_customer,p_expected,p_request | `{enquiry_id,status,lead_id?,version}` | enquiry.triage |
| a056_list_enquiries_v1 | p_business,p_status,p_limit,p_offset | list (status RECEIVED/DRAFT/triaged/converted/closed) | enquiry.triage |

## Opportunities (pipeline)
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_opportunity_v1 | p_business,p_site,p_customer,p_lead,p_enquiry,p_title,p_expected_value(null ok),p_expected_close,p_owner,p_request | `{opportunity_id,stage,version}` | opportunity.write |
| a056_move_opportunity_stage_v1 | p_opp,p_stage,p_expected,p_reason,p_request | `{opportunity_id,stage,status,version}` (`won` requires an accepted+converted quote; stages flagged approval need `quote.approve` tier) | opportunity.stage |
| a056_list_opportunities_v1 | p_business,p_stage,p_status,p_limit,p_offset | list | opportunity.write |
| a056_read_pipeline_v1 | p_business | `{stages:[{code,label,kind,count,value_advisory}],note}` (value null when no quoted values) | report.read |

## Quotations (versioned, immutable versions)
Lines JSON: `[{description,quantity,unit_price,discount_pct,item_id?}]`.
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_quotation_v1 | p_opp,p_lines,p_valid_until,p_notes,p_request | `{quotation_id,quote_no,version_no:1,total,requires_approval}` | quote.write |
| a056_revise_quotation_v1 | p_quotation,p_lines,p_valid_until,p_notes,p_expected_version,p_request | `{quotation_id,version_no,total,requires_approval}` (old version -> superseded) | quote.write |
| a056_decide_quotation_v1 | p_quotation,p_version_no,p_decision('submit'\|'approve'\|'reject'\|'send'\|'accept'\|'decline'),p_note,p_request | `{quotation_id,version_no,status}`; approve: creator cannot self-approve when approval required | submit/send/accept/decline: quote.write; approve/reject: quote.approve |
| a056_read_quotation_v1 | p_quotation | `{quotation,versions:[{version_no,status,total,lines[],approval}]}` | quote.write |
| a056_list_quotations_v1 | p_business,p_status,p_limit,p_offset | list | quote.write |

## Sales / order integration (via A049 canonical contracts only)
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_convert_quote_to_order_v1 | p_quotation,p_version_no,p_location,p_request | `{links:[{link_id,a049_order_id,status:'draft'}],adapter:'A049_CANONICAL'}` — calls `create_operation_order_v1` (draft only; confirm/post stay in A049) | quote.convert |
| a056_TEST_ADAPTER_create_order_v1 | same | `{adapter:'TEST_ADAPTER',...}` only when A049 contract is absent; otherwise `A056_USE_CANONICAL_ADAPTER` | quote.convert |
| a056_read_order_links_v1 | p_business,p_customer(null=all) | list `{link_id,quotation_id,a049_order_id,order_status,fulfilment:'unavailable'\|'draft'\|'confirmed'\|'posted',estimate_total}` read through `read_operation_overview_v1` | customer.read |
| a056_read_purchase_history_v1 | p_customer | `{orders[],posted_count,estimate_total_advisory,first_purchase,last_purchase,certified:false}` | customer.read |

## Finance (certified read models only)
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_register_finance_source_v1 | p_business,p_read_fn text,p_certification_ref,p_certified,p_expected,p_request | `{business_id,version,certified}` | finance.register (owner) |
| a056_read_customer_finance_v1 | p_customer | `{status:'NOT_CERTIFIED'\|'UNAVAILABLE'\|'CERTIFIED',balance_due:null\|n,payment_status:null\|text,invoices_status,source,reason}` — never fabricated | finance.read |

## Support
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_ticket_v1 | p_business,p_site,p_customer,p_kind('complaint'\|'service'\|'warranty'\|'return_request'),p_priority('urgent'\|'standard'\|'low'),p_subject,p_description,p_order_link,p_request | `{ticket_id,status:'open',sla_due_at,version}` (return_request records intent only; no refund/stock) | ticket.write |
| a056_update_ticket_v1 | p_ticket,p_action('assign'\|'start'\|'wait'\|'respond'\|'resolve'\|'close'\|'reopen'),p_assignee,p_note,p_evidence,p_expected,p_request | `{ticket_id,status,version,sla_breached}` (resolve needs note+evidence; resolve/close: ticket.resolve) | ticket.write |
| a056_list_tickets_v1 | p_business,p_status,p_limit,p_offset | list with `sla_state: ok\|at_risk\|breached\|met` | ticket.write |

## Follow-ups
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_followup_v1 | p_business,p_site,p_customer,p_opportunity,p_ticket,p_due_at,p_note,p_assignee,p_request | `{followup_id,version}` | followup.write |
| a056_complete_followup_v1 | p_followup,p_outcome('done'\|'cancelled'),p_note,p_expected,p_request | `{followup_id,status,version}` | followup.write |
| a056_list_followups_v1 | p_business,p_status,p_due_before,p_limit,p_offset | list | followup.write |

## Segmentation, campaigns, loyalty
Segment definition (whitelisted): `{"kind":"person|organization","tags_any":[..],"site_id":n,"min_posted_orders":n,"max_days_since_purchase":n,"has_consent":{"channel":"email","purpose":"marketing"}}`.
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_save_segment_v1 | p_business,p_segment(null=new),p_name,p_definition,p_expected,p_request | `{segment_id,version}` | segment.write |
| a056_list_segments_v1 | p_business | list | segment.write |
| a056_evaluate_segment_v1 | p_segment | `{count,customer_ids[]}` | segment.write |
| a056_create_campaign_v1 | p_business,p_name,p_channel,p_segment,p_template,p_request | `{campaign_id,status:'draft'}` | campaign.write |
| a056_dispatch_campaign_v1 | p_campaign,p_request | `{considered,eligible,blocked,by_reason{},provider:'NOOP',sent:0}` (consent-aware; NO real sending) | campaign.dispatch |
| a056_list_campaigns_v1 / a056_read_campaign_v1 | p_business,p_limit / p_campaign | list / `{campaign,recipients[]}` | campaign.write |
Loyalty config lives in settings config `loyalty` (versioned); advisory only, no points ledger in this package.

## Intake contracts (website / e-commerce / POS / offline / phone)
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_create_intake_endpoint_v1 | p_business,p_site,p_channel('website'\|'ecommerce'\|'pos'\|'offline'\|'phone'),p_label,p_rate_limit_per_hour,p_request | `{endpoint_id,token}` token shown ONCE (only sha256 stored) | intake.manage |
| a056_revoke_intake_endpoint_v1 | p_endpoint,p_request | `{endpoint_id,status:'revoked'}` | intake.manage |
| a056_list_intake_endpoints_v1 | p_business | list (no token) | intake.manage |
| a056_public_intake_v1 | p_token,p_idempotency,p_payload jsonb{intent:'enquiry'\|'quote_request'\|'order_request',name,email,phone,subject,message,lines[],consent{marketing_email,marketing_sms}} | `{reference,status:'RECEIVED'\|'DRAFT',replayed}` — executable by `anon`; never creates order/stock/refund; consent is a *claim* applied only after staff triage | token |

## Reports & privacy
| RPC | Args | Returns | Perm |
|---|---|---|---|
| a056_report_dashboard_v1 | p_business,p_from,p_to | `{leads,enquiries,opportunities_open,quotes_pending_approval,tickets_open,followups_overdue,customers,advisory_pipeline_value,certified:false}` | report.read |
| a056_report_funnel_v1 | p_business,p_from,p_to | `{stages:[{stage,count,rate_from_prev}],lead_to_order_rate}` | report.read |
| a056_report_retention_v1 | p_business,p_months | `{cohorts:[{cohort_month,customers,repeat_customers,repeat_rate}],source:'A049_posted_orders'}` | report.read |
| a056_report_repeat_business_v1 | p_business | `{customers_with_orders,repeat_customers,repeat_rate}` (null rate when 0 denominators) | report.read |
| a056_report_followups_v1 | p_business | `{overdue[],due_today[],upcoming[]}` | report.read |
| a056_report_tickets_v1 | p_business,p_from,p_to | `{opened,resolved,sla_met,sla_breached,avg_resolution_hours(null if none),by_priority{}}` | report.read |
| a056_export_customer_v1 | p_customer,p_request | full subject-data package jsonb | customer.export |
| a056_export_customers_csv_v1 | p_business | `text` CSV, formula-injection neutralised | customer.export |
| a056_redact_customer_v1 | p_customer,p_expected,p_reason,p_request | `{customer_id,status:'redacted',version}`; opt-out suppression hashes retained | customer.redact (owner) |

## Reality labels (must be shown in UI)
Orders are A049 *drafts* until A049 staff confirm/post; no revenue/COGS/profit is produced by CRM. Balances/payment status show
`NOT CERTIFIED` unless the Owner registers and certifies a finance read model. Campaign dispatch is a NO-OP provider. Public intake is RECEIVED/DRAFT only.
