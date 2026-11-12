-- Stand-in stock / money / approval tables + role fixtures. The GOV-003 core owns none of these, so this
-- fixture creates synthetic ones to PROVE that risk detection, dismissal and grant review never touch them.
\set ON_ERROR_STOP on
set role c10g3_owner;
create table c10_gov003_demo.fx_stock_ledger (item_ref text primary key, qty_milli bigint not null);
create table c10_gov003_demo.fx_money_ledger (entry_id int primary key, amount_minor bigint not null);
create table c10_gov003_demo.fx_approvals (approval_id text primary key, status text not null);
insert into c10_gov003_demo.fx_stock_ledger values ('item-1', 100000), ('item-2', 5500);
insert into c10_gov003_demo.fx_money_ledger values (1, 12500), (2, -4000), (3, 777);
insert into c10_gov003_demo.fx_approvals values ('appr-77', 'pending'), ('appr-78', 'approved');
alter table c10_gov003_demo.fx_stock_ledger enable row level security;
alter table c10_gov003_demo.fx_money_ledger enable row level security;
alter table c10_gov003_demo.fx_approvals enable row level security;
reset role;
