-- A server-owned shared cache. There are intentionally no client policies: the
-- authenticated Edge Function is the only way the iOS app reads this metadata.
create table if not exists public.ai_model_catalog (
  id text primary key check (id = 'default'),
  models jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.ai_model_catalog enable row level security;
