-- SYNTHETIC fixture mimicking observed live structure (org_units.name_bn verified via live read-only information_schema).
-- Throwaway PostgreSQL only. Never run against Supabase.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;

CREATE TABLE public.org_units (
  id bigint PRIMARY KEY, parent_id bigint REFERENCES public.org_units(id),
  kind text NOT NULL CHECK (kind IN ('group','legal_entity','business','unit')),
  name_bn text NOT NULL, active boolean NOT NULL DEFAULT true);
INSERT INTO public.org_units(id,parent_id,kind,name_bn) VALUES
 (1,NULL,'group','Group'),
 (2,1,'legal_entity','ISL'),
 (3,2,'business','SWEETS'),
 (4,1,'legal_entity','CL-P');

CREATE TABLE public.locations (
  id bigint PRIMARY KEY, name text NOT NULL, org_unit_id bigint REFERENCES public.org_units(id));
INSERT INTO public.locations(id,name,org_unit_id) VALUES
 (1,'Showroom',3),(2,'Factory',3),(3,'Misty Bari',3),(4,'Al-Cakiz',3),
 (5,'Godown',3),(6,'Loc6',3),(7,'Loc7',3),(9,'Loc9',3);

-- a few of the 136 FK-referencing tables
CREATE TABLE public.stock_moves (id bigserial PRIMARY KEY, location_id bigint NOT NULL REFERENCES public.locations(id), qty numeric);
CREATE TABLE public.sales (id bigserial PRIMARY KEY, location_id bigint NOT NULL REFERENCES public.locations(id), total numeric);
CREATE TABLE public.user_locations (user_id uuid, location_id bigint NOT NULL REFERENCES public.locations(id));
INSERT INTO public.stock_moves(location_id,qty) VALUES (1,5),(2,7),(9,1);
INSERT INTO public.sales(location_id,total) VALUES (1,100),(3,50);
INSERT INTO public.user_locations VALUES (gen_random_uuid(),1),(gen_random_uuid(),9);

-- mimic Supabase: RLS on locations + a read policy, API grants on existing tables
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY loc_read ON public.locations FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.locations, public.org_units TO authenticated;
GRANT SELECT,INSERT ON public.sales TO authenticated;
-- Supabase-style default privileges: new public tables auto-granted to API roles
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
