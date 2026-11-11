-- C10-A019 / REV-009: LEGACY-TO-CANONICAL STOCK-LOCATION CROSSWALK v1
-- DISPOSABLE POSTGRES / CI ONLY. NOT an IMG-ERP-SG migration or a public API.
-- Built separately from customized Islamia ERP. No update/trigger on public.*
-- Existing legacy PKs remain unchanged; canonical IDs are distinct.
-- ADMIN-LOADED STAGING DATA ONLY after approved backup and authenticated review.
-- Never grant DML/EXECUTE of mapping data to anon/authenticated.
CREATE TABLE c10_demo.legacy_source_locations_v1(
 source_system text NOT NULL CHECK(source_system='IMG-ERP-SG'),
 legacy_location_id integer NOT NULL CHECK(legacy_location_id>0),
 legacy_business_id bigint NOT NULL CHECK(legacy_business_id>0),
 legacy_kind text NOT NULL CHECK(legacy_kind IN ('showroom','factory','godown','warehouse','project')),
 PRIMARY KEY(source_system,legacy_location_id),
 UNIQUE(source_system,legacy_location_id,legacy_business_id,legacy_kind)
);

-- One historic business has exactly one canonical destination. The destination
-- can differ in ID, but its tenant/business lineage is enforced by composite FK.
CREATE TABLE c10_demo.legacy_business_links_v1(
 source_system text NOT NULL CHECK(source_system='IMG-ERP-SG'),
 legacy_business_id bigint NOT NULL CHECK(legacy_business_id>0),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 PRIMARY KEY(source_system,legacy_business_id),
 UNIQUE(source_system,legacy_business_id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id)
   REFERENCES c10_demo.businesses(id,tenant_id)
);

-- Structural evidence only: linking neither grants access nor moves inventory.
-- One historic location may bind once, one canonical stock location may bind once.
CREATE TABLE c10_demo.legacy_location_links_v1(
 source_system text NOT NULL CHECK(source_system='IMG-ERP-SG'),
 legacy_location_id integer NOT NULL CHECK(legacy_location_id>0),
 legacy_business_id bigint NOT NULL CHECK(legacy_business_id>0),
 legacy_kind text NOT NULL,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint NOT NULL,
 stock_location_id bigint NOT NULL,
 PRIMARY KEY(source_system,legacy_location_id),
 UNIQUE(stock_location_id),
 FOREIGN KEY(source_system,legacy_location_id,legacy_business_id,legacy_kind)
   REFERENCES c10_demo.legacy_source_locations_v1
    (source_system,legacy_location_id,legacy_business_id,legacy_kind),
 FOREIGN KEY(source_system,legacy_business_id,tenant_id,business_id)
   REFERENCES c10_demo.legacy_business_links_v1
    (source_system,legacy_business_id,tenant_id,business_id),
 FOREIGN KEY(stock_location_id,tenant_id,business_id,site_id)
   REFERENCES c10_demo.stock_locations(id,tenant_id,business_id,site_id)
);

-- Parent site type must match the historic location type; cross-business,
-- cross-tenant, duplicate, missing and changed-identity bindings fail closed.
CREATE FUNCTION c10_demo.legacy_location_link_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,c10_demo AS $$
DECLARE v_kind text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN
  RAISE EXCEPTION 'LEGACY_LOCATION_LINK_IMMUTABLE';
 END IF;
 SELECT kind INTO v_kind FROM c10_demo.sites
  WHERE id=NEW.site_id AND tenant_id=NEW.tenant_id
    AND business_id=NEW.business_id;
 IF v_kind IS NULL OR v_kind<>NEW.legacy_kind THEN
  RAISE EXCEPTION 'LEGACY_SITE_KIND_MISMATCH';
 END IF;
 RETURN NEW;
END
$$;
CREATE TRIGGER legacy_link_guard_before_write_v1
 BEFORE INSERT OR UPDATE OR DELETE ON c10_demo.legacy_location_links_v1
 FOR EACH ROW EXECUTE FUNCTION c10_demo.legacy_location_link_guard_v1();

-- No table is exposed by this module to browser-authenticated or anon roles.
-- Absence of a permissive policy ensures default deny even if future grants drift.
ALTER TABLE c10_demo.legacy_source_locations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.legacy_business_links_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.legacy_location_links_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON c10_demo.legacy_source_locations_v1,
 c10_demo.legacy_business_links_v1,c10_demo.legacy_location_links_v1
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION c10_demo.legacy_location_link_guard_v1()
 FROM PUBLIC,anon,authenticated;
