CREATE TABLE "source_auth_archive" (
	"id" uuid PRIMARY KEY NOT NULL,
	"source_user" jsonb NOT NULL,
	"source_identities" jsonb NOT NULL
);
--> statement-breakpoint
revoke all on public.source_auth_archive from public, diald_api;
create trigger recovery_before before insert or update or delete on public.source_auth_archive for each statement execute function public.guard_recoverable_mutation();
create constraint trigger recovery_commit after insert or update or delete on public.source_auth_archive deferrable initially deferred for each row execute function public.guard_recoverable_mutation();
