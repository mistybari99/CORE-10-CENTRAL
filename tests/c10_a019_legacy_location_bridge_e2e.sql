\set ON_ERROR_STOP on
\echo CORE10 A019: independent legacy-to-canonical location links on disposable database

-- Four old showrooms, three factories and one godown; synthetic target IDs
-- deliberately differ from all historic source location PKs.
INSERT INTO c10_demo.sites(id,tenant_id,business_id,kind,label,request_key)
VALUES
 (1011,1,101,'showroom','Crosswalk Showroom B','bridge-site-11'),
 (1012,1,101,'showroom','Crosswalk Showroom C','bridge-site-12'),
 (1013,1,101,'showroom','Crosswalk Showroom D','bridge-site-13'),
 (1014,1,101,'factory','Crosswalk Factory B','bridge-site-14'),
 (1015,1,101,'godown','Crosswalk Godown','bridge-site-15'),
 (1016,1,101,'factory','Crosswalk Factory C','bridge-site-16');
INSERT INTO c10_demo.stock_locations(id,tenant_id,business_id,site_id,code)
VALUES
 (5011,1,101,1011,'MAIN'),
 (5012,1,101,1012,'MAIN'),
 (5013,1,101,1013,'MAIN'),
 (5014,1,101,1014,'MAIN'),
 (5015,1,101,1015,'MAIN'),
 (5016,1,101,1016,'MAIN'),
 (5020,1,101,1002,'SECOND'),
 (5021,1,101,1001,'SECOND');

INSERT INTO c10_demo.legacy_source_locations_v1
 (source_system,legacy_location_id,legacy_business_id,legacy_kind)
VALUES
 ('IMG-ERP-SG',1,3,'showroom'),
 ('IMG-ERP-SG',2,3,'showroom'),
 ('IMG-ERP-SG',3,3,'showroom'),
 ('IMG-ERP-SG',4,3,'showroom'),
 ('IMG-ERP-SG',5,3,'factory'),
 ('IMG-ERP-SG',6,3,'factory'),
 ('IMG-ERP-SG',7,3,'godown'),
 ('IMG-ERP-SG',9,3,'factory'),
 ('IMG-ERP-SG',998,3,'showroom'),
 ('IMG-ERP-SG',999,3,'showroom');

INSERT INTO c10_demo.legacy_business_links_v1
(source_system,legacy_business_id,tenant_id,business_id)
VALUES('IMG-ERP-SG',3,1,101);

INSERT INTO c10_demo.legacy_location_links_v1
 (source_system,legacy_location_id,legacy_business_id,legacy_kind,
  tenant_id,business_id,site_id,stock_location_id)
VALUES
 ('IMG-ERP-SG',1,3,'showroom',1,101,1001,5001),
 ('IMG-ERP-SG',2,3,'showroom',1,101,1011,5011),
 ('IMG-ERP-SG',3,3,'showroom',1,101,1012,5012),
 ('IMG-ERP-SG',4,3,'showroom',1,101,1013,5013),
 ('IMG-ERP-SG',5,3,'factory',1,101,1002,5002),
 ('IMG-ERP-SG',6,3,'factory',1,101,1014,5014),
 ('IMG-ERP-SG',7,3,'godown',1,101,1015,5015),
 ('IMG-ERP-SG',9,3,'factory',1,101,1016,5016);

DO $$
DECLARE v_old integer[];v_new integer[];
BEGIN
 SELECT array_agg(legacy_location_id ORDER BY legacy_location_id),
        array_agg(stock_location_id ORDER BY legacy_location_id)
 INTO v_old,v_new FROM c10_demo.legacy_location_links_v1;
 IF v_old IS DISTINCT FROM ARRAY[1,2,3,4,5,6,7,9]::integer[] THEN
  RAISE EXCEPTION 'HISTORIC_ID_INVENTORY_CHANGED';
 END IF;
 IF v_old::text = v_new::text THEN
  RAISE EXCEPTION 'IDENTITY_SPACE_NOT_SEPARATE';
 END IF;
 IF (SELECT count(*) FROM c10_demo.legacy_location_links_v1)<>8 THEN
  RAISE EXCEPTION 'UNEXPECTED_MAPPED_STOCK_LOCATION_COUNT';
 END IF;
 IF EXISTS(
    SELECT 1 FROM c10_demo.legacy_location_links_v1 l
    JOIN c10_demo.stock_locations st ON st.id=l.stock_location_id
    JOIN c10_demo.sites si ON si.id=st.site_id
    WHERE si.kind<>l.legacy_kind
       OR st.tenant_id<>l.tenant_id
       OR st.business_id<>l.business_id
       OR st.site_id<>l.site_id
 ) THEN RAISE EXCEPTION 'CROSSWALK_SCOPE_INVALID'; END IF;
