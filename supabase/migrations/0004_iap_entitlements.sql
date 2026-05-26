create table if not exists public.iap_entitlements (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  product_id text not null,
  original_transaction_id text,
  status text not null check (status in ('active', 'expired', 'revoked', 'unknown')),
  expires_at timestamptz,
  revoked_at timestamptz,
  environment text,
  updated_at timestamptz not null default now()
);

create index if not exists iap_entitlements_status_idx
  on public.iap_entitlements (status, expires_at);

drop trigger if exists iap_entitlements_touch_updated_at on public.iap_entitlements;
create trigger iap_entitlements_touch_updated_at
  before update on public.iap_entitlements
  for each row execute function public.touch_updated_at();

alter table public.iap_entitlements enable row level security;

drop policy if exists "iap_entitlements read own" on public.iap_entitlements;
create policy "iap_entitlements read own" on public.iap_entitlements
  for select using (user_id = auth.uid());
