// GOV-003 reviewer UI. DEMO / NOT LIVE - synthetic data. Same-origin module; no framework, no third-party script,
// no innerHTML (every string is inserted as text). Every button below calls the real local API, which calls the real
// local PostgreSQL test bed. Nothing on this page is a static sample pretending to be live.
import { createApiClient, newKey, sha256Hex } from '/client/api-client.js';

// ------------------------------------------------------------------------------------------------ i18n
// [bangla, english]. Bangla is the default language; English is a toggle.
const D = {
  skip: ['মূল অংশে যান', 'Skip to main content'],
  banner_sub: ['স্থানীয় পরীক্ষা-সার্ভার, কৃত্রিম তথ্য। এটি কোনো সত্যিকারের ব্যবসা, অর্থ বা স্টক নয়।', 'Local test server, synthetic data. This is not a real business, money or stock.'],
  title: ['নিরীক্ষা ও প্রস্তুতির সত্য-পর্যালোচনা', 'Audit and readiness truth review'],
  identity_label: ['পরিচয় (কৃত্রিম ফিক্সচার)', 'Identity (synthetic fixture)'],
  target_label: ['লক্ষ্য ব্যবসা', 'Target business'],
  lang_label: ['ভাষা', 'Language'],
  loading: ['লোড হচ্ছে...', 'Loading...'],
  foot1: ['এই পাতার প্রতিটি বোতাম স্থানীয় API ও স্থানীয় PostgreSQL ডাটাবেসকে সত্যিই ডাকে। স্ট্যাটিক নমুনা দেখানো হয় না।', 'Every button on this page really calls the local API and the local PostgreSQL database. No static sample is shown as live.'],
  foot2: ['পরিচয় একটি ফিক্সচার লেবেল, স্বাক্ষরিত GoTrue সেশন নয়। হ্যাশ-চেইন পরিবর্তনের প্রমাণ দেয়, WORM সুরক্ষা নয়। সংকেত কেবল পরামর্শ।', 'The identity is a fixture label, not a signed GoTrue session. A hash chain is tamper-evidence, not WORM protection. Signals are advisory only.'],
  acting: ['এখন কাজ করছেন', 'Acting as'],
  signed_no: ['স্বাক্ষরিত সেশন নয়', 'not a signed session'],
  read: ['পড়া', 'read'], write: ['লেখা', 'write'], no_access: ['প্রবেশাধিকার নেই', 'no access'],
  tab_audit: ['অডিট জার্নাল', 'Audit journal'], tab_signals: ['ঝুঁকি সংকেত', 'Risk signals'], tab_incidents: ['ঘটনা ও প্রমাণ', 'Incidents and evidence'],
  tab_readiness: ['প্রস্তুতির সত্য-সারণি', 'Readiness truth'], tab_export: ['এক্সপোর্ট', 'Export'], tab_errors: ['নিরাপদ ত্রুটি', 'Safe errors'], tab_grants: ['অনুমতি পর্যালোচনা', 'Grant review'],
  how_to_read: ['কীভাবে পড়বেন', 'How to read this'],
  refresh: ['রিফ্রেশ', 'Refresh'], apply: ['প্রয়োগ', 'Apply'], all: ['সব', 'All'], none: ['(নেই)', '(none)'],
  // states
  denied_title: ['প্রবেশ অনুমোদিত নয়', 'Access denied'],
  denied_text: ['এই পরিচয়ের এই ব্যবসায় এই কাজের অধিকার নেই। কারণ বা অস্তিত্ব সম্পর্কে কিছু জানানো হয় না, এবং কোনো সংখ্যাও দেখানো হয় না।', 'This identity has no right to do this in this business. No reason, no existence hint and no count is revealed.'],
  unauth_title: ['অনুমোদন হয়নি', 'Not authenticated'],
  conflict_title: ['সংঘাত (409)', 'Conflict (409)'],
  invalid_title: ['যাচাই ব্যর্থ (422)', 'Validation or integrity failed (422)'],
  error_title: ['ত্রুটি', 'Error'],
  network_title: ['সার্ভারে পৌঁছানো যায়নি', 'Server not reachable'],
  empty_title: ['কিছু নেই', 'Nothing here'],
  // audit
  audit_lead: ['প্রতিটি ঘটনা: কে, কী, কখন, কেন, কোন ব্যবসা/সাইট, কোন উৎস-সংস্করণ, সঙ্গে হ্যাশ-চেইন ও রসিদ।', 'Every event: who, what, when, why, business/site scope and source version, chained by hash and receipted.'],
  audit_help1: ['শুধু ব্যবসার মালিক বা টেন্যান্ট মালিক এই জার্নাল পড়তে পারেন। সাইট-স্টাফ, বিনিয়োগকারী, বাতিল সদস্য, সহায়তা-অপারেটর ও অন্য টেন্যান্ট কিছুই দেখে না, সংখ্যাও না।', 'Only the business owner or tenant owner can read this journal. Site staff, investors, revoked members, support operators and other tenants see nothing, not even a count.'],
  audit_help2: ['"চেইন যাচাই" সম্পূর্ণ হ্যাশ-চেইন আবার গণনা করে। এটি সাধারণ ব্যবহারকারীর পরিবর্তন ধরে, কিন্তু সুবিধাপ্রাপ্ত DBA-র বিরুদ্ধে আইনি WORM নয়।', '"Verify chain" recomputes the whole hash chain. It detects edits by ordinary principals; it is not legal WORM protection against a privileged DBA.'],
  stat_total: ['এই ব্যবসার মোট ঘটনা', 'Events in this business'], stat_filtered: ['ফিল্টার করা ঘটনা', 'Filtered events'], stat_chain: ['চেইন অবস্থা', 'Chain status'],
  f_action: ['কমান্ড', 'Action'], f_domain: ['উৎস ডোমেইন', 'Source domain'], f_from: ['শুরুর তারিখ', 'From date'], f_to: ['শেষ তারিখ (অন্তর্ভুক্ত)', 'To date (inclusive)'],
  verify_chain: ['চেইন যাচাই', 'Verify chain'], chain_ok: ['অক্ষত', 'intact'], chain_bad: ['ভাঙা', 'broken'], chain_unknown: ['যাচাই হয়নি', 'not verified'],
  checked: ['{n}টি ঘটনা যাচাই', '{n} events checked'], seq: ['ক্রম', 'seq'],
  details: ['বিস্তারিত', 'Details'], payload: ['অনুমোদিত পেলোড', 'Approved payload'], receipt: ['রসিদ', 'Receipt'], prior: ['পূর্ববর্তী ডাইজেস্ট', 'Prior digest'], digest: ['ডাইজেস্ট', 'Digest'],
  correlation: ['সংযোগ-আইডি', 'Correlation id'], idem_key: ['আইডেম্পোটেন্সি কী', 'Idempotency key'], reason: ['কারণ-শ্রেণি', 'Reason category'], actor: ['কর্তা', 'Actor'], scope_site: ['সাইট', 'Site'], source_ver: ['উৎস-সংস্করণ', 'Source version'],
  empty_audit: ['এই ফিল্টারে কোনো ঘটনা নেই।', 'No events match this filter.'],
  append_title: ['একটি ফিক্সচার ঘটনা যোগ করুন', 'Append a fixture event'],
  append_help: ['কর্তা ব্রাউজার থেকে আসে না: সার্ভার সেশন থেকে কর্তা নির্ধারণ করে। একই কী ও একই বিষয়বস্তু আবার পাঠালে পুরোনো রসিদই ফেরে; একই কী ও বদলানো বিষয়বস্তু 409 হয়।', 'The actor never comes from the browser: the server derives it from the session. Sending the same key and content again returns the original receipt; the same key with changed content is a 409.'],
  f_preset: ['ঘটনার ধরন', 'Event type'], f_source: ['উৎস-আইডি', 'Source id'], f_amount: ['পরিমাণ (ক্ষুদ্রতম এককে)', 'Amount (minor units)'], f_site: ['সাইট', 'Site'],
  site_business: ['(ব্যবসা-স্তর)', '(business level)'],
  btn_append: ['ঘটনা যোগ করুন', 'Append event'], btn_replay: ['একই অনুরোধ আবার পাঠান', 'Replay the same request'], btn_changed: ['একই কী, বদলানো পরিমাণ', 'Same key, changed amount'],
  res_created: ['সংরক্ষিত (201)', 'Stored (201)'], res_replayed: ['পুনরাবৃত্তি: পুরোনো রসিদ (200)', 'Replay: original receipt (200)'],
  // signals
  signals_lead: ['কনফিগার করা অসংগতি থেকে ব্যাখ্যাযোগ্য সংকেত, তারপর মানুষের পর্যালোচনা।', 'Explainable signals from configured anomaly rules, then human review.'],
  advisory: ['শুধুই পরামর্শ: এগুলো অভিযোগ নয়। কোনো স্টক, অর্থ, অনুমোদন বা ভূমিকা স্বয়ংক্রিয়ভাবে বদলায় না, ফ্রিজ বা ব্লক হয় না। মানুষের পর্যালোচনা দরকার।', 'ADVISORY ONLY: these are not accusations. Nothing is frozen, blocked, paid, approved or changed automatically. Human review is required.'],
  signals_help: ['"এখনই শনাক্ত করুন" ডাটাবেসের সত্যিকারের ঘটনাগুলোর ওপর নিয়ম চালায়। পর্যালোচক অবশ্যই প্রমাণ-ঘটনার কর্তা ছাড়া অন্য একজন মালিক হতে হবে। প্রতিটি সংকেতের একটিই চূড়ান্ত অবস্থা থাকে; দ্বিতীয় পর্যালোচনা 409 পায়।', '"Detect now" runs the rules over the real events in the database. The reviewer must be an owner other than the actors of the evidence. Each signal has exactly one terminal state; a second review gets a 409.'],
  detect: ['এখনই শনাক্ত করুন', 'Detect now'], detected: ['নতুন সংকেত: {n}, আগে থেকে ছিল: {m}', 'New signals: {n}, already existed: {m}'],
  empty_signals: ['কোনো সংকেত নেই। "এখনই শনাক্ত করুন" চাপুন।', 'No signals yet. Press "Detect now".'],
  rule_dup_key: ['একই আইডেম্পোটেন্সি কী বারবার', 'Idempotency key repeated'], rule_dup_content: ['একই বিষয়বস্তু নতুন কী-তে', 'Same content under new keys'],
  rule_volume_spike: ['অস্বাভাবিক ঘটনার পরিমাণ', 'Unexpected event volume'], rule_stale_source: ['উৎস নীরব', 'Source gone quiet'],
  rule_unauthorized_command: ['মালিক নন এমন পরিচয়ের সংবেদনশীল কমান্ড', 'Sensitive command outside an owner role'], rule_grant_policy_diff: ['অনুমতি তালিকা ভিত্তি থেকে ভিন্ন', 'Permission catalog differs from baseline'],
  sev_low: ['নিম্ন', 'low'], sev_medium: ['মাঝারি', 'medium'], sev_high: ['উচ্চ', 'high'],
  st_open: ['খোলা', 'open'], st_acknowledged: ['স্বীকৃত', 'acknowledged'], st_dismissed: ['খারিজ', 'dismissed'],
  confidence: ['আস্থা', 'Confidence'], evidence: ['মূল প্রমাণ', 'Original evidence'], evidence_actors: ['প্রমাণ-ঘটনার কর্তা', 'Evidence actors'],
  window: ['সময়-পরিসর', 'Window'], reviewed_by: ['পর্যালোচক', 'Reviewed by'],
  f_decision: ['সিদ্ধান্ত', 'Decision'], f_reason: ['কারণ-কোড', 'Reason code'], dec_acknowledge: ['স্বীকার (পরবর্তী পদক্ষেপ লাগবে)', 'Acknowledge (follow-up)'], dec_dismiss: ['খারিজ', 'Dismiss'],
  btn_review: ['পর্যালোচনা রেকর্ড করুন', 'Record review'], review_done: ['পর্যালোচনা রসিদসহ রেকর্ড হয়েছে।', 'Review recorded with a receipt.'],
  rc_followup_required: ['পরবর্তী পদক্ষেপ দরকার', 'follow-up required'], rc_under_investigation: ['তদন্তাধীন', 'under investigation'], rc_known_issue: ['জানা সমস্যা', 'known issue'],
  rc_false_positive: ['ভুল শনাক্তকরণ', 'false positive'], rc_expected_activity: ['প্রত্যাশিত কার্যকলাপ', 'expected activity'], rc_duplicate_signal: ['সদৃশ সংকেত', 'duplicate signal'],
  rc_test_activity: ['পরীক্ষামূলক কার্যকলাপ', 'test activity'], rc_accepted_risk: ['গৃহীত ঝুঁকি', 'accepted risk'],
  // incidents
  inc_lead: ['ঘটনা খোলা, প্রমাণ-তালিকা অপরিবর্তনীয়, ধারণ (hold) থাকলে মোছা অচল।', 'Incident opened, evidence manifest immutable, deletion blocked while a hold is active.'],
  inc_help: ['"মোছার চেষ্টা" সত্যিই পারজ ফাংশন ডাকে। হোল্ড বা সংরক্ষণ-নিয়ম থাকলে সেটি প্রত্যাখ্যান হয় (G3H02) এবং প্রত্যাখ্যানও একটি রসিদে লেখা হয়। এটি আইনি হোল্ডের প্রত্যয়ন নয়।', '"Attempt purge" really calls the purge function. With a hold or retention rule it is refused (G3H02) and the refusal itself is recorded in a receipt. This is not a legal-hold certification.'],
  case: ['ঘটনা', 'Case'], manifest: ['প্রমাণ-তালিকা', 'Manifest'], manifest_ok: ['অক্ষত', 'intact'], manifest_bad: ['অখণ্ডতা ব্যর্থ', 'integrity failed'], items: ['{n}টি প্রমাণ', '{n} items'],
  holds: ['ধারণ (hold)', 'Holds'], evidence_items: ['প্রমাণ-আইটেম', 'Evidence items'], retention_until: ['সংরক্ষণ-সীমা', 'Retention until'],
  hold_in_force: ['কার্যকর', 'in force'], hold_released: ['মুক্ত', 'released'], review_pending: ['পর্যালোচনা বাকি', 'review pending'], review_approved: ['পর্যালোচিত: অনুমোদিত', 'reviewed: approved'], review_rejected: ['পর্যালোচিত: প্রত্যাখ্যাত', 'reviewed: rejected'],
  btn_purge: ['মোছার চেষ্টা', 'Attempt purge'], purge_refused: ['প্রত্যাখ্যাত: প্রমাণ হোল্ড/সংরক্ষণের অধীনে', 'Refused: the evidence is under hold or retention'],
  purge_done: ['ফলাফল: {o}', 'Outcome: {o}'], protection: ['সুরক্ষার কারণ', 'Protection'], purged_mark: ['মোছা (টম্বস্টোন)', 'purged (tombstone)'],
  legal_note: ['এটি শুধু একটি পরিবর্তনযোগ্য ডাটাবেসের প্রকৌশল-নিয়ন্ত্রণ। আইনি ধারণ-প্রত্যয়ন নয়; আইনি সংরক্ষণ-সিদ্ধান্ত মালিক/আইনজীবীর।', 'An engineering control in a mutable database only. Not a legal-hold certification; legal retention is an owner/counsel decision.'],
  empty_incidents: ['কোনো ঘটনা নেই।', 'No incident cases.'],
  // readiness
  ready_lead: ['প্রস্তুতি প্রমাণ-সারি থেকে নির্ধারিত হয়, হাতে বসানো সবুজ টিক থেকে নয়।', 'Readiness is derived from proof rows, never from a hand-set green tick.'],
  ready_help: ['একটি ধাপ তখনই সবুজ যখন বর্তমান হেড SHA-র সঙ্গে বাঁধা পাস-প্রমাণ থাকে। পুরোনো SHA-র পাস পুনর্ব্যবহার হয় না। সিমুলেটেড/আইসোলেটেড প্রমাণ কখনো স্বাক্ষরিত সেশন, ইন্টিগ্রেশন, ডিপ্লয় বা রিলিজ ধাপ সবুজ করে না।', 'A step is green only when a passing proof is bound to the CURRENT head SHA. An old SHA pass is never reused. Simulated or isolated proof can never turn the signed-session, integration, deployment or release steps green.'],
  lv_proposed: ['প্রস্তাবিত', 'Proposed'], lv_code_built: ['কোড তৈরি', 'Code built'], lv_isolated_test_pass: ['আইসোলেটেড টেস্ট পাস', 'Isolated test pass'], lv_signed_stage_verified: ['স্বাক্ষরিত স্টেজ যাচাই', 'Signed stage verified'],
  lv_integrated_verified: ['ইন্টিগ্রেশন যাচাই', 'Integrated verified'], lv_deployed_verified: ['ডিপ্লয় যাচাই', 'Deployed verified'], lv_released: ['রিলিজ', 'Released'],
  s_pass: ['প্রমাণ আছে', 'Proven'], s_sim: ['সিমুলেটেড পাস', 'Simulated pass'], s_stale: ['পুরোনো SHA', 'Stale SHA'], s_missing: ['নেই', 'Missing'],
  state_now: ['বর্তমান অবস্থা', 'Current state'], head: ['হেড SHA', 'Head SHA'], proofs_n: ['{n}টি প্রমাণ-সারি', '{n} proof rows'],
  tx_not_certified: ['সার্টিফাই হয়নি', 'not certified'], tx_stale_ci: ['CI পুরোনো', 'stale CI'], tx_staging_missing: ['স্টেজিং নেই', 'staging missing'], tx_integration_missing: ['ইন্টিগ্রেশন নেই', 'integration missing'],
  tx_deployment_unverified: ['ডিপ্লয় অযাচাইকৃত', 'deployment unverified'], tx_release_not_approved: ['রিলিজ অনুমোদিত নয়', 'release not approved'], tx_simulation_only: ['শুধু সিমুলেশন', 'simulation only'],
  tx_isolated_tests_missing: ['আইসোলেটেড টেস্ট নেই', 'isolated tests missing'], tx_head_not_registered: ['হেড নিবন্ধিত নয়', 'head not registered'], tx_stale_evidence: ['প্রমাণ পুরোনো', 'stale evidence'],
  trace_title: ['সিদ্ধান্ত ও পরিবর্তনের ট্রেস', 'Decision and change trace'], trace_lead: ['প্রয়োজন, ফিচার, সোর্স ফাইল, টেস্ট ও রিলিজ: অনাথ, ডুপ্লিকেট বা হারানো আইটেম ধরা পড়ে।', 'Requirement, feature, source file, test and release: orphan, duplicate or silently dropped items are caught.'],
  verdict_valid: ['বৈধ', 'valid'], verdict_invalid: ['অবৈধ', 'invalid'], violations: ['লঙ্ঘন', 'Violations'], reqs: ['প্রয়োজন', 'requirements'], built: ['তৈরি', 'built'], deferred: ['স্থগিত', 'deferred'], chains: ['সম্পূর্ণ শৃঙ্খল', 'complete chains'],
  empty_ready: ['কোনো ফিচার নিবন্ধিত নেই।', 'No features registered.'], empty_trace: ['কোনো ট্রেস-স্ন্যাপশট নেই।', 'No trace snapshots.'],
  // export
  export_lead: ['অনুমোদিত, ফিল্টার করা রিপোর্ট; হুবহু বাইটের SHA-256; সারি-সংখ্যা, ফিল্টার, কর্তা ও উৎস-সংস্করণসহ রসিদ।', 'Authorised, filtered report; SHA-256 of the exact bytes; a receipt with row count, filter, actor and source version.'],
  export_help: ['CSV সত্যিই ডাটাবেসে তৈরি হয়, আপনার ব্রাউজার আলাদাভাবে SHA-256 গণনা করে মিলিয়ে দেখে। "বদলানো বাইট যাচাই" ইচ্ছাকৃতভাবে ব্যর্থ হওয়া উচিত। সূত্র-ইনজেকশন (= + - @) সুরক্ষিত।', 'The CSV is really produced in the database and your browser independently recomputes the SHA-256 to compare. "Verify altered bytes" is expected to fail. Formula injection (= + - @) is neutralised.'],
  btn_export: ['এক্সপোর্ট তৈরি করুন', 'Create export'], f_maxrows: ['সর্বোচ্চ সারি', 'Max rows'],
  exp_receipt: ['এক্সপোর্ট রসিদ', 'Export receipt'], exp_rows: ['সারি', 'Rows'], exp_bytes: ['বাইট', 'Bytes'], exp_sha_server: ['সার্ভারের SHA-256', 'Server SHA-256'], exp_sha_browser: ['ব্রাউজারে গণনা করা SHA-256', 'Browser-computed SHA-256'],
  exp_match: ['মিলেছে', 'match'], exp_nomatch: ['মেলেনি', 'MISMATCH'], exp_unavailable: ['এই ব্রাউজারে SHA-256 অনুপলব্ধ', 'SHA-256 unavailable in this browser'],
  btn_download: ['CSV নামান', 'Download CSV'], btn_verify: ['হুবহু বাইট যাচাই', 'Verify exact bytes'], btn_verify_bad: ['বদলানো বাইট যাচাই (ব্যর্থ হওয়া উচিত)', 'Verify altered bytes (should fail)'],
  verified_ok: ['যাচাই সফল: বাইট রসিদের সঙ্গে মিলেছে।', 'Verified: the bytes match the receipt.'], verified_bad: ['প্রত্যাখ্যাত, যা প্রত্যাশিত ছিল: বদলানো বাইট রসিদের সঙ্গে মেলে না।', 'Rejected, as expected: the altered bytes do not match the receipt.'],
  preview: ['প্রিভিউ (প্রথম {n} লাইন)', 'Preview (first {n} lines)'], history: ['আগের এক্সপোর্ট রসিদ', 'Earlier export receipts'], source_version: ['উৎস-সংস্করণ', 'Source version'], issued: ['ইস্যু', 'Issued'],
  replay_note: ['পুনরাবৃত্তি: একই রসিদ', 'Replay: same receipt'],
  // errors
  err_lead: ['অপারেশনাল ত্রুটির একটি নিরাপদ প্রক্ষেপণ: গোপন তথ্য ও ব্যক্তিগত তথ্য মুছে, শুধু অনুমোদিত কোড ও বার্তা।', 'A safe projection of an operational error: secrets and personal data removed, only an allow-listed code and message.'],
  err_help: ['বোতামটি সার্ভারে পাসওয়ার্ড, JWT, ইমেইল, কানেকশন-স্ট্রিং, কার্ড-নম্বর ও স্ট্যাক-ফ্রেমসহ একটি কৃত্রিম ত্রুটি বানায়। আপনি শুধু পরিষ্কার প্রক্ষেপণ দেখবেন; কাঁচা লেখা ফেরত আসে না, জমাও হয় না। সহায়তা-অপারেটর স্বয়ংক্রিয়ভাবে অন্য ব্যবসার ত্রুটি দেখতে পায় না।', 'The button makes the server build a synthetic error containing a password, JWT, email, connection string, card number and stack frames. You only see the clean projection; the raw text is neither returned nor stored. A support operator does not automatically see another business\'s errors.'],
  btn_err: ['কৃত্রিম গোপন-তথ্যভরা ত্রুটি তৈরি করুন', 'Generate synthetic secret-laden error'],
  err_projection: ['নিরাপদ প্রক্ষেপণ', 'Safe projection'], err_code: ['ত্রুটি-কোড', 'Error code'], err_message: ['প্রকাশ্য বার্তা', 'Public message'], err_detail: ['পরিষ্কার বিবরণ', 'Scrubbed detail'],
  err_planted: ['রোপণ করা (কখনো দেখানো হয় না)', 'Planted (never shown)'], err_recent: ['সাম্প্রতিক নিরাপদ ত্রুটি', 'Recent safe errors'], empty_errors: ['কোনো রেকর্ড করা ত্রুটি নেই।', 'No recorded errors.'],
  // grants
  grants_lead: ['প্রকৃত অনুমতি তালিকা বনাম মালিক-অনুমোদিত ভিত্তি: অপ্রত্যাশিত GRANT বা শিথিল নীতি ধরা পড়ে।', 'Effective grants versus the owner-approved baseline: unexpected GRANTs or permissive policies are flagged.'],
  grants_help: ['এই পাতা PostgreSQL ক্যাটালগ শুধু পড়ে। এটি কখনো GRANT, REVOKE বা ALTER চালায় না। ভিত্তি সার্ভারে সংরক্ষিত মালিক-অনুমোদিত স্ন্যাপশট; ব্যবহারকারী ভিত্তি দিতে পারে না। ডেমো ডাটাবেসে বানানোর সময় একটি অনুমতি-বিচ্যুতি ইচ্ছে করে বসানো হয়েছে যাতে একটি পরামর্শমূলক ফলাফল দেখা যায়।', 'This page only reads the PostgreSQL catalog. It never runs GRANT, REVOKE or ALTER. The baseline is the owner-approved snapshot stored on the server; a caller cannot supply one. The demo database was built with one deliberate grant drift so that there is an advisory finding to see.'],
  baseline: ['অনুমোদিত ভিত্তি', 'Approved baseline'], btn_diff: ['ভিত্তির সঙ্গে তুলনা চালান', 'Run diff against baseline'], btn_baseline: ['বর্তমান তালিকাকে নতুন ভিত্তি হিসেবে অনুমোদন', 'Approve current catalog as new baseline'],
  btn_baseline_confirm: ['নিশ্চিত করুন: ভিত্তি বদলান (মালিকের সিদ্ধান্ত)', 'Confirm: replace baseline (owner decision)'],
  findings: ['ফলাফল', 'Findings'], advisory_label: ['পরামর্শমূলক', 'ADVISORY'], max_sev: ['সর্বোচ্চ তীব্রতা', 'Max severity'], no_findings: ['কোনো পার্থক্য নেই।', 'No differences.'],
  empty_baseline: ['কোনো অনুমোদিত ভিত্তি নেই।', 'No approved baseline.'], change: ['পরিবর্তন', 'Change'], rule: ['নিয়ম', 'Rule'],
  last_diff: ['সর্বশেষ তুলনা', 'Latest diff'], approved: ['অনুমোদিত', 'approved'],
};
const LANGS = ['bn', 'en'];
const state = { lang: 'bn', identity: 'business_owner_b1', view: 'audit', me: null, targetIdx: 0, gen: 0 };
const t = (k, vars) => {
  const e = D[k];
  if (!e) return k;
  let s = e[state.lang === 'bn' ? 0 : 1];
  if (vars) for (const [a, b] of Object.entries(vars)) s = s.replaceAll(`{${a}}`, String(b));
  return s;
};

