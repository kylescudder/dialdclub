create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.beans (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  roaster text not null,
  origin text,
  process text,
  variety text,
  roast_level text check (roast_level in ('light', 'medium_light', 'medium', 'medium_dark', 'dark')),
  roast_date date,
  tasting_notes text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists beans_owner_updated_idx on public.beans (owner_id, updated_at desc) where deleted_at is null;

create table if not exists public.brew_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  bean_id uuid references public.beans(id) on delete set null,
  method text not null check (method in ('espresso', 'v60', 'aeropress', 'chemex', 'clever', 'moka', 'french_press', 'other')),
  title text not null default 'Dial-in',
  dose_grams numeric(6,2) not null check (dose_grams > 0),
  yield_grams numeric(6,2) check (yield_grams is null or yield_grams >= 0),
  water_grams numeric(7,2) check (water_grams is null or water_grams >= 0),
  grind_setting text,
  water_temperature_c numeric(4,1),
  extraction_seconds int not null check (extraction_seconds > 0),
  rating int check (rating between 1 and 5),
  acidity int check (acidity between 1 and 5),
  sweetness int check (sweetness between 1 and 5),
  body int check (body between 1 and 5),
  clarity int check (clarity between 1 and 5),
  notes text,
  brewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists brew_sessions_owner_brewed_idx on public.brew_sessions (owner_id, brewed_at desc) where deleted_at is null;

create table if not exists public.brew_steps (
  id uuid primary key default gen_random_uuid(),
  brew_id uuid not null references public.brew_sessions(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  position int not null,
  label text not null,
  starts_at_seconds int not null default 0,
  duration_seconds int,
  water_grams numeric(7,2),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (brew_id, position)
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  apns_token text not null,
  device_name text,
  bundle_id text not null,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, apns_token)
);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'username', ''),
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), nullif(new.raw_user_meta_data->>'full_name', ''), split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

do $$
declare tbl text;
begin
  foreach tbl in array array['profiles', 'beans', 'brew_sessions', 'brew_steps', 'device_tokens']
  loop
    execute format('drop trigger if exists %I_touch_updated_at on public.%I', tbl, tbl);
    execute format('create trigger %I_touch_updated_at before update on public.%I for each row execute function public.touch_updated_at()', tbl, tbl);
  end loop;
end $$;

alter table public.profiles enable row level security;
alter table public.beans enable row level security;
alter table public.brew_sessions enable row level security;
alter table public.brew_steps enable row level security;
alter table public.device_tokens enable row level security;

create policy "profiles read own" on public.profiles for select using (id = auth.uid() and deleted_at is null);
create policy "profiles update own" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
create policy "beans owner all" on public.beans for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "brew sessions owner all" on public.brew_sessions for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "brew steps owner all" on public.brew_steps for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "device tokens owner all" on public.device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());