END $$;

-- Negative matrix, each denied INSERT remains atomic and leaves no residue.
DO $$
BEGIN
 BEGIN
  INSERT INTO c10_demo.legacy_location_links_v1
   VALUES('IMG-ERP-SG',999,3,'showroom',1,101,1001,5001);
  RAISE EXCEPTION 'DUPLICATE_TARGET_ACCEPTED';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO c10_demo.legacy_location_links_v1
   VALUES('IMG-ERP-SG',998,3,'showroom',1,101,1002,5020);
  RAISE EXCEPTION 'SOURCE_TARGET_KIND_MISMATCH_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LEGACY_SITE_KIND_MISMATCH' THEN RAISE; END IF;
 END;
 BEGIN
  INSERT INTO c10_demo.legacy_location_links_v1
   VALUES('IMG-ERP-SG',999,3,'showroom',1,102,1003,5003);
  RAISE EXCEPTION 'CROSS_BUSINESS_ACCEPTED';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO c10_demo.legacy_location_links_v1
   VALUES('IMG-ERP-SG',999,3,'showroom',2,201,2001,6001);
  RAISE EXCEPTION 'CROSS_TENANT_ACCEPTED';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO c10_demo.legacy_location_links_v1
   VALUES('IMG-ERP-SG',998,9,'showroom',1,101,1001,5021);
  RAISE EXCEPTION 'INVENTED_SOURCE_BUSINESS_ACCEPTED';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  UPDATE c10_demo.legacy_location_links_v1
   SET stock_location_id=5011 WHERE legacy_location_id=1;
  RAISE EXCEPTION 'LEGACY_MAPPING_MUTATION_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LEGACY_LOCATION_LINK_IMMUTABLE' THEN RAISE; END IF;
 END;
 BEGIN
  DELETE FROM c10_demo.legacy_location_links_v1 WHERE legacy_location_id=1;
  RAISE EXCEPTION 'LEGACY_MAPPING_DELETION_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LEGACY_LOCATION_LINK_IMMUTABLE' THEN RAISE; END IF;
 END;
 BEGIN
  DELETE FROM c10_demo.legacy_source_locations_v1 WHERE legacy_location_id=1;
  RAISE EXCEPTION 'REFERENCED_SOURCE_DELETION_ACCEPTED';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 IF (SELECT count(*) FROM c10_demo.legacy_location_links_v1)<>8 THEN
  RAISE EXCEPTION 'FAILED_NEGATIVES_LEFT_RESIDUE'; END IF;
END $$;

-- Authenticated customers, staff, managers, owners and investors ALL have
-- zero access to staging crosswalk tables. Roles are enforced by SQL GRANT/RLS,
-- not browser flags or untrusted user_metadata.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE p text;
BEGIN
 FOREACH p IN ARRAY ARRAY[
   'c10_demo.legacy_source_locations_v1',
   'c10_demo.legacy_business_links_v1',
   'c10_demo.legacy_location_links_v1'
 ] LOOP
  IF has_table_privilege('authenticated',p,'SELECT') OR
     has_table_privilege('authenticated',p,'INSERT') OR
     has_table_privilege('authenticated',p,'UPDATE') OR
     has_table_privilege('authenticated',p,'DELETE') THEN
    RAISE EXCEPTION 'AUTHENTICATED_PERMISSION_EXPOSED:%',p;
  END IF;
  BEGIN
   EXECUTE 'SELECT count(*) FROM '||p;
   RAISE EXCEPTION 'AUTHENTICATED_READ_SUCCEEDED:%',p;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
 END LOOP;
END $$;
ROLLBACK;

DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.legacy_location_links_v1)<>8 THEN
  RAISE EXCEPTION 'AUTH_TEST_ALTERED_MAPPING'; END IF;
END $$;
\echo PASS C10-A019: legacy 8 IDs bind to 8 distinct canonical stock locations; composite FKs, kind, immutability, tenant/business negatives, and authenticated deny enforced. No production database touched.