const IDENTITIES = [
  ['business_owner_b1', 'ব্যবসার মালিক (A)', 'Business owner (A)'],
  ['business_owner_b1_second', 'দ্বিতীয় মালিক (A), স্বাধীন পর্যালোচক', 'Second owner (A), independent reviewer'],
  ['tenant_owner_t1', 'টেন্যান্ট-১ মালিক', 'Tenant 1 owner'],
  ['staff_s1', 'সাইট স্টাফ (সাইট ১)', 'Site staff (site 1)'],
  ['investor_b1', 'বিনিয়োগকারী', 'Investor'],
  ['revoked_b1', 'বাতিল সদস্য', 'Revoked member'],
  ['tenant_owner_t2', 'টেন্যান্ট-২ মালিক', 'Tenant 2 owner'],
  ['support_operator', 'সহায়তা-অপারেটর', 'Support operator'],
  ['business_owner_b2', 'অসম্পর্কিত মালিক (B)', 'Unrelated owner (B)'],
];
const VIEWS = ['audit', 'signals', 'incidents', 'readiness', 'export', 'errors', 'grants'];

// ------------------------------------------------------------------------------------------------ dom helpers
const $ = (sel, root = document) => root.querySelector(sel);
function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'text') el.textContent = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid === null || kid === undefined || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return el;
}
const chip = (kind, text) => h('span', { class: `chip chip-${kind}` }, text);
const short = (s, n = 10) => (s ? String(s).slice(0, n) : '');
const fmtTime = (iso) => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return new Intl.DateTimeFormat(state.lang === 'bn' ? 'bn-BD-u-nu-latn' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }).format(d);
};
const wClass = (pct) => `w-${Math.max(0, Math.min(100, Math.round(Number(pct) / 5) * 5))}`;
const sevChip = (sev) => chip(sev === 'high' ? 'bad' : sev === 'medium' ? 'warn' : 'info', t(`sev_${sev}`));

