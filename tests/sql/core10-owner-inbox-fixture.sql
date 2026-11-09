-- C10-A007: ISOLATED CI fixture; never execute on live IMG-ERP-SG.
-- Run the C10-A006 synthetic schema first, then this extension.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA public TO authenticated,anon;
GRANT USAGE ON SCHEMA auth TO authenticated,anon;

CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
  AS $fn$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $fn$;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon;
CREATE TABLE public.profiles(id uuid PRIMARY KEY,status text NOT NULL);
CREATE TABLE public.user_roles(user_id uuid NOT NULL,role_code text NOT NULL);
CREATE FUNCTION public.is_owner() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = ''
  AS $fn$
    SELECT EXISTS (
      SELECT 1 FROM public.profiles p JOIN public.user_roles r ON r.user_id=p.id
      WHERE p.id=auth.uid() AND p.status='active' AND r.role_code='owner'
    );
  $fn$;

INSERT INTO public.profiles(id,status) VALUES
 ('00000000-0000-4000-8000-000000000001','active'),
 ('00000000-0000-4000-8000-000000000002','active'),
 ('00000000-0000-4000-8000-000000000003','inactive');
INSERT INTO public.user_roles(user_id,role_code) VALUES
 ('00000000-0000-4000-8000-000000000001','owner'),
 ('00000000-0000-4000-8000-000000000002','staff'),
 ('00000000-0000-4000-8000-000000000003','owner');

ALTER TABLE public.org_units ADD COLUMN status text NOT NULL DEFAULT 'active';
ALTER TABLE public.entries ADD COLUMN status text NOT NULL DEFAULT 'submitted';
ALTER TABLE public.entries ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.release_requests ADD COLUMN status text NOT NULL DEFAULT 'pending';
ALTER TABLE public.release_requests ADD COLUMN requested_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.entry_change_requests ADD COLUMN status text NOT NULL DEFAULT 'pending';
ALTER TABLE public.entry_change_requests ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.exceptions ADD COLUMN status text NOT NULL DEFAULT 'open';
ALTER TABLE public.exceptions ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.emergency_requests ADD COLUMN status text NOT NULL DEFAULT 'pending';
ALTER TABLE public.emergency_requests ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.pay_requests ADD COLUMN status text NOT NULL DEFAULT 'received';
ALTER TABLE public.pay_requests ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.wastage_requests ADD COLUMN status text NOT NULL DEFAULT 'pending';
ALTER TABLE public.wastage_requests ADD COLUMN requested_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.item_changes ADD COLUMN status text NOT NULL DEFAULT 'pending';
ALTER TABLE public.item_changes ADD COLUMN requested_at timestamptz NOT NULL DEFAULT now();

-- Approved and inactive records must never appear as pending.
INSERT INTO public.release_requests(id,entry_id,status) VALUES
 (3,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','approved');
INSERT INTO public.item_changes(id,org_unit_id,status) VALUES (3,21,'approved');
INSERT INTO public.org_units(id,parent_id,kind,status) VALUES
 (30,NULL,'business','inactive'),(31,30,'branch','active');
INSERT INTO public.locations(id,org_unit_id) VALUES (103,31);
INSERT INTO public.entries(id,location_id) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',103);
