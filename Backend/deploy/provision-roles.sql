-- Run once as the DBA before owner migrations. Runtime gets no admin attributes.
-- Create this role before owner migrations (which must not need CREATEROLE).
create role diald_api nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant diald_api to dialdclub_runtime;