const api = createApiClient({ getIdentity: () => state.identity });
const target = () => state.me?.targets?.[state.targetIdx] ?? null;
const scope = () => { const x = target(); return x ? { tenant_id: x.tenant_id, business_id: x.business_id } : null; };

function stateBox(kind, title, text) {
  const icon = kind === 'denied' ? '⊘' : kind === 'loading' ? null : kind === 'error' ? '!' : '○';
  return h('div', { class: `state state-${kind}`, role: kind === 'loading' ? 'status' : (kind === 'denied' || kind === 'error') ? 'alert' : 'status' },
    icon ? h('span', { class: 'state-icon', 'aria-hidden': 'true' }, icon) : null,
    h('div', null, title ? h('p', { class: 'state-title' }, title) : null, text ? h('p', null, text) : null));
}
const loadingBox = () => stateBox('loading', null, t('loading'));
const emptyBox = (msg) => stateBox('empty', t('empty_title'), msg);
function failBox(res) {
  const msg = res.data?.message ? h('span', { lang: 'en' }, res.data.message) : null;
  if (res.status === 403) return stateBox('denied', t('denied_title'), t('denied_text'));
  if (res.status === 401) return stateBox('error', t('unauth_title'), msg);
  if (res.status === 409) return stateBox('error', t('conflict_title'), msg);
  if (res.status === 422) return stateBox('error', t('invalid_title'), msg);
  if (res.status === 0) return stateBox('error', t('network_title'), msg);
  return stateBox('error', t('error_title'), msg);
}
function viewHead(key, leadKey, helpKeys) {
  return h('div', { class: 'view-head' },
    h('h2', { class: 'view-title', id: 'view-title' }, t(`tab_${key}`)),
    h('p', { class: 'view-lead' }, t(leadKey)),
    helpKeys && helpKeys.length ? h('details', { class: 'help' }, h('summary', null, t('how_to_read')), ...helpKeys.map((k) => h('p', null, t(k)))) : null);
}
function field(label, control, id) {
  return h('div', { class: 'field' }, h('label', { for: id }, label), control);
}
function select(id, options, value, onChange) {
  const sel = h('select', { id, name: id, onchange: onChange }, options.map(([v, l]) => h('option', { value: v }, l)));
  sel.value = value ?? options[0]?.[0] ?? '';
  return sel;
}
function kv(pairs) {
  return h('dl', { class: 'kv' }, pairs.filter(Boolean).flatMap(([k, v, cls]) => [h('dt', null, k), h('dd', { class: cls || null }, v)]));
}
async function busy(btn, fn) {
  btn.disabled = true; btn.setAttribute('aria-busy', 'true');
  try { return await fn(); } finally { btn.disabled = false; btn.removeAttribute('aria-busy'); }
}

