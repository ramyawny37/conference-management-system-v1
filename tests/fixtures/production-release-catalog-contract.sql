-- Disposable CI-only contract fixture. NOT the application foundation or production migration.
-- Deliberately models the live Development catalog columns and uniqueness constraints.
CREATE SCHEMA platform;
-- Minimal public module registry required by the canonical catalog seed.
CREATE TABLE public.platform_modules (
 module_key text PRIMARY KEY,
 display_name text NOT NULL,
 status text NOT NULL DEFAULT 'active'
);
CREATE TABLE platform.roles (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 code text NOT NULL,
 domain text NOT NULL,
 name text NOT NULL,
 description text,
 scope_type text NOT NULL,
 is_system boolean NOT NULL DEFAULT true,
 is_assignable boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (domain,code)
);
CREATE TABLE platform.permissions (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 code text NOT NULL UNIQUE,
 domain text NOT NULL,
 description text,
 is_system boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'active',
 allowed_scope_mode text NOT NULL DEFAULT 'module',
 allowed_resource_type text,
 sensitive_mutation boolean NOT NULL DEFAULT false
);
CREATE TABLE platform.role_permissions (
 role_id bigint NOT NULL REFERENCES platform.roles(id),
 permission_id bigint NOT NULL REFERENCES platform.permissions(id),
 created_by bigint,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (role_id,permission_id)
);
