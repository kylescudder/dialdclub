-- Apple only returns a name when the user first authorizes the app (and after
-- reconnecting following a revocation). Fill an empty profile name atomically
-- so a later authorization can never replace a user-edited value.

create or replace function public.fill_profile_display_name(candidate text)
returns void
language sql
security invoker
set search_path = public
as $$
  update public.profiles
  set display_name = nullif(btrim(candidate), '')
  where id = auth.uid()
    and nullif(btrim(display_name), '') is null;
$$;

revoke all on function public.fill_profile_display_name(text) from public;
grant execute on function public.fill_profile_display_name(text) to authenticated;

-- Sign in with Apple does not include the name in its identity token, so leave
-- new Apple profiles empty until the native authorization response is handled.
-- Other providers retain the existing email-prefix fallback.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'username', ''),
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      nullif(new.raw_user_meta_data->>'full_name', ''),
      case
        when new.raw_app_meta_data->>'provider' = 'apple' then null
        else split_part(new.email, '@', 1)
      end
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
