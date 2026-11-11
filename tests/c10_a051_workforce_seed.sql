-- C10-A051 synthetic personas (inert fixture UUIDs, NOT real Auth users). Applies after tests/c10_a018_demo_seed.sql.
-- Existing A018 personas reused: 1111 tenant owner, 2222 business owner(101), 3333 manager(101), 4444 site staff(1001),
-- 5555 investor, 6666 revoked manager, 7777 other-tenant owner, 8888 other-tenant site staff, 9999 platform operator (no membership).
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active) VALUES
 (1,102,'b1111111-1111-4111-8111-111111111111','manager',true),
 (1,102,'b2222222-2222-4222-8222-222222222222','business_owner',true),
 (2,201,'c1111111-1111-4111-8111-111111111111','business_owner',true);
-- Employee-only identities (no membership): a1 supervisor, a2 monthly staff, a3 other-site daily staff, a5 terminated staff,
-- a6 night-shift staff, c2 other-tenant employee. They gain workforce access ONLY through an owner-created employee link.
