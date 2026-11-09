-- Synthetic two-business fixture. ISOLATED CI Postgres ONLY; never run on IMG-ERP-SG.
-- Disposable test tables/functions intentionally mimic only the columns used by C10-A006.
CREATE TABLE public.org_units (id bigint PRIMARY KEY, parent_id bigint, kind text NOT NULL);
CREATE TABLE public.locations (id integer PRIMARY KEY, org_unit_id bigint);
CREATE TABLE public.entries (id uuid PRIMARY KEY,location_id integer NOT NULL);
CREATE TABLE public.release_requests (id bigint PRIMARY KEY,entry_id uuid NOT NULL);
CREATE TABLE public.entry_change_requests (id bigint PRIMARY KEY,entry_id uuid NOT NULL);
CREATE TABLE public.exceptions (id bigint PRIMARY KEY,location_id integer NOT NULL,entry_id uuid);
CREATE TABLE public.emergency_requests (id bigint PRIMARY KEY,location_id integer);
CREATE TABLE public.pay_requests (id bigint PRIMARY KEY,location_id integer);
CREATE TABLE public.wastage_requests (id uuid PRIMARY KEY,location_id integer NOT NULL);
CREATE TABLE public.item_changes (id bigint PRIMARY KEY,org_unit_id bigint);

CREATE FUNCTION public._business_of_unit123(p_unit bigint)
RETURNS bigint LANGUAGE sql STABLE AS $fn$
  WITH RECURSIVE parent_chain(id,parent_id,kind) AS (
    SELECT id,parent_id,kind FROM public.org_units WHERE id=p_unit
    UNION ALL
    SELECT o.id,o.parent_id,o.kind
      FROM public.org_units o JOIN parent_chain pc ON pc.parent_id=o.id
  )
  SELECT id FROM parent_chain WHERE kind='business' LIMIT 1;
$fn$;
CREATE FUNCTION public._business_of_loc123(p_loc integer)
RETURNS bigint LANGUAGE sql STABLE AS $fn$
  SELECT public._business_of_unit123(l.org_unit_id)
    FROM public.locations l WHERE l.id=p_loc;
$fn$;

INSERT INTO public.org_units(id,parent_id,kind) VALUES
 (10,NULL,'business'),(11,10,'branch'),(20,NULL,'business'),(21,20,'branch');
INSERT INTO public.locations(id,org_unit_id) VALUES (101,11),(102,21);
INSERT INTO public.entries(id,location_id) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',101),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',102);
INSERT INTO public.release_requests(id,entry_id) VALUES
 (1,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 (2,'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
INSERT INTO public.entry_change_requests(id,entry_id) VALUES
 (1,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
INSERT INTO public.exceptions(id,location_id,entry_id) VALUES
 (1,101,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), -- conflicting businesses
 (2,101,NULL);                                 -- local only
INSERT INTO public.emergency_requests(id,location_id) VALUES
 (1,101),(2,NULL);
INSERT INTO public.pay_requests(id,location_id) VALUES
 (1,102),(2,NULL);
INSERT INTO public.wastage_requests(id,location_id) VALUES
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',101);
INSERT INTO public.item_changes(id,org_unit_id) VALUES
 (1,11),(2,NULL);