// ------------------------------------------------------------------------------------------------ view: audit
const auditFilters = { action: '', source_domain: '', from: '', to: '' };
const lastAppend = { key: null, body: null };
const PRESETS = [['order.created', 'erp.orders'], ['sale.recorded', 'pos.sales'], ['stock.count', 'stock.feed']];

async function viewAudit(alive) {
  const root = h('div', { class: 'stack' }, viewHead('audit', 'audit_lead', ['audit_help1', 'audit_help2']));
  const sc = scope();
  const statsBox = h('div', { class: 'grid-3' });
  const listBox = h('div', { 'aria-live': 'polite' });
  const filterBox = h('div');
  let lists = { actions: [], source_domains: [] };
  let chain = null;
  let lastData = null;

  const dayIso = (d, plus = 0) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + plus); return x.toISOString().replace('.000Z', 'Z'); };
  async function load() {
    listBox.replaceChildren(loadingBox());
    const res = await api.audit(sc, { action: auditFilters.action, source_domain: auditFilters.source_domain,
      from: auditFilters.from ? dayIso(auditFilters.from) : '', to: auditFilters.to ? dayIso(auditFilters.to, 1) : '', limit: 100 });
    if (!alive()) return;
    if (!res.ok) { statsBox.replaceChildren(); filterBox.replaceChildren(); listBox.replaceChildren(failBox(res)); return; }
    lists = { actions: res.data.actions, source_domains: res.data.source_domains };
    lastData = res.data;
    renderStats(res.data);
    renderFilters();
    listBox.replaceChildren(res.data.events.length === 0 ? emptyBox(t('empty_audit')) : h('ol', { class: 'ledger', 'aria-label': t('tab_audit') }, res.data.events.map(entry)));
  }
  function renderStats(d) {
    const chainChip = chain === null ? chip('quiet', t('chain_unknown')) : chain.ok ? chip('ok', t('chain_ok')) : chip('bad', t('chain_bad'));
    statsBox.replaceChildren(
      h('div', { class: 'stat' }, h('div', { class: 'stat-n' }, String(d.total_count)), h('div', { class: 'stat-l' }, t('stat_total'))),
      h('div', { class: 'stat' }, h('div', { class: 'stat-n', id: 'filtered-count' }, String(d.filtered_count)), h('div', { class: 'stat-l' }, t('stat_filtered'))),
      h('div', { class: 'stat' }, h('div', { class: 'stat-n' }, chainChip), h('div', { class: 'stat-l' }, chain ? t('checked', { n: chain.checked }) : t('stat_chain'))));
  }
  function renderFilters() {
    const opt = (arr) => [['', t('all')], ...arr.map((x) => [x, x])];
    const act = select('f-action', opt(lists.actions), auditFilters.action);
    const dom = select('f-domain', opt(lists.source_domains), auditFilters.source_domain);
    const from = h('input', { type: 'date', id: 'f-from', name: 'f-from', value: auditFilters.from });
    const to = h('input', { type: 'date', id: 'f-to', name: 'f-to', value: auditFilters.to });
    const apply = h('button', { type: 'submit', class: 'btn' }, t('apply'));
    const verify = h('button', { type: 'button', class: 'btn btn-quiet', id: 'btn-verify-chain' }, t('verify_chain'));
    verify.addEventListener('click', () => busy(verify, async () => {
      const r = await api.verifyChain(sc);
      if (!alive()) return;
      if (!r.ok) { listBox.prepend(failBox(r)); return; }
      chain = r.data;
      if (lastData) renderStats(lastData);
    }));
    const form = h('form', { class: 'card', 'aria-label': t('tab_audit') },
      h('div', { class: 'form-grid' }, field(t('f_action'), act, 'f-action'), field(t('f_domain'), dom, 'f-domain'), field(t('f_from'), from, 'f-from'), field(t('f_to'), to, 'f-to')),
      h('div', { class: 'row' }, apply, verify, h('button', { type: 'button', class: 'btn btn-quiet', onclick: () => load() }, t('refresh'))));
    form.addEventListener('submit', (ev) => {
      ev.preventDefault();
      Object.assign(auditFilters, { action: act.value, source_domain: dom.value, from: from.value, to: to.value });
      load();
    });
    filterBox.replaceChildren(form);
  }
  function entry(e) {
    const p = Object.entries(e.payload || {});
    return h('li', { class: 'entry' },
      h('span', { class: 'entry-no', title: t('seq') }, `#${String(e.stream_seq).padStart(3, '0')}`),
      h('div', { class: 'entry-main' },
        h('div', { class: 'entry-act' }, e.action),
        h('div', { class: 'entry-meta' }, h('span', null, `${e.source_domain} / ${e.source_id}`), h('span', null, fmtTime(e.event_time)),
          h('span', null, `${t('actor')}: ${e.actor_id_label ?? short(e.actor_id, 8)}`), h('span', { class: 'mono' }, `${t('receipt')} ${short(e.receipt_id, 8)}`))),
      h('details', null, h('summary', null, t('details')),
        kv([[t('payload'), p.length ? p.map(([k, v]) => `${k}=${v}`).join(', ') : '-'], [t('source_ver'), e.source_version], [t('reason'), e.reason_category],
          [t('scope_site'), e.site_id ? short(e.site_id, 8) : '-'], [t('correlation'), e.correlation_id], [t('idem_key'), e.idempotency_key],
          [t('receipt'), e.receipt_id, 'hash'], [t('digest'), e.event_digest, 'hash'], [t('prior'), e.prior_digest, 'hash']])));
  }
  function appendPanel() {
    const writable = (target()?.sites || []).filter((s) => s.can_write);
    const bizWrite = target()?.can_write === true;
    const siteOpts = [...(bizWrite ? [['', t('site_business')]] : []), ...writable.map((s) => [s.site_id, s.label])];
    const out = h('div', { role: 'status', 'aria-live': 'polite' });
    if (siteOpts.length === 0) return h('details', { class: 'card help' }, h('summary', null, t('append_title')), stateBox('denied', t('denied_title'), t('denied_text')));
    const preset = select('a-preset', PRESETS.map(([a, d]) => [a, `${a} (${d})`]), PRESETS[0][0]);
    const src = h('input', { type: 'text', id: 'a-source', name: 'a-source', value: 'ORD-DEMO-1', maxlength: '64', autocomplete: 'off' });
    const amt = h('input', { type: 'text', id: 'a-amount', name: 'a-amount', value: '125000', inputmode: 'numeric', pattern: '-?[0-9]{1,18}', autocomplete: 'off' });
    const site = select('a-site', siteOpts, siteOpts[0][0]);
    const bAppend = h('button', { type: 'button', class: 'btn', id: 'btn-append' }, t('btn_append'));
    const bReplay = h('button', { type: 'button', class: 'btn btn-quiet', id: 'btn-replay', disabled: !lastAppend.key }, t('btn_replay'));
    const bChanged = h('button', { type: 'button', class: 'btn btn-quiet', id: 'btn-changed', disabled: !lastAppend.key }, t('btn_changed'));
    const build = (amount) => { const dom = PRESETS.find((x) => x[0] === preset.value)[1];
      return { ...(site.value ? { site_id: site.value } : {}), source_domain: dom, source_id: src.value, action: preset.value, reason_category: 'operational',
        payload: { status: 'new', amount_minor: amount, currency: 'bdt', entity_ref: src.value } }; };
    const send = async (btn, key, body) => {
      const res = await busy(btn, () => api.appendEvent(sc, { ...body, idempotency_key: key }));
      if (!alive()) return;
      if (res.ok) {
        out.replaceChildren(h('div', { class: 'result result-ok' }, chip(res.data.replayed ? 'info' : 'ok', res.data.replayed ? t('res_replayed') : t('res_created')),
          kv([[t('receipt'), res.data.receipt_id, 'hash'], [t('seq'), `#${res.data.stream_seq}`], ['payload sha256', res.data.payload_sha256, 'hash'], [t('digest'), res.data.event_digest, 'hash']]),
          h('p', { class: 'muted', lang: 'en' }, res.data.note)));
        bReplay.disabled = false; bChanged.disabled = false;
        if (!res.data.replayed) load();
      } else out.replaceChildren(h('div', { class: 'result result-bad' }, failBox(res)));
    };
    bAppend.addEventListener('click', () => { const key = newKey('ui-append'); const body = build(amt.value); lastAppend.key = key; lastAppend.body = body; send(bAppend, key, body); });
    bReplay.addEventListener('click', () => send(bReplay, lastAppend.key, lastAppend.body));
    bChanged.addEventListener('click', () => {
      const body = { ...lastAppend.body, payload: { ...lastAppend.body.payload, amount_minor: String(BigInt(lastAppend.body.payload.amount_minor || '0') + 1n) } };
      send(bChanged, lastAppend.key, body);
    });
    return h('details', { class: 'card help' }, h('summary', null, t('append_title')), h('p', null, t('append_help')),
      h('div', { class: 'form-grid' }, field(t('f_preset'), preset, 'a-preset'), field(t('f_source'), src, 'a-source'), field(t('f_amount'), amt, 'a-amount'), field(t('f_site'), site, 'a-site')),
      h('div', { class: 'row' }, bAppend, bReplay, bChanged), out);
  }
  root.append(statsBox, filterBox, listBox, appendPanel());
  await load();
  return root;
}

