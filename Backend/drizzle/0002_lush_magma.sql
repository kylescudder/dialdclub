CREATE TABLE "beans" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"name" text NOT NULL,
	"roaster" text NOT NULL,
	"origin" text,
	"process" text,
	"variety" text,
	"roast_level" text,
	"roast_date" date,
	"tasting_notes" text,
	"archived_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "beans_roast_level_check" CHECK ("beans"."roast_level" in ('light','medium_light','medium','medium_dark','dark'))
);
--> statement-breakpoint
CREATE TABLE "brew_reminders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"label" text DEFAULT 'Morning brew' NOT NULL,
	"local_time" time NOT NULL,
	"timezone" text DEFAULT 'Europe/London' NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "brew_sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"bean_id" uuid,
	"method" text NOT NULL,
	"title" text DEFAULT 'Dial-in' NOT NULL,
	"dose_grams" numeric(6, 2) NOT NULL,
	"yield_grams" numeric(6, 2),
	"water_grams" numeric(7, 2),
	"grind_setting" text,
	"water_temperature_c" numeric(4, 1),
	"extraction_seconds" integer NOT NULL,
	"rating" integer,
	"acidity" integer,
	"sweetness" integer,
	"body" integer,
	"clarity" integer,
	"notes" text,
	"brewed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "brew_sessions_method_check" CHECK ("brew_sessions"."method" in ('espresso','v60','aeropress','chemex','clever','moka','french_press','other')),
	CONSTRAINT "brew_sessions_dose_check" CHECK ("brew_sessions"."dose_grams" > 0),
	CONSTRAINT "brew_sessions_yield_check" CHECK ("brew_sessions"."yield_grams" is null or "brew_sessions"."yield_grams" >= 0),
	CONSTRAINT "brew_sessions_water_check" CHECK ("brew_sessions"."water_grams" is null or "brew_sessions"."water_grams" >= 0),
	CONSTRAINT "brew_sessions_extraction_check" CHECK ("brew_sessions"."extraction_seconds" > 0),
	CONSTRAINT "brew_sessions_rating_check" CHECK ("brew_sessions"."rating" between 1 and 5),
	CONSTRAINT "brew_sessions_acidity_check" CHECK ("brew_sessions"."acidity" between 1 and 5),
	CONSTRAINT "brew_sessions_sweetness_check" CHECK ("brew_sessions"."sweetness" between 1 and 5),
	CONSTRAINT "brew_sessions_body_check" CHECK ("brew_sessions"."body" between 1 and 5),
	CONSTRAINT "brew_sessions_clarity_check" CHECK ("brew_sessions"."clarity" between 1 and 5)
);
--> statement-breakpoint
CREATE TABLE "brew_steps" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"brew_id" uuid NOT NULL,
	"owner_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"label" text NOT NULL,
	"starts_at_seconds" integer DEFAULT 0 NOT NULL,
	"duration_seconds" integer,
	"water_grams" numeric(7, 2),
	"notes" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "device_tokens" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"apns_token" text NOT NULL,
	"device_name" text,
	"bundle_id" text NOT NULL,
	"environment" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "device_tokens_environment_check" CHECK ("device_tokens"."environment" in ('sandbox','production'))
);
--> statement-breakpoint
CREATE TABLE "extraction_creation_events" (
	"brew_session_id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "extraction_creation_quotas" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"lifetime_count" bigint DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "extraction_creation_quotas_count_check" CHECK ("extraction_creation_quotas"."lifetime_count" >= 0)
);
--> statement-breakpoint
CREATE TABLE "iap_entitlements" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"product_id" text NOT NULL,
	"original_transaction_id" text,
	"transaction_id" text,
	"bundle_id" text,
	"status" text NOT NULL,
	"expires_at" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	"environment" text,
	"signed_at" timestamp with time zone,
	"verified_at" timestamp with time zone,
	"verification_source" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "iap_entitlements_status_check" CHECK ("iap_entitlements"."status" in ('active','expired','revoked','unknown')),
	CONSTRAINT "iap_entitlements_environment_check" CHECK ("iap_entitlements"."environment" in ('Production','Sandbox')),
	CONSTRAINT "iap_entitlements_source_check" CHECK ("iap_entitlements"."verification_source" in ('device','notification'))
);
--> statement-breakpoint
CREATE TABLE "profiles" (
	"id" uuid PRIMARY KEY NOT NULL,
	"username" text,
	"display_name" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "profiles_username_unique" UNIQUE("username")
);
--> statement-breakpoint
ALTER TABLE "beans" ADD CONSTRAINT "beans_owner_id_profiles_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "brew_reminders" ADD CONSTRAINT "brew_reminders_owner_id_profiles_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "brew_sessions" ADD CONSTRAINT "brew_sessions_owner_id_profiles_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "brew_sessions" ADD CONSTRAINT "brew_sessions_bean_id_beans_id_fk" FOREIGN KEY ("bean_id") REFERENCES "public"."beans"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "brew_steps" ADD CONSTRAINT "brew_steps_brew_id_brew_sessions_id_fk" FOREIGN KEY ("brew_id") REFERENCES "public"."brew_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "brew_steps" ADD CONSTRAINT "brew_steps_owner_id_profiles_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_tokens" ADD CONSTRAINT "device_tokens_user_id_profiles_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "extraction_creation_events" ADD CONSTRAINT "extraction_creation_events_user_id_profiles_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "extraction_creation_quotas" ADD CONSTRAINT "extraction_creation_quotas_user_id_profiles_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "iap_entitlements" ADD CONSTRAINT "iap_entitlements_user_id_profiles_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "profiles" ADD CONSTRAINT "profiles_id_auth_user_id_fk" FOREIGN KEY ("id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "beans_owner_updated_idx" ON "beans" USING btree ("owner_id","updated_at");--> statement-breakpoint
CREATE INDEX "brew_sessions_owner_brewed_idx" ON "brew_sessions" USING btree ("owner_id","brewed_at");--> statement-breakpoint
CREATE UNIQUE INDEX "brew_steps_brew_position_idx" ON "brew_steps" USING btree ("brew_id","position");--> statement-breakpoint
CREATE UNIQUE INDEX "device_tokens_user_token_idx" ON "device_tokens" USING btree ("user_id","apns_token");--> statement-breakpoint
CREATE INDEX "extraction_creation_events_user_idx" ON "extraction_creation_events" USING btree ("user_id");