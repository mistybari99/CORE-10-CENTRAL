-- B-014: non-posting customer order aggregate. Adapted from A026 multi-line
-- documents and A049 scoped FKs/version lifecycle; no inventory or Money ledger.
CREATE TABLE core10.sales_orders_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint NOT NULL,
 customer_id bigint NOT NULL CHECK(customer_id>0),
 price_list_id bigint NOT NULL CHECK(price_list_id>0),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 document jsonb NOT NULL CHECK(jsonb_typeof(document)='object'),
 total numeric NOT NULL CHECK(total>=0 AND total NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','confirmed','cancelled')),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL,
 changed_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(id,tenant_id,business_id,site_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES core10.sites(id,tenant_id,business_id)
);
CREATE TABLE core10.sales_order_lines_v1 (
 order_id bigint NOT NULL,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint NOT NULL,
 line_no integer NOT NULL CHECK(line_no>0),
 item_id bigint NOT NULL CHECK(item_id>0),
 variant_id bigint CHECK(variant_id>0),
 uom_id bigint NOT NULL CHECK(uom_id>0),
 quantity numeric NOT NULL CHECK(quantity>0 AND quantity NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 unit_price numeric NOT NULL CHECK(unit_price>=0 AND unit_price NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 discount_percent numeric NOT NULL CHECK(discount_percent BETWEEN 0 AND 100),
 tax_percent numeric NOT NULL CHECK(tax_percent BETWEEN 0 AND 100),
 line_total numeric NOT NULL CHECK(line_total>=0 AND line_total NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 PRIMARY KEY(order_id,line_no),
 FOREIGN KEY(order_id,tenant_id,business_id,site_id)
  REFERENCES core10.sales_orders_v1(id,tenant_id,business_id,site_id)
);
-- Command receipts are operational idempotency records, not another audit chain.
CREATE TABLE core10.sales_order_commands_v1 (
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 order_id bigint NOT NULL,
 actor_id uuid NOT NULL,
 input jsonb NOT NULL,
 receipt jsonb NOT NULL,
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 PRIMARY KEY(business_id,request_key),
 FOREIGN KEY(order_id,tenant_id,business_id,site_id)
  REFERENCES core10.sales_orders_v1(id,tenant_id,business_id,site_id)
);
ALTER TABLE core10.sales_orders_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.sales_order_lines_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.sales_order_commands_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.sales_orders_v1 FROM PUBLIC,authenticated;
REVOKE ALL ON core10.sales_order_lines_v1 FROM PUBLIC,authenticated;
REVOKE ALL ON core10.sales_order_commands_v1 FROM PUBLIC,authenticated;
REVOKE ALL ON SEQUENCE core10.sales_orders_v1_id_seq FROM PUBLIC,authenticated;
-- API access is RPC-only, including reads; default-deny RLS has no table grants.
-- Master IDs are references, never local customer/item copies. Their semantic and
-- scope validation must pass the Master port before any header/line is persisted.
