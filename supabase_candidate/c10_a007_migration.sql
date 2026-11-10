-- C10-A007 migration CANDIDATE: owner-only scoped inbox RPC core10_owner_inbox_v1.
-- NOT APPLIED. Files only. Requires explicit Owner go/no-go, staging with real
-- signed JWT sessions, and a backup before any live apply (see PR description).
-- The function body is byte-identical to CORE10_OWNER_INBOX_RPC_CANDIDATE.sql
-- (CI enforces this); only the grants differ: live default privileges grant
-- EXECUTE on new public functions to anon, authenticated and service_role, so
-- everything is revoked explicitly and only authenticated is granted back.
BEGIN;

CREATE OR REPLACE FUNCTION public.core10_owner_inbox_v1(
  p_business_id bigint DEFAULT NULL,
  p_limit integer DEFAULT 40
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $rpc$
DECLARE
  v_limit integer := COALESCE(p_limit,40);
  v_items jsonb;
BEGIN
  -- An authenticated database role is NOT sufficient: verify the current user
  -- against the server-owned profile and owner-role tables via is_owner().
  IF auth.uid() IS NULL OR NOT public.is_owner() THEN
    RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
  END IF;
  IF v_limit NOT BETWEEN 1 AND 40 THEN
    RAISE EXCEPTION 'bad limit' USING ERRCODE = '22023';
  END IF;
  IF p_business_id IS NOT NULL AND (
     p_business_id NOT BETWEEN 1 AND 9007199254740991
     OR NOT EXISTS (
        SELECT 1 FROM public.org_units b
        WHERE b.id = p_business_id AND b.kind = 'business'
          AND b.status = 'active'
     )
  ) THEN
    RAISE EXCEPTION 'invalid business' USING ERRCODE = '22023';
  END IF;

  -- All sources are identified by canonical, type-prefixed stable IDs.
  -- No caller-supplied role flag, no fallback to the first business.
  -- Only controlled status-to-'pending' normalization reaches the frontend.
  WITH candidates AS (
    SELECT 'entry:'||e.id::text AS id, 'entry'::text AS request_type,
           'Entry awaiting approval'::text AS title, e.created_at AS created_at,
           public._business_of_loc123(e.location_id) AS business_id
      FROM public.entries e WHERE e.status='submitted'
    UNION ALL
    SELECT 'release:'||r.id::text, 'release_request'::text,
           'Release request awaiting approval'::text, r.requested_at,
           public._business_of_loc123(e.location_id)
      FROM public.release_requests r
      JOIN public.entries e ON e.id=r.entry_id WHERE r.status='pending'
    UNION ALL
    SELECT 'entry_change:'||r.id::text, 'entry_change'::text,
           'Entry change awaiting approval'::text, r.created_at,
           public._business_of_loc123(e.location_id)
      FROM public.entry_change_requests r
      JOIN public.entries e ON e.id=r.entry_id WHERE r.status='pending'
    UNION ALL
    SELECT 'exception:'||x.id::text, 'exception'::text,
           'Exception awaiting review'::text, x.created_at,
           public._business_of_loc123(x.location_id)
      FROM public.exceptions x
      LEFT JOIN public.entries e ON e.id=x.entry_id
      WHERE x.status='open' AND (
        x.entry_id IS NULL OR (
          e.id IS NOT NULL
          AND public._business_of_loc123(x.location_id)
                = public._business_of_loc123(e.location_id)
        )
      )
    UNION ALL
    SELECT 'emergency:'||r.id::text, 'emergency_request'::text,
           'Emergency request awaiting approval'::text, r.created_at,
           public._business_of_loc123(r.location_id)
      FROM public.emergency_requests r WHERE r.status='pending'
    UNION ALL
    SELECT 'pay:'||r.id::text, 'payment_request'::text,
           'Payment request awaiting approval'::text, r.created_at,
           public._business_of_loc123(r.location_id)
      FROM public.pay_requests r WHERE r.status='received'
    UNION ALL
    SELECT 'wastage:'||r.id::text, 'wastage_request'::text,
           'Wastage request awaiting approval'::text, r.requested_at,
           public._business_of_loc123(r.location_id)
      FROM public.wastage_requests r WHERE r.status='pending'
    UNION ALL
    SELECT 'item_change:'||r.id::text, 'item_change'::text,
           'Item change awaiting approval'::text, r.requested_at,
           public._business_of_unit123(r.org_unit_id)
      FROM public.item_changes r WHERE r.status='pending'
  ), scoped AS (
    SELECT c.id,c.request_type,c.title,c.created_at,c.business_id
    FROM candidates c
    JOIN public.org_units b ON b.id=c.business_id
       AND b.kind='business' AND b.status = 'active'
    WHERE c.business_id BETWEEN 1 AND 9007199254740991
      AND (p_business_id IS NULL OR c.business_id=p_business_id)
  ), limited AS (
    SELECT * FROM scoped ORDER BY created_at DESC,id ASC LIMIT v_limit
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id',id,'business_id',business_id,'request_type',request_type,
        'title',title,'status','pending',
        'created_at',to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')
      ) ORDER BY created_at DESC,id ASC
    ), '[]'::jsonb
  ) INTO v_items FROM limited;

  RETURN jsonb_build_object(
    'certified',true,'scope','owner','business_id',p_business_id,'items',v_items
  );
END;
$rpc$;

-- Live default privileges give anon/authenticated/service_role EXECUTE on every
-- new public function, and PostgreSQL gives PUBLIC EXECUTE: remove all of it.
REVOKE ALL ON FUNCTION public.core10_owner_inbox_v1(bigint,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.core10_owner_inbox_v1(bigint,integer)
  TO authenticated;

COMMIT;
