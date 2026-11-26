# Sweets/Bakery মডিউল বিল্ড প্ল্যান

[Final Build Blueprint v1.0](https://docs.google.com/document/d/1Ftj3uWiR0p24T2ylQkJo21ifS_tv_ymA5e-LI3IUQt0/edit) এবং [Execution Register](https://docs.google.com/spreadsheets/d/100urPYSrm8hYqAqU3xPp1nUORqfZXxXq/edit)-এর Business execution শিটের T01.01–08 অনুসরণ করুন। কাজের বর্তমান বরাদ্দ ও integration দেখতে [Coordination Board](https://docs.google.com/spreadsheets/d/1QyBpRr6rybexMwSA1ivLmn_VidrntbcOTRK4qi1c9Mc/edit) খুলুন।

শুরুর ভিত্তি S0–S2। বর্তমান integration branch-এ migration runner, scoped Auth/Control/Approval/Audit এবং Master catalog ব্যবহার করুন। Board-এ #164 ও #165 integrated এবং hosted ledger 71/max0504 হিসেবে নথিভুক্ত। প্রথম রানেই বিদ্যমান migration ও receipt মিলিয়ে নিন।

| ক্রম | মডিউল ও কাজ | গ্রহণযোগ্যতার প্রমাণ |
| --- | --- | --- |
| T01.01 | Setup wizard-এ কারখানা, গুদাম ও শোরুম পরিকল্পনা। এরপর entity/site/location ID, recipe revision, lot, kg→g, pack, shelf life ও label profile যাচাই। | একই profile দিয়ে authenticated rerun-এ একই setup ও versioned receipt। |
| T01.02 | কর্মী, site scope, delegation ও অনুমোদন। | scope বদল ও grant প্রত্যাহারের পরে পুরোনো অধিকার দিয়ে action প্রত্যাখ্যান। |
| T01.03 | ক্রয়াদেশ থেকে QC-গৃহীত lot, তারপর supplier invoice matching। | ১০০ অর্ডার ও ৮০ গৃহীত হলে ১০০-এর invoice-এ ২০ disputed। Retry-তে duplicate liability শূন্য। |
| T01.04 | অনুমোদিত recipe দিয়ে batch, yield, waste, FEFO ও showroom transfer। | raw lot থেকে finished lot ও dispatch/receipt পর্যন্ত পরিমাণ মেলে। |
| T01.05 | POS invoice, payment ও bank settlement। | প্রতিটি receipt মূল invoice-এ যুক্ত, journal balanced এবং bank/MFS মেলে। |
| T01.06 | return, refund ও reversal। | মূল দামে ও মূল receipt ধরে অনুমোদিত adjustment একবারই হয়। |
| T01.07 | দিনের discrepancy এবং period close। | stock, WIP, AP/AR, bank ও GL মেলে, close অনুমোদিত। |
| T01.08 | ব্যবসার স্বীকৃতি। | ১৬ persona, বাংলা/ইংরেজি, 390/1440 px, signed receipts ও Owner sign-off। |

প্রথম কোড পরিবর্তন T01.01-এর site planning অংশ। Business Creation → Review ও export-এ quick mode-এর default showroom এবং advanced mode-এর নির্বাচিত সাইট থেকে coverage দেখায়। কারখানা বা গুদাম বাকি থাকলেও draft export করা যায়। এই হিসাব planned site kinds থেকে আসে। বাস্তব সাইটের পরিচয় ও signed provisioning আলাদা পরীক্ষায় যাচাই করতে হবে।

পরবর্তী নয়টি template-এর নিজস্ব T02.01–T10.08 সারিতে একই shared engines ব্যবহার করুন। প্রতিটির workflow, policy ও evidence সংশ্লিষ্ট register row থেকে নিন।
