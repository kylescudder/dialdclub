CREATE TABLE "native_codes" (
	"id" text PRIMARY KEY NOT NULL,
	"challenge" text NOT NULL,
	"session_token" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "notification_inbox" (
	"id" text PRIMARY KEY NOT NULL,
	"signed_payload" text NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"processed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "recovery_lease" (
	"id" integer PRIMARY KEY NOT NULL,
	"snapshot_started_at" timestamp with time zone NOT NULL,
	"verified_at" timestamp with time zone NOT NULL,
	"snapshot_id" text NOT NULL
);
--> statement-breakpoint
create or replace function public.require_recovery_lease() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if clock_timestamp() - transaction_timestamp() >= interval '60 seconds'
     or not exists (
       select 1 from public.recovery_lease
       where id = 1
         and snapshot_started_at > clock_timestamp() - interval '600 seconds'
         and snapshot_started_at <= clock_timestamp()
         and verified_at >= snapshot_started_at
         and verified_at <= clock_timestamp()
         and length(snapshot_id) > 0
     ) then
    raise exception using errcode = 'DX006', message = 'Recovery proof unavailable; retry later';
  end if;
end $$;
revoke all on function public.require_recovery_lease() from public;
grant execute on function public.require_recovery_lease() to diald_api;
--> statement-breakpoint
create or replace function public.guard_recoverable_mutation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_recovery_lease();
  return null;
end $$;
revoke all on function public.guard_recoverable_mutation() from public;
--> statement-breakpoint
do $$ declare t text; begin
  foreach t in array array['auth_user','auth_account','auth_session','auth_verification','auth_rate_limit','auth_email_limit','auth_jwks','profiles','beans','brew_sessions','brew_steps','brew_reminders','device_tokens','extraction_creation_quotas','extraction_creation_events','iap_entitlements','native_codes','notification_inbox'] loop
    execute format('create trigger recovery_before before insert or update or delete on public.%I for each statement execute function public.guard_recoverable_mutation()', t);
    execute format('create constraint trigger recovery_commit after insert or update or delete on public.%I deferrable initially deferred for each row execute function public.guard_recoverable_mutation()', t);
  end loop;
end $$;
--> statement-breakpoint
revoke all on public.recovery_lease from public, diald_api;
grant select, insert, update, delete on public.auth_user, public.auth_account, public.auth_session, public.auth_verification, public.auth_rate_limit, public.auth_email_limit, public.auth_jwks, public.native_codes, public.notification_inbox to diald_api;
-- The API verifies Apple signatures before invoking this narrow definer function.
grant execute on function public.record_verified_iap_entitlement(uuid,text,text,text,text,text,timestamptz,timestamptz,text,timestamptz,text) to diald_api;
--> statement-breakpoint
grant execute on function public.has_verified_supporter_entitlement(uuid) to diald_api;
--> statement-breakpoint
create function public.initialize_profile() returns trigger language plpgsql security definer set search_path = '' as $$ begin
  insert into public.profiles(id, display_name) values(new.id, nullif(new.name,'')) on conflict do nothing;
  return new;
end $$;
revoke all on function public.initialize_profile() from public;
create trigger auth_user_profile after insert on public.auth_user for each row execute function public.initialize_profile();
