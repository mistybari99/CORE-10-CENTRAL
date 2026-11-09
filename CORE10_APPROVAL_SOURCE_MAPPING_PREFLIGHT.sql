-- CORE-10-CENTRAL / C10-A006 / CANONICAL APPROVAL SOURCE MAPPING PREFLIGHT v1
-- READ ONLY. Run against IMG-ERP-SG; never creates an RPC, policy, table or row.
-- This is a pre-deployment mapping gate, NOT proof of tenant isolation or approval safety.
-- Fail closed: no first-business fallback, name matching, or requester-identity guess.
-- Business identity resolves only from a recorded location -> org hierarchy
-- or a recorded org_unit_id -> org hierarchy.
-- No personal identifiers or individual request rows are returned.

WITH catalog(source) AS (
 VALUES ('entries'),('release_requests'),('entry_change_requests'),
        ('exceptions'),('emergency_requests'),('pay_requests'),
        ('wastage_requests'),('item_changes')
), sources AS (
 SELECT 'entries'::text source,'entry:'||e.id::text canonical_id,
        e.location_id primary_location,NULL::integer parent_location,
        NULL::bigint direct_unit,false parent_required FROM public.entries e
 UNION ALL
 SELECT 'release_requests','release:'||r.id::text,e.location_id,e.location_id,
        NULL::bigint,true FROM public.release_requests r
        LEFT JOIN public.entries e ON e.id=r.entry_id
 UNION ALL
 SELECT 'entry_change_requests','entry_change:'||r.id::text,e.location_id,e.location_id,
        NULL::bigint,true FROM public.entry_change_requests r
        LEFT JOIN public.entries e ON e.id=r.entry_id
 UNION ALL
 SELECT 'exceptions','exception:'||x.id::text,x.location_id,e.location_id,
        NULL::bigint,x.entry_id IS NOT NULL FROM public.exceptions x
        LEFT JOIN public.entries e ON e.id=x.entry_id
 UNION ALL
 SELECT 'emergency_requests','emergency:'||r.id::text,r.location_id,NULL::integer,
        NULL::bigint,false FROM public.emergency_requests r
 UNION ALL
 SELECT 'pay_requests','pay:'||r.id::text,r.location_id,NULL::integer,
        NULL::bigint,false FROM public.pay_requests r
 UNION ALL
 SELECT 'wastage_requests','wastage:'||r.id::text,r.location_id,NULL::integer,
        NULL::bigint,false FROM public.wastage_requests r
 UNION ALL
 SELECT 'item_changes','item_change:'||r.id::text,NULL::integer,NULL::integer,
        r.org_unit_id,false FROM public.item_changes r
), resolved AS (
 SELECT s.source,s.canonical_id,s.parent_required,s.parent_location,
        CASE WHEN s.primary_location IS NOT NULL
             THEN public._business_of_loc123(s.primary_location)
             WHEN s.direct_unit IS NOT NULL
             THEN public._business_of_unit123(s.direct_unit)
             ELSE NULL::bigint END business_id,
        CASE WHEN s.parent_location IS NOT NULL
             THEN public._business_of_loc123(s.parent_location)
             ELSE NULL::bigint END parent_business
 FROM sources s
), classified AS (
 SELECT source,canonical_id,
        CASE WHEN parent_required AND parent_location IS NULL THEN 'MISSING_PARENT'
             WHEN business_id IS NULL THEN 'UNMAPPED'
             WHEN parent_required AND parent_business IS NULL THEN 'MISSING_PARENT'
             WHEN parent_business IS NOT NULL AND parent_business <> business_id
                  THEN 'CROSS_BUSINESS_CONFLICT'
             ELSE 'MAPPED' END mapping_state
 FROM resolved
)
SELECT c.source,COUNT(x.canonical_id) total_rows,
       COUNT(x.canonical_id) FILTER (WHERE x.mapping_state='MAPPED') mapped_rows,
       COUNT(x.canonical_id) FILTER (WHERE x.mapping_state='UNMAPPED') unmapped_rows,
       COUNT(x.canonical_id) FILTER (WHERE x.mapping_state='MISSING_PARENT') missing_parent_rows,
       COUNT(x.canonical_id) FILTER (WHERE x.mapping_state='CROSS_BUSINESS_CONFLICT') conflicting_rows,
       COUNT(x.canonical_id)-COUNT(DISTINCT x.canonical_id) duplicate_ids,
       CASE WHEN COUNT(x.canonical_id)=0 THEN 'NOT_EXERCISED'
            WHEN COUNT(x.canonical_id) FILTER (WHERE x.mapping_state<>'MAPPED')>0
              OR COUNT(x.canonical_id)<>COUNT(DISTINCT x.canonical_id) THEN 'BLOCKED'
            ELSE 'MAPPING_COUNTS_PASS_ONLY' END audit_gate
FROM catalog c LEFT JOIN classified x ON x.source=c.source
GROUP BY c.source ORDER BY c.source;

-- C10-A006 synthetic fail-closed classifications. NO database writes.
WITH scenarios(name,business_id,parent_business,parent_required,parent_present,expected) AS (
 VALUES
 ('valid_location',1::bigint,NULL::bigint,false,false,'MAPPED'::text),
 ('valid_linked_parent',1::bigint,1::bigint,true,true,'MAPPED'),
 ('unmapped_source',NULL::bigint,NULL::bigint,false,false,'UNMAPPED'),
 ('missing_parent',1::bigint,NULL::bigint,true,false,'MISSING_PARENT'),
 ('missing_parent_business',1::bigint,NULL::bigint,true,true,'MISSING_PARENT'),
 ('cross_business_link',1::bigint,2::bigint,true,true,'CROSS_BUSINESS_CONFLICT'),
 ('unmapped_with_parent',NULL::bigint,1::bigint,true,true,'UNMAPPED')
), results AS (
 SELECT name,expected,
        CASE WHEN parent_required AND NOT parent_present THEN 'MISSING_PARENT'
             WHEN business_id IS NULL THEN 'UNMAPPED'
             WHEN parent_required AND parent_business IS NULL THEN 'MISSING_PARENT'
             WHEN parent_business IS NOT NULL AND parent_business<>business_id
               THEN 'CROSS_BUSINESS_CONFLICT'
             ELSE 'MAPPED' END actual
 FROM scenarios
)
SELECT name,expected,actual,(expected=actual) passed FROM results ORDER BY name;

-- Important limitations:
-- 1. A source with zero rows is NOT_EXERCISED, never "passed".
-- 2. Leave/option requests and other sources lacking authoritative business scope
--    are intentionally excluded rather than assigned to the first business.
-- 3. The synthetic scenarios check classification logic, not real RLS or API access.
-- 4. This script is not an authenticated owner inbox RPC. Do not publish approval actions.
-- 5. Before migration: stage multi-business seed data; verify read/write tenant denial,
--    anon/revoked users, grants, SECURITY DEFINER, stable IDs and status filters.
