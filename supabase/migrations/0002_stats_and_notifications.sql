create or replace function public.get_brew_stats(user_id uuid)
returns table (
  total_brews bigint,
  average_rating numeric,
  average_extraction_seconds numeric,
  favourite_method text
)
language sql
security definer
set search_path = public
as $$
  with active_brews as (
    select * from public.brew_sessions where owner_id = user_id and deleted_at is null
  ),
  method_rank as (
    select method, count(*) as count from active_brews group by method order by count desc, method asc limit 1
  )
  select
    count(*)::bigint,
    round(avg(rating), 2),
    round(avg(extraction_seconds), 1),
    (select method from method_rank)
  from active_brews;
$$;

revoke all on function public.get_brew_stats(uuid) from public;
grant execute on function public.get_brew_stats(uuid) to authenticated;

create table if not exists public.brew_reminders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  label text not null default 'Morning brew',
  local_time time not null,
  timezone text not null default 'Europe/London',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

drop trigger if exists brew_reminders_touch_updated_at on public.brew_reminders;
create trigger brew_reminders_touch_updated_at before update on public.brew_reminders for each row execute function public.touch_updated_at();

alter table public.brew_reminders enable row level security;
create policy "brew reminders owner all" on public.brew_reminders for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
