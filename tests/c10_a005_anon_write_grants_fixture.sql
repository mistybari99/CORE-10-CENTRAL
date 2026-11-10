-- SYNTHETIC. Tables: RLS on + no anon policy (must be revoked) vs RLS on + anon INSERT policy (must keep) vs authenticated-only.
CREATE TABLE public.a5_locked(id int primary key, v text); ALTER TABLE public.a5_locked ENABLE ROW LEVEL SECURITY;
CREATE TABLE public.a5_public_form(id int primary key, v text); ALTER TABLE public.a5_public_form ENABLE ROW LEVEL SECURITY;
CREATE POLICY a5_anon_ins ON public.a5_public_form FOR INSERT TO anon WITH CHECK (true);
CREATE TABLE public.a5_auth(id int primary key, v text); ALTER TABLE public.a5_auth ENABLE ROW LEVEL SECURITY;
CREATE POLICY a5_auth_all ON public.a5_auth FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT ALL ON public.a5_locked, public.a5_public_form, public.a5_auth TO anon, authenticated;