// ------------------------------------------------------------------------------------------------ view: signals
const REASONS = { acknowledge: ['followup_required', 'under_investigation', 'known_issue'], dismiss: ['false_positive', 'expected_activity', 'duplicate_signal', 'test_activity', 'accepted_risk'] };

async function viewSignals(alive) {
  const root = h('div', { class: 'stack' }, viewHead('signals', 'signals_lead', ['signals_help']));
  const sc = scope();
  const note = h('p', { class: 'notice', role: 'note' }, t('advisory'));
  const out = h('div', { role: 'status', 'aria-live': 'polite' });
  const listBox = h('div');
  const detect = h('button', { type: 'button', class: 'btn', id: 'btn-detect' }, t('detect'));
  detect.addEventListener('click', () => busy(detect, async () => {
    const r = await api.detect(sc);
    if (!alive()) return;
    out.replaceChildren(r.ok ? h('div', { class: 'result result-ok' }, t('detected', { n: r.data.created, m: r.data.existing }), ' ', h('span', { class: 'muted', lang: 'en' }, r.data.advisory_notice)) : failBox(r));
    if (r.ok) await load();
  }));
  async function load() {
    listBox.replaceChildren(loadingBox());
    const res = await api.signals(sc);
    if (!alive()) return;
    if (!res.ok) { listBox.replaceChildren(failBox(res)); return; }
    listBox.replaceChildren(res.data.signals.length === 0 ? emptyBox(t('empty_signals')) : h('ul', { class: 'list' }, res.data.signals.map(card)));
  }
  function card(s) {
    const st = s.status;
    const result = h('div', { role: 'status', 'aria-live': 'polite' });
    const title = D[`rule_${s.rule_id}`] ? t(`rule_${s.rule_id}`) : s.rule_id;
    let review = null;
    if (st === 'open') {
      const dec = select(`dec-${s.signal_id}`, [['acknowledge', t('dec_acknowledge')], ['dismiss', t('dec_dismiss')]], 'dismiss');
      const reasonSel = h('select', { id: `rc-${s.signal_id}`, name: `rc-${s.signal_id}` });
      const fill = () => { reasonSel.replaceChildren(...REASONS[dec.value].map((c) => h('option', { value: c }, t(`rc_${c}`)))); };
      dec.addEventListener('change', fill); fill();
      const go = h('button', { type: 'button', class: 'btn btn-small' }, t('btn_review'));
      go.addEventListener('click', () => busy(go, async () => {
        const r = await api.review(s.signal_id, { decision: dec.value, reason_code: reasonSel.value, idempotency_key: newKey('ui-review') });
        if (!alive()) return;
        if (r.ok) { result.replaceChildren(h('div', { class: 'result result-ok' }, t('review_done'), ' ', h('span', { class: 'hash' }, short(r.data.receipt_id, 8)))); await load(); }
        else result.replaceChildren(failBox(r));
      }));
      review = h('div', { class: 'form-grid' }, field(t('f_decision'), dec, `dec-${s.signal_id}`), field(t('f_reason'), reasonSel, `rc-${s.signal_id}`), go);
    }
    return h('li', { class: 'item card signal', 'data-sev': s.severity, 'data-status': st },
      h('div', { class: 'item-head' }, h('strong', null, title), h('span', { class: 'chips' }, sevChip(s.severity), chip(st === 'open' ? 'warn' : 'quiet', t(`st_${st}`)), chip('info', t('advisory_label')))),
      h('p', { lang: 'en' }, s.reason),
      h('div', { class: 'row' }, h('span', { class: 'muted' }, `${t('confidence')} ${s.confidence_pct}%`), h('div', { class: 'meter', role: 'img', 'aria-label': `${t('confidence')} ${s.confidence_pct}%` }, h('span', { class: wClass(s.confidence_pct) }))),
      kv([[t('window'), s.window_start ? `${fmtTime(s.window_start)} - ${fmtTime(s.window_end)}` : '-'], [t('evidence_actors'), (s.evidence_actor_labels || []).filter(Boolean).join(', ') || '-'],
        st !== 'open' ? [t('reviewed_by'), `${s.reviewer_id_label ?? ''} (${t(`rc_${s.review_reason_code}`)})`] : null]),
      h('div', null, h('strong', null, t('evidence')),
        h('ul', { class: 'evidence' }, (s.evidence || []).map((e) => h('li', null, e.evidence_kind === 'audit_event' ? `#${e.stream_seq} ${e.action} ${short(e.event_digest, 12)}` : `${e.evidence_kind} ${e.log_id ?? e.ref ?? ''}`)))),
      review, result);
  }
  root.append(note, h('div', { class: 'row' }, detect, h('button', { type: 'button', class: 'btn btn-quiet', onclick: () => load() }, t('refresh'))), out, listBox);
  await load();
  return root;
}

