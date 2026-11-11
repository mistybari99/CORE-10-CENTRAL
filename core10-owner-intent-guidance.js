/* C10-A052 contextual guidance catalog (single source). The SQL seed
 * internal/enterprise-sql/c10_a052_intent_guidance_seed_v1.sql is GENERATED from this file by
 * tests/c10_a052_gen_guidance.js and drift-checked in CI. Server copy is authoritative at runtime. */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_INTENT_GUIDANCE=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const g=(module_code,capability_key,c)=>({module_code,capability_key,content:c});
 const T=(en,bn)=>({en,bn});
 const GUIDANCE={
 "intent.request_box":g("intent",null,{
  title:T("Describe what you want","আপনি কী চান লিখুন"),
  what:T("Write your business rule in Bangla or English. The system matches it to a certified capability or records an engineering requirement.","বাংলা বা ইংরেজিতে ব্যবসার নিয়ম লিখুন। সিস্টেম এটিকে সার্টিফাইড সক্ষমতার সাথে মেলায় অথবা ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট হিসেবে রাখে।"),
  why:T("So you do not need to know menu names or technical settings.","যাতে মেনু বা টেকনিক্যাল সেটিংয়ের নাম জানতে না হয়।"),
  when:T("Whenever you want a threshold, approval limit or margin rule for one business.","কোনো ব্যবসার সীমা, অনুমোদন-সীমা বা মার্জিন নিয়ম চাইলে।"),
  default:T("Nothing is applied. Every request starts as an interpretation you can edit.","কিছুই প্রয়োগ হয় না। প্রতিটি অনুরোধ আগে সম্পাদনাযোগ্য ব্যাখ্যা হিসেবে শুরু হয়।"),
  exception:T("Requests for permissions, code, ledger posting or payments are refused by policy.","অনুমতি, কোড, লেজার পোস্টিং বা পেমেন্টের অনুরোধ নীতিগতভাবে প্রত্যাখ্যাত।"),
  consequence:T("Supported requests can be previewed. Unsupported ones are stored for engineering; they never run.","সমর্থিত অনুরোধ প্রিভিউ করা যায়। অসমর্থিতগুলো ইঞ্জিনিয়ারিংয়ের জন্য জমা থাকে; চলে না।"),
  data_formula_units:T("Parsed with fixed rules (no AI service). Numbers keep their units: %, kg, pcs, litre, currency.","নির্দিষ্ট নিয়মে পার্স করা হয় (কোনো এআই সার্ভিস নয়)। সংখ্যার একক বজায় থাকে: %, কেজি, পিস, লিটার, মুদ্রা।"),
  linked_report:T("History and audit panel below.","নিচের ইতিহাস ও অডিট প্যানেল।")}),
 "intent.preview_diff":g("intent",null,{
  title:T("Safe preview","নিরাপদ প্রিভিউ"),
  what:T("A dry run showing before/after values, a worked sample, the formula and what else is affected.","আগে/পরে মান, একটি নমুনা হিসাব, সূত্র এবং আর কী প্রভাবিত হবে তার ড্রাই-রান।"),
  why:T("You see the consequence before anything changes.","কিছু বদলানোর আগেই ফলাফল দেখতে পান।"),
  when:T("After interpreting and before approving.","ব্যাখ্যার পরে, অনুমোদনের আগে।"),
  default:T("Uses the capability's built-in sample numbers; you can type your own.","সক্ষমতার নিজস্ব নমুনা সংখ্যা ব্যবহার হয়; নিজের সংখ্যাও দিতে পারেন।"),
  exception:T("Blocking conflicts (for example no effective change) stop validation.","ব্লকিং দ্বন্দ্ব (যেমন কার্যকর পরিবর্তন নেই) যাচাই থামিয়ে দেয়।"),
  consequence:T("Preview writes nothing to settings or engines. If the world changes afterwards, the preview becomes stale and must be redone.","প্রিভিউ সেটিং বা ইঞ্জিনে কিছু লেখে না। পরে অবস্থা বদলালে প্রিভিউ পুরোনো হয়ে যায় এবং আবার করতে হয়।"),
  data_formula_units:T("Exact decimal arithmetic; every step is shown with units.","নির্ভুল দশমিক হিসাব; প্রতিটি ধাপ এককসহ দেখানো হয়।"),
  linked_report:T("Reports listed in the impact panel; unbuilt ones are marked NOT_BUILT.","ইমপ্যাক্ট প্যানেলের রিপোর্ট; তৈরি না হলে NOT_BUILT লেখা থাকে।")}),
 "intent.approval_publish":g("intent",null,{
  title:T("Validate, approve, publish","যাচাই, অনুমোদন, প্রকাশ"),
  what:T("Three separate steps. Only the tenant Owner can approve and publish.","তিনটি আলাদা ধাপ। শুধু টেন্যান্ট মালিক অনুমোদন ও প্রকাশ করতে পারেন।"),
  why:T("Keeps a deliberate, audited path from idea to setting.","ধারণা থেকে সেটিং পর্যন্ত সুচিন্তিত ও অডিটযোগ্য পথ বজায় রাখে।"),
  when:T("After a clean preview.","পরিষ্কার প্রিভিউয়ের পর।"),
  default:T("Business Owners may submit and preview but not publish.","ব্যবসার মালিক জমা ও প্রিভিউ করতে পারেন, প্রকাশ নয়।"),
  exception:T("A stale preview, a changed setting or a blocking conflict stops the step.","পুরোনো প্রিভিউ, বদলে যাওয়া সেটিং বা ব্লকিং দ্বন্দ্ব ধাপ থামায়।"),
  consequence:T("Publishing stores an advisory setting version. It does not post stock, money or permissions.","প্রকাশ করলে একটি পরামর্শমূলক সেটিং সংস্করণ সংরক্ষিত হয়। স্টক, টাকা বা অনুমতি পোস্ট হয় না।"),
  data_formula_units:T("Each publish creates a new immutable version with a hash.","প্রতিটি প্রকাশে হ্যাশসহ নতুন অপরিবর্তনীয় সংস্করণ তৈরি হয়।"),
  linked_report:T("History and audit panel.","ইতিহাস ও অডিট প্যানেল।")}),
 "intent.rollback":g("intent",null,{
  title:T("Rollback","রোলব্যাক"),
  what:T("Restores an earlier setting version as a new version; history is never deleted.","আগের সেটিং সংস্করণটি নতুন সংস্করণ হিসেবে ফেরায়; ইতিহাস মোছা হয় না।"),
  why:T("A wrong setting can be undone quickly and traceably.","ভুল সেটিং দ্রুত ও ট্রেসযোগ্যভাবে ফেরানো যায়।"),
  when:T("When the active version behaves badly or was published by mistake.","সক্রিয় সংস্করণ ঠিক না থাকলে বা ভুলে প্রকাশ হলে।"),
  default:T("Only the tenant Owner; you must give a reason.","শুধু টেন্যান্ট মালিক; কারণ দিতে হবে।"),
  exception:T("Fails if someone published a newer version meanwhile (stale).","ইতিমধ্যে নতুন সংস্করণ প্রকাশ হলে ব্যর্থ হয় (stale)।"),
  consequence:T("Creates version N+1 with the old values and an audit event.","পুরোনো মান নিয়ে N+1 সংস্করণ ও অডিট ইভেন্ট তৈরি হয়।"),
  data_formula_units:T("Versions are compared by hash of their parameters.","সংস্করণ প্যারামিটারের হ্যাশ দিয়ে তুলনা হয়।"),
  linked_report:T("History and audit panel.","ইতিহাস ও অডিট প্যানেল।")}),
 "intent.engineering_requirement":g("intent",null,{
  title:T("Engineering requirement","ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট"),
  what:T("A stored, structured ticket for something no certified handler can do yet.","যা এখনো কোনো সার্টিফাইড হ্যান্ডলার করতে পারে না, তার জন্য সংরক্ষিত কাঠামোবদ্ধ টিকিট।"),
  why:T("So the need is not lost and nothing pretends to work.","যাতে চাহিদা হারিয়ে না যায় এবং কিছু কাজ করার ভান না করে।"),
  when:T("Shown automatically for unsupported requests.","অসমর্থিত অনুরোধে স্বয়ংক্রিয়ভাবে দেখায়।"),
  default:T("Status NEEDS_HANDLER_BUILD (or NOT_ALLOWED_BY_POLICY for refused requests).","স্ট্যাটাস NEEDS_HANDLER_BUILD (প্রত্যাখ্যাত হলে NOT_ALLOWED_BY_POLICY)।"),
  exception:T("Policy-refused requests are never built through this path.","নীতিগতভাবে প্রত্যাখ্যাত অনুরোধ এই পথে কখনো তৈরি হয় না।"),
  consequence:T("Nothing executes. Engineers must build and certify a handler first.","কিছুই চলে না। আগে ইঞ্জিনিয়ারকে হ্যান্ডলার বানিয়ে সার্টিফাই করতে হবে।"),
  data_formula_units:T("Lists data entities and testable acceptance criteria.","ডেটা এন্টিটি ও পরীক্ষাযোগ্য গ্রহণযোগ্যতার শর্ত তালিকাভুক্ত।"),
  linked_report:T("Engineering requirements panel.","ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট প্যানেল।")}),
 "inventory.wastage_threshold":g("production","wastage_threshold",{
  title:T("Wastage threshold","অপচয় সীমা"),
  what:T("Warns when wasted quantity is a larger share of produced quantity than your limit.","নষ্ট পরিমাণ উৎপাদিত পরিমাণের তুলনায় আপনার সীমার বেশি হলে সতর্ক করে।"),
  why:T("Sweets and bakery lose margin quietly through spoilage.","মিষ্টি ও বেকারিতে নষ্ট হয়ে নীরবে লাভ কমে।"),
  when:T("Per batch, when production is recorded.","প্রতি ব্যাচে, উৎপাদন লেখার সময়।"),
  default:T("Outcome is a warning; unit is kg unless you state another.","ফলাফল সতর্কতা; অন্য একক না বললে কেজি।"),
  exception:T("Wasted quantity above produced quantity is invalid input.","উৎপাদিতের বেশি নষ্ট পরিমাণ অবৈধ ইনপুট।"),
  consequence:T("Advisory only. No stock movement or cost is posted.","শুধু পরামর্শ। কোনো স্টক মুভমেন্ট বা খরচ পোস্ট হয় না।"),
  data_formula_units:T("wastage % = wasted ÷ produced × 100. Both quantities in the same unit.","অপচয় % = নষ্ট ÷ উৎপাদিত × ১০০। দুটি পরিমাণ একই এককে।"),
  linked_report:T("Wastage report: NOT_BUILT (engineering requirement).","অপচয় রিপোর্ট: NOT_BUILT (ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট)।")}),
 "pricing.pack_discount_margin":g("costing","pack_discount_margin",{
  title:T("Pack discount margin","প্যাক ডিসকাউন্ট মার্জিন"),
  what:T("Checks the margin of a pack after discount and shows the largest discount that keeps your margin floor.","ছাড়ের পর প্যাকের মার্জিন যাচাই করে এবং মার্জিন সীমা ধরে রাখার সর্বোচ্চ ছাড় দেখায়।"),
  why:T("Paint and hardware packs of different litres need exact unit costs.","পেইন্ট ও হার্ডওয়্যারের বিভিন্ন লিটারের প্যাকে নির্ভুল একক খরচ দরকার।"),
  when:T("When setting discounts or price lists.","ছাড় বা মূল্যতালিকা ঠিক করার সময়।"),
  default:T("Warn when margin falls below the floor; currency BDT unless stated.","মার্জিন সীমার নিচে গেলে সতর্ক; উল্লেখ না থাকলে মুদ্রা BDT।"),
  exception:T("Discount of 100% or zero price is invalid.","১০০% ছাড় বা শূন্য দাম অবৈধ।"),
  consequence:T("Advisory only. No price or discount is changed.","শুধু পরামর্শ। কোনো দাম বা ছাড় বদলায় না।"),
  data_formula_units:T("net = price × (1 − d/100); cost = cost per litre × litres; margin = (net − cost) ÷ net × 100.","নিট = দাম × (১ − ছাড়/১০০); খরচ = লিটার-প্রতি খরচ × লিটার; মার্জিন = (নিট − খরচ) ÷ নিট × ১০০।"),
  linked_report:T("Margin report: NOT_BUILT.","মার্জিন রিপোর্ট: NOT_BUILT।")}),
 "inventory.low_stock_alert":g("stock","low_stock_alert",{
  title:T("Low stock alert","কম স্টক সতর্কতা"),
  what:T("Flags an item when on-hand quantity is below your number.","মজুত আপনার সংখ্যার নিচে গেলে আইটেম চিহ্নিত করে।"),
  why:T("Avoid stock-outs before they stop sales or production.","বিক্রি বা উৎপাদন থামার আগেই স্টক-আউট এড়ান।"),
  when:T("On stock checks and reorder review.","স্টক যাচাই ও রিঅর্ডার পর্যালোচনায়।"),
  default:T("Warn.","সতর্কতা।"),
  exception:T("Negative thresholds are invalid.","ঋণাত্মক সীমা অবৈধ।"),
  consequence:T("Stored through the A045 engine registry; advisory only, no purchase is created.","A045 ইঞ্জিন রেজিস্ট্রির মাধ্যমে সংরক্ষিত; শুধু পরামর্শ, ক্রয় তৈরি হয় না।"),
  data_formula_units:T("matched when on_hand < threshold, in the item's stock unit.","মজুত < সীমা হলে মেলে, আইটেমের স্টক এককে।"),
  linked_report:T("Stock position (read-only, existing).","স্টক পজিশন (শুধু পড়া, বিদ্যমান)।")}),
 "pricing.margin_floor_approval":g("costing","margin_floor_approval",{
  title:T("Margin floor approval","ন্যূনতম মার্জিনে অনুমোদন"),
  what:T("Marks a sale or order as needing approval when margin is under your floor.","মার্জিন সীমার নিচে গেলে বিক্রি বা অর্ডারে অনুমোদন দরকার বলে চিহ্নিত করে।"),
  why:T("Stops unnoticed loss-making deals.","অজান্তে লোকসানের চুক্তি আটকায়।"),
  when:T("At quotation or order entry.","কোটেশন বা অর্ডার এন্ট্রির সময়।"),
  default:T("Approval required (advisory flag).","অনুমোদন প্রয়োজন (পরামর্শমূলক ফ্ল্যাগ)।"),
  exception:T("Floor must be between 0 and 99.99 %.","সীমা ০ থেকে ৯৯.৯৯ % এর মধ্যে হতে হবে।"),
  consequence:T("The approval is not enforced yet; the flag is stored via A045.","অনুমোদন এখনো বাধ্যতামূলক নয়; ফ্ল্যাগ A045-এর মাধ্যমে সংরক্ষিত।"),
  data_formula_units:T("matched when margin % < threshold %.","মার্জিন % < সীমা % হলে মেলে।"),
  linked_report:T("Margin report: NOT_BUILT.","মার্জিন রিপোর্ট: NOT_BUILT।")}),
 "purchase.order_total_approval":g("purchase","order_total_approval",{
  title:T("Large order approval","বড় অর্ডারে অনুমোদন"),
  what:T("Flags purchase or project-materials orders at or above your amount for Owner approval.","আপনার অঙ্ক বা তার বেশি ক্রয়/প্রকল্প-মালামাল অর্ডার মালিকের অনুমোদনের জন্য চিহ্নিত করে।"),
  why:T("Construction and project buying should not exceed limits unseen.","নির্মাণ ও প্রকল্পের ক্রয় অজান্তে সীমা ছাড়াবে না।"),
  when:T("When an order is drafted.","অর্ডারের খসড়া তৈরির সময়।"),
  default:T("Approval required (advisory flag); currency BDT unless stated.","অনুমোদন প্রয়োজন (পরামর্শমূলক ফ্ল্যাগ); উল্লেখ না থাকলে মুদ্রা BDT।"),
  exception:T("Zero or negative limits are invalid.","শূন্য বা ঋণাত্মক সীমা অবৈধ।"),
  consequence:T("Nothing is posted or approved automatically. The read-only materials report is not built.","কিছু স্বয়ংক্রিয়ভাবে পোস্ট বা অনুমোদিত হয় না। শুধু-পড়া মালামাল রিপোর্ট তৈরি হয়নি।"),
  data_formula_units:T("matched when order total ≥ limit, in the stated currency.","অর্ডার মোট ≥ সীমা হলে মেলে, উল্লিখিত মুদ্রায়।"),
  linked_report:T("Project materials report: NOT_BUILT.","প্রকল্প মালামাল রিপোর্ট: NOT_BUILT।")})
 };
 return Object.freeze({GUIDANCE});
});
