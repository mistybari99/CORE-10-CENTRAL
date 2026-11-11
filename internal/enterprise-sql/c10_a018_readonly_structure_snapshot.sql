-- CORE 10 | C10-A018 | READ-ONLY STRUCTURE SNAPSHOT
-- Snapshot source: current IMG-ERP-SG; output contains structural IDs only.
-- No names, staff data, finance, raw UUIDs, or actual location codes.
-- All legacy PK/FK IDs remain EXACT to support compatibility testing.
-- Use manually with an authorized SELECT-only connection; no migration or DB write.
-- A stored snapshot goes stale. Its CI result NEVER certifies today's production.
WITH client_labels AS (
 SELECT client_id,
        'client_' || ROW_NUMBER() OVER (ORDER BY client_id)::text AS pseudonym
 FROM (SELECT DISTINCT client_id
       FROM public.org_units
       WHERE client_id IS NOT NULL) q
), snapshot AS (
 SELECT jsonb_build_object(
   'schema_version', 1,
   'captured_at_utc', to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
                            'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
   'source_project', 'IMG-ERP-SG',
   'privacy_note', 'No business names, account info, raw client UUIDs, or unmasked location codes; structural fixture only.',
   'org_units', (
     SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id',o.id::text,
       'parent_id',o.parent_id::text,
       'kind',o.kind,
       'template_code',o.template_code,
       'client_id',cl.pseudonym
     ) ORDER BY o.id),'[]'::jsonb)
     FROM public.org_units o
     LEFT JOIN client_labels cl ON cl.client_id=o.client_id
   ),
   'locations', (
     SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id',l.id,
       'code',CASE WHEN l.code IS NULL THEN NULL
                   WHEN btrim(l.code)='' THEN ''
                   ELSE 'loc_'||l.id::text END,
       'kind',l.kind,
       'org_unit_id',l.org_unit_id::text
     ) ORDER BY l.id),'[]'::jsonb)
     FROM public.locations l
   ),
   'business_profiles', (
     SELECT coalesce(jsonb_agg(jsonb_build_object(
       'org_unit_id',bp.org_unit_id::text
     ) ORDER BY bp.org_unit_id),'[]'::jsonb)
     FROM public.business_profiles bp
   ),
   'business_templates', (
     SELECT coalesce(jsonb_agg(jsonb_build_object(
       'code',bt.code,'status',bt.status
     ) ORDER BY bt.code),'[]'::jsonb)
     FROM public.business_templates bt
   )
 ) AS doc
)
SELECT doc::text AS sanitized_structure_snapshot FROM snapshot;