// ------------------------------------------------------------------------------------------------ view: incidents
async function viewIncidents(alive) {
  const root = h('div', { class: 'stack' }, viewHead('incidents', 'inc_lead', ['inc_help']));
  const sc = scope();
  const box = h('div');
  async function load() {
    box.replaceChildren(loadingBox());
    const res = await api.incidents(sc);
    if (!alive()) return;
    if (!res.ok) { box.replaceChildren(failBox(res)); return; }
    const d = res.data;
    if (d.cases.length === 0) { box.replaceChildren(emptyBox(t('empty_incidents'))); return; }
    box.replaceChildren(...d.cases.map((c) => caseCard(c, d)), h('p', { class: 'notice notice-info', role: 'note' }, t('legal_note')));
  }
  function caseCard(c, d) {
    const m = d.manifests[c.case_ref];
    const evs = d.evidence.filter((e) => e.case_ref === c.case_ref);
    const holds = d.holds.filter((x) => x.case_ref === c.case_ref);
    return h('article', { class: 'card stack', 'aria-label': c.case_ref },
      h('div', { class: 'item-head' }, h('h3', { class: 'h3' }, `${t('case')} ${c.case_ref}`), h('span', { class: 'chips' }, sevChip(c.severity === 'critical' ? 'high' : c.severity), chip('quiet', c.category),
        m ? (m.ok ? chip('ok', `${t('manifest')}: ${t('manifest_ok')}`) : chip('bad', `${t('manifest')}: ${t('manifest_bad')}`)) : null, chip('quiet', t('items', { n: evs.length })))),
      h('strong', null, t('holds')),
      h('ul', { class: 'list' }, holds.length ? holds.map((x) => h('li', { class: 'item' }, h('div', { class: 'item-head' }, h('span', { class: 'mono' }, x.hold_ref),
        h('span', { class: 'chips' }, chip(x.in_force ? 'warn' : 'quiet', x.released ? t('hold_released') : t('hold_in_force')),
          chip(x.review_status === 'approved' ? 'ok' : 'info', x.review_status === 'approved' ? t('review_approved') : x.review_status === 'rejected' ? t('review_rejected') : t('review_pending')))),
        h('span', { class: 'muted' }, `${t('retention_until')}: ${fmtTime(x.retention_until)}`))) : [h('li', null, t('none'))]),
      h('strong', null, t('evidence_items')),
      h('ul', { class: 'list' }, evs.map((e) => evidenceItem(c, e))));
  }
  function evidenceItem(c, e) {
    const out = h('div', { role: 'status', 'aria-live': 'polite' });
    const go = h('button', { type: 'button', class: 'btn btn-warn btn-small', 'data-evidence': e.evidence_ref, disabled: e.purged }, t('btn_purge'));
    go.addEventListener('click', () => busy(go, async () => {
      const r = await api.purgeAttempt(sc, c.case_ref, { evidence_ref: e.evidence_ref, reason_code: 'retention_expiry', idempotency_key: newKey('ui-purge') });
      if (!alive()) return;
      if (r.status === 409 && r.data.outcome === 'refused') {
        out.replaceChildren(h('div', { class: 'result result-bad' }, h('strong', null, `${t('purge_refused')} (${r.data.code})`),
          kv([[t('protection'), (r.data.protection || []).join(', ')], [t('receipt'), r.data.audit_receipt_id, 'hash']])));
      } else if (r.ok) { out.replaceChildren(h('div', { class: 'result result-ok' }, t('purge_done', { o: r.data.outcome }))); await load(); }
      else out.replaceChildren(failBox(r));
    }));
    return h('li', { class: 'item' }, h('div', { class: 'item-head' }, h('span', null, h('strong', null, e.evidence_ref), ` (${e.kind})`), e.purged ? chip('bad', t('purged_mark')) : go),
      h('span', { class: 'hash' }, `sha256 ${e.sha256}`), h('span', { class: 'muted' }, `${e.byte_length} bytes, #${e.item_seq}`), out);
  }
  root.append(box);
  await load();
  return root;
}

// ------------------------------------------------------------------------------------------------ view: readiness
const LEVELS = ['proposed', 'code_built', 'isolated_test_pass', 'signed_stage_verified', 'integrated_verified', 'deployed_verified', 'released'];
const tx = (s) => { const k = `tx_${String(s).replaceAll(' ', '_')}`; return D[k] ? t(k) : s; };

async function viewReadiness(alive) {
  const root = h('div', { class: 'stack' }, viewHead('readiness', 'ready_lead', ['ready_help']));
  const sc = scope();
  const box = h('div', { class: 'stack' });
  const traceBox = h('div');
  box.append(loadingBox());
  root.append(box, h('h3', { class: 'h3' }, t('trace_title')), h('p', { class: 'muted' }, t('trace_lead')), traceBox);
  const res = await api.readiness(sc);
  if (!alive()) return root;
  if (!res.ok) { box.replaceChildren(failBox(res)); } else if (res.data.features.length === 0) { box.replaceChildren(emptyBox(t('empty_ready'))); }
  else {
    box.replaceChildren(h('p', { class: 'notice notice-info', role: 'note', lang: 'en' }, res.data.notice), ...res.data.features.map((f) => {
      const r = f.readiness;
      const sat = new Set(r.satisfied_levels); const sim = new Set(r.simulated_levels); const stale = new Map(r.stale.map((x) => [x.level, x.commit_sha]));
      const steps = LEVELS.map((lv) => {
        const s = lv === 'proposed' ? 'pass' : sat.has(lv) ? (sim.has(lv) ? 'sim' : 'pass') : stale.has(lv) ? 'stale' : 'missing';
        return h('li', { class: 'step', 'data-s': s, 'data-level': lv }, h('span', { class: 'step-name' }, t(`lv_${lv}`)), h('span', { class: 'step-state' }, t(`s_${s}`)));
      });
      return h('article', { class: 'card', 'aria-label': f.title },
        h('div', { class: 'item-head' }, h('strong', null, f.title), h('span', { class: 'chips' }, chip(r.certified ? 'ok' : 'bad', `${t('state_now')}: ${t(`lv_${r.state}`)}`))),
        h('p', { class: 'muted hash' }, `${f.feature_id} / ${t('head')}: ${short(r.current_head_sha, 12)} / ${t('proofs_n', { n: res.data.proofs.filter((p) => p.feature_id === f.feature_id).length })}`),
        h('ol', { class: 'ladder', 'aria-label': t('tab_readiness') }, steps),
        h('div', { class: 'chips' }, (r.text || []).map((x) => chip(x === 'not certified' || x.includes('missing') || x.includes('unverified') || x.includes('stale') ? 'bad' : 'warn', tx(x)))));
    }));
  }
  const tr = await api.trace(sc);
  if (!alive()) return root;
  if (!tr.ok) traceBox.replaceChildren(failBox(tr));
  else if (tr.data.snapshots.length === 0) traceBox.replaceChildren(emptyBox(t('empty_trace')));
  else traceBox.replaceChildren(h('ul', { class: 'list' }, tr.data.snapshots.map((s) => h('li', { class: 'item' },
    h('div', { class: 'item-head' }, h('strong', null, s.source_label), chip(s.verdict === 'valid' ? 'ok' : 'bad', s.verdict === 'valid' ? t('verdict_valid') : t('verdict_invalid'))),
    h('span', { class: 'muted' }, `${t('reqs')} ${s.summary.requirements}, ${t('built')} ${s.summary.built}, ${t('deferred')} ${s.summary.deferred}, ${t('chains')} ${s.summary.complete_chains}`),
    s.violations.length ? h('div', null, h('strong', null, `${t('violations')} (${s.violations.length})`), h('ul', { class: 'evidence' }, s.violations.slice(0, 6).map((v) => h('li', null, `${v.code}: ${v.subject}`)))) : null))));
  return root;
}

