-- C10-A025 rollback: removes ONLY the isolated schema. Operational tables were never touched.
drop schema if exists c10_sim cascade;