// ------------------------------------------------------------------------------------------------ view: export
let lastExport = null;
async function viewExport(alive) {
  const root = h('div', { class: 'stack' }, viewHead('export', 'export_lead', ['export_help']));
  const sc = scope();
  const out = h('div', { role: 'status', 'aria-live': 'polite' });
  const histBox = h('div');
  const from = h('input', { type: 'date', id: 'x-from', name: 'x-from' });
  const to = h('input', { type: 'date', id: 'x-to', name: 'x-to' });
  const act = h('input', { type: 'text', id: 'x-action', name: 'x-action', placeholder: 'order.created', autocomplete: 'off', maxlength: '64' });
  const dom = h('input', { type: 'text', id: 'x-domain', name: 'x-domain', placeholder: 'erp.orders', autocomplete: 'off', maxlength: '64' });
  const max = h('input', { type: 'number', id: 'x-max', name: 'x-max', value: '1000', min: '1', max: '10000' });
  const go = h('button', { type: 'submit', class: 'btn', id: 'btn-export' }, t('btn_export'));
  const dayIso = (d, plus = 0) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + plus); return x.toISOString().replace('.000Z', 'Z'); };
  const form = h('form', { class: 'card', 'aria-label': t('tab_export') }, h('div', { class: 'form-grid' },
    field(t('f_from'), from, 'x-from'), field(t('f_to'), to, 'x-to'), field(t('f_action'), act, 'x-action'), field(t('f_domain'), dom, 'x-domain'), field(t('f_maxrows'), max, 'x-max')),
  h('div', { class: 'row' }, go));
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    busy(go, async () => {
      out.replaceChildren(loadingBox());
      const res = await api.exportCreate(sc, { idempotency_key: newKey('ui-export'), from: from.value ? dayIso(from.value) : '', to: to.value ? dayIso(to.value, 1) : '',
        action: act.value.trim(), source_domain: dom.value.trim(), max_rows: Number(max.value) || 1000 });
      if (!alive()) return;
      if (!res.ok) { out.replaceChildren(failBox(res)); return; }
      lastExport = { receipt: res.data.receipt, csv: res.data.csv, replayed: res.data.replayed };
      await showExport(res.data);
      loadHistory();
    });
  });
  async function showExport(d) {
    const browserSha = await sha256Hex(d.csv);
    const r = d.receipt;
    const verifyOut = h('div', { role: 'status', 'aria-live': 'polite' });
    const bVerify = h('button', { type: 'button', class: 'btn btn-quiet', id: 'btn-verify-export' }, t('btn_verify'));
    const bBad = h('button', { type: 'button', class: 'btn btn-warn', id: 'btn-verify-altered' }, t('btn_verify_bad'));
    const bDl = h('button', { type: 'button', class: 'btn btn-quiet', id: 'btn-download' }, t('btn_download'));
    bVerify.addEventListener('click', () => busy(bVerify, async () => {
      const v = await api.exportVerify(r.export_receipt_id, d.csv);
      verifyOut.replaceChildren(v.ok ? h('div', { class: 'result result-ok' }, t('verified_ok')) : failBox(v));
    }));
    bBad.addEventListener('click', () => busy(bBad, async () => {
      const v = await api.exportVerify(r.export_receipt_id, `${d.csv}x`);
      verifyOut.replaceChildren(!v.ok && v.status === 422 ? h('div', { class: 'result result-ok' }, t('verified_bad'), ' ', h('span', { class: 'muted', lang: 'en' }, v.data.message)) : failBox(v));
    }));
    bDl.addEventListener('click', () => {
      const url = URL.createObjectURL(new Blob([d.csv], { type: 'text/csv;charset=utf-8' }));
      const a = h('a', { href: url, download: `gov003-audit-${short(r.byte_sha256, 8)}.csv` }); document.body.append(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
    });
    const lines = d.csv.split('\r\n').slice(0, 7).join('\n');
    out.replaceChildren(h('div', { class: 'card stack' },
      h('div', { class: 'item-head' }, h('h3', { class: 'h3' }, t('exp_receipt')), d.replayed ? chip('info', t('replay_note')) : chip('ok', t('res_created'))),
      kv([[t('exp_rows'), String(r.row_count)], [t('exp_bytes'), String(r.byte_length)], [t('exp_sha_server'), r.byte_sha256, 'hash'],
        [t('exp_sha_browser'), browserSha ?? t('exp_unavailable'), 'hash'], [t('source_version'), r.source_version], [t('issued'), fmtTime(r.issued_at)],
        [t('receipt'), r.export_receipt_id, 'hash'], ['audit receipt', r.audit_receipt_id, 'hash']]),
      h('div', { class: 'chips' }, d.sha256_matches ? chip('ok', `API SHA-256 ${t('exp_match')}`) : chip('bad', `API SHA-256 ${t('exp_nomatch')}`),
        browserSha ? (browserSha === r.byte_sha256 ? chip('ok', `${t('exp_sha_browser')}: ${t('exp_match')}`) : chip('bad', `${t('exp_sha_browser')}: ${t('exp_nomatch')}`)) : chip('quiet', t('exp_unavailable'))),
      h('strong', null, t('preview', { n: 7 })), h('pre', { class: 'csv', tabindex: '0', 'aria-label': 'CSV preview' }, lines),
      h('div', { class: 'row' }, bDl, bVerify, bBad), verifyOut));
  }
  async function loadHistory() {
    const r = await api.exportList(sc);
    if (!alive()) return;
    if (!r.ok) { histBox.replaceChildren(failBox(r)); return; }
    histBox.replaceChildren(h('h3', { class: 'h3' }, t('history')), r.data.receipts.length === 0 ? emptyBox(t('none'))
      : h('ul', { class: 'list' }, r.data.receipts.map((x) => h('li', { class: 'item' }, h('div', { class: 'item-head' }, h('span', { class: 'mono' }, short(x.export_receipt_id, 8)), chip('quiet', `${x.row_count} ${t('exp_rows')}`)),
        h('span', { class: 'hash' }, x.byte_sha256), h('span', { class: 'muted' }, `${x.source_version} / ${fmtTime(x.issued_at)}`)))));
  }
  root.append(form, out, histBox);
  await loadHistory();
  return root;
}

// ------------------------------------------------------------------------------------------------ view: safe errors
async function viewErrors(alive) {
  const root = h('div', { class: 'stack' }, viewHead('errors', 'err_lead', ['err_help']));
  const sc = scope();
  const out = h('div', { role: 'status', 'aria-live': 'polite' });
  const listBox = h('div');
  const go = h('button', { type: 'button', class: 'btn', id: 'btn-error-demo' }, t('btn_err'));
  go.addEventListener('click', () => busy(go, async () => {
    const site = (target()?.sites || []).find((s) => s.can_write)?.site_id;
    const r = await api.errorsDemo(sc, target()?.can_write ? undefined : site);
    if (!alive()) return;
    if (!r.ok) { out.replaceChildren(failBox(r)); return; }
    const p = r.data.projection;
    out.replaceChildren(h('div', { class: 'card stack' }, h('h3', { class: 'h3' }, t('err_projection')),
      kv([[t('err_code'), p.error_code], [t('err_message'), p.public_message], [t('err_detail'), p.scrubbed_detail, 'hash'], ['error id', p.error_id, 'hash']]),
      h('p', { class: 'muted' }, `${t('err_planted')}: ${r.data.planted_marker_kinds.join(', ')} (raw_text_returned: ${String(r.data.raw_text_returned)})`),
      h('p', { class: 'muted', lang: 'en' }, r.data.note)));
    await load();
  }));
  async function load() {
    const r = await api.errors(sc);
    if (!alive()) return;
    if (!r.ok) { listBox.replaceChildren(failBox(r)); return; }
    listBox.replaceChildren(h('h3', { class: 'h3' }, t('err_recent')), r.data.errors.length === 0 ? emptyBox(t('empty_errors'))
      : h('ul', { class: 'list' }, r.data.errors.map((e) => h('li', { class: 'item' }, h('div', { class: 'item-head' }, chip('bad', e.error_code), h('span', { class: 'muted' }, fmtTime(e.occurred_at))), h('span', { class: 'hash' }, e.scrubbed_detail)))));
  }
  root.append(h('div', { class: 'row' }, go), out, listBox);
  await load();
  return root;
}

// ------------------------------------------------------------------------------------------------ view: grants
async function viewGrants(alive) {
  const root = h('div', { class: 'stack' }, viewHead('grants', 'grants_lead', ['grants_help']));
  const sc = scope();
  const note = h('p', { class: 'notice', role: 'note' }, t('advisory'));
  const out = h('div', { role: 'status', 'aria-live': 'polite' });
  const box = h('div', { class: 'stack' });
  const diffBtn = h('button', { type: 'button', class: 'btn', id: 'btn-diff' }, t('btn_diff'));
  const baseBtn = h('button', { type: 'button', class: 'btn btn-quiet', id: 'btn-baseline' }, t('btn_baseline'));
  let armed = false;
  diffBtn.addEventListener('click', () => busy(diffBtn, async () => {
    const r = await api.grantsDiff(sc, newKey('ui-diff'));
    if (!alive()) return;
    out.replaceChildren(r.ok ? h('div', { class: 'result result-ok' }, `${t('findings')}: ${r.data.finding_count} / ${t('max_sev')}: ${r.data.max_severity}`) : failBox(r));
    if (r.ok) await load();
  }));
  baseBtn.addEventListener('click', () => {
    if (!armed) { armed = true; baseBtn.textContent = t('btn_baseline_confirm'); baseBtn.className = 'btn btn-warn'; return; }
    armed = false; baseBtn.textContent = t('btn_baseline'); baseBtn.className = 'btn btn-quiet';
    busy(baseBtn, async () => {
      const r = await api.grantsBaseline(sc, newKey('ui-baseline'));
      if (!alive()) return;
      out.replaceChildren(r.ok ? h('div', { class: 'result result-ok' }, `${t('baseline')} #${r.data.baseline_seq} ${t('approved')}`) : failBox(r));
      if (r.ok) await load();
    });
  });
  async function load() {
    const r = await api.grants(sc);
    if (!alive()) return;
    if (!r.ok) { box.replaceChildren(failBox(r)); diffBtn.disabled = true; baseBtn.disabled = true; return; }
    const b = r.data.baselines[0];
    const d = r.data.diffs[0];
    box.replaceChildren(
      b ? h('div', { class: 'card' }, h('strong', null, t('baseline')), kv([['#', String(b.baseline_seq)], [t('approved'), fmtTime(b.approved_at)], ['inventory sha256', b.inventory_sha256, 'hash']])) : emptyBox(t('empty_baseline')),
      d ? h('div', { class: 'card stack' }, h('div', { class: 'item-head' }, h('strong', null, t('last_diff')), h('span', { class: 'chips' }, chip('info', t('advisory_label')), (d.max_severity === 'none' ? chip('ok', d.max_severity) : sevChip(d.max_severity)), chip('quiet', `${t('findings')}: ${d.finding_count}`))),
        d.finding_count === 0 ? h('p', null, t('no_findings')) : h('ul', { class: 'list' }, d.diff.findings.map((f) => h('li', { class: 'finding' },
          h('div', { class: 'item-head' }, h('span', { class: 'hash' }, f.key), sevChip(f.severity)), h('span', { class: 'muted' }, `${t('change')}: ${f.change} / ${t('rule')}: ${f.rule}`))))) : null);
  }
  root.append(note, h('div', { class: 'row' }, diffBtn, baseBtn), out, box);
  await load();
  return root;
}

// ------------------------------------------------------------------------------------------------ shell wiring
const RENDER = { audit: viewAudit, signals: viewSignals, incidents: viewIncidents, readiness: viewReadiness, export: viewExport, errors: viewErrors, grants: viewGrants };

function applyStaticI18n() {
  document.documentElement.lang = state.lang;
  document.title = `GOV-003 ${t('title')} - DEMO / NOT LIVE`;
  for (const el of document.querySelectorAll('[data-i18n]')) { el.textContent = t(el.getAttribute('data-i18n')); el.setAttribute('lang', state.lang); }
  const sub = $('#demo-banner .demo-sub'); if (sub) sub.setAttribute('lang', state.lang);
  $('#lang-bn').setAttribute('aria-pressed', String(state.lang === 'bn'));
  $('#lang-en').setAttribute('aria-pressed', String(state.lang === 'en'));
}
function renderIdentitySelect() {
  const sel = $('#identity');
  sel.replaceChildren(...IDENTITIES.map(([id, bn, en]) => h('option', { value: id }, `${state.lang === 'bn' ? bn : en} (${id})`)));
  sel.value = state.identity;
}
function renderTargetSelect() {
  const sel = $('#target');
  const targets = state.me?.targets ?? [];
  sel.replaceChildren(...targets.map((x, i) => h('option', { value: String(i) },
    `${x.label} - ${x.can_read ? t('read') : ''}${x.can_read && x.can_write ? ' + ' : ''}${x.can_write ? t('write') : ''}${!x.can_read && !x.can_write ? t('no_access') : ''}`)));
  sel.value = String(state.targetIdx);
}
function renderWhoami() {
  const el = $('#whoami');
  el.replaceChildren(`${t('acting')}: `, h('b', null, state.me?.actor?.label ?? state.identity), ` (${t('signed_no')}) `, h('span', { class: 'chip chip-warn' }, 'DEMO / NOT LIVE'));
}
function renderTabs() {
  const tabs = $('#tabs');
  tabs.replaceChildren(...VIEWS.map((v) => h('button', { type: 'button', role: 'tab', id: `tab-${v}`, class: 'tab', 'aria-selected': String(state.view === v), 'aria-controls': 'view',
    tabindex: state.view === v ? '0' : '-1', 'data-view': v, onclick: () => setView(v) }, t(`tab_${v}`))));
  $('#view').setAttribute('aria-labelledby', `tab-${state.view}`);
}
async function renderView() {
  const gen = ++state.gen;
  const view = $('#view');
  view.setAttribute('aria-busy', 'true');
  view.replaceChildren(loadingBox());
  if (!scope()) { view.replaceChildren(stateBox('error', t('error_title'), state.me?.message || t('network_title'))); view.setAttribute('aria-busy', 'false'); return; }
  try {
    const node = await RENDER[state.view](() => gen === state.gen);
    if (gen !== state.gen) return;
    view.replaceChildren(node);
  } catch {
    if (gen === state.gen) view.replaceChildren(stateBox('error', t('error_title'), 'UI error'));
  }
  if (gen === state.gen) view.setAttribute('aria-busy', 'false');
}
function setView(v) { state.view = v; renderTabs(); renderView(); }
async function loadMe(keepTarget) {
  const res = await api.me();
  state.me = res.ok ? res.data : { targets: [], message: res.data?.message };
  if (!keepTarget || !state.me.targets[state.targetIdx]) {
    const i = state.me.targets.findIndex((x) => x.can_read); const j = state.me.targets.findIndex((x) => x.can_write);
    state.targetIdx = i >= 0 ? i : j >= 0 ? j : 0;
  }
  renderTargetSelect(); renderWhoami();
}
function setLang(l) {
  state.lang = l;
  try { localStorage.setItem('g3lang', l); } catch { /* storage may be blocked; the page works without it */ }
  applyStaticI18n(); renderIdentitySelect(); renderTargetSelect(); renderWhoami(); renderTabs(); renderView();
}
function wireTabKeys() {
  $('#tabs').addEventListener('keydown', (ev) => {
    const i = VIEWS.indexOf(state.view);
    const next = { ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1, ArrowUp: i - 1, Home: 0, End: VIEWS.length - 1 }[ev.key];
    if (next === undefined) return;
    ev.preventDefault();
    setView(VIEWS[(next + VIEWS.length) % VIEWS.length]);
    $(`#tab-${state.view}`)?.focus();
  });
}

async function init() {
  const params = new URLSearchParams(location.search);
  let stored = null; try { stored = localStorage.getItem('g3lang'); } catch { /* ignore */ }
  const lang = params.get('lang') ?? stored;
  if (LANGS.includes(lang)) state.lang = lang;
  if (IDENTITIES.some((x) => x[0] === params.get('as'))) state.identity = params.get('as');
  if (VIEWS.includes(params.get('view'))) state.view = params.get('view');
  applyStaticI18n(); renderIdentitySelect(); renderTabs(); wireTabKeys();
  $('#lang-bn').addEventListener('click', () => setLang('bn'));
  $('#lang-en').addEventListener('click', () => setLang('en'));
  $('#identity').addEventListener('change', async (ev) => { state.identity = ev.target.value; lastExport = null; await loadMe(true); renderView(); });
  $('#target').addEventListener('change', (ev) => { state.targetIdx = Number(ev.target.value); renderView(); });
  await loadMe(false);
  await renderView();
}
init();
