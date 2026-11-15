import { sql } from 'drizzle-orm'
import {
  check,
  jsonb,
  numeric,
  date,
  time,
  bigint,
  boolean,
  index,
  integer,
  uuid,
  pgTable,
  text,
  timestamp,
  uniqueIndex
} from 'drizzle-orm/pg-core'

// Separate, additive tables: auth changes never require removing auth data
// or restoring an older copy of anonymous suggestions.
export const authUser = pgTable('auth_user', {
  id: uuid('id').primaryKey(),
  name: text('name').notNull(),
  givenName: text('given_name').notNull().default(''),
  familyName: text('family_name').notNull().default(''),
  email: text('email').notNull().unique(),
  emailVerified: boolean('email_verified').notNull().default(false),
  image: text('image'),
  createdAt: timestamp('created_at', { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
})

export const authSession = pgTable(
  'auth_session',
  {
    id: text('id').primaryKey(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    token: text('token').notNull().unique(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    ipAddress: text('ip_address'),
    userAgent: text('user_agent'),
    userId: uuid('user_id')
      .notNull()
      .references(() => authUser.id, { onDelete: 'cascade' })
  },
  (table) => [index('auth_session_user_idx').on(table.userId)]
)

export const authAccount = pgTable(
  'auth_account',
  {
    id: text('id').primaryKey(),
    accountId: text('account_id').notNull(),
    providerId: text('provider_id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => authUser.id, { onDelete: 'cascade' }),
    accessToken: text('access_token'),
    refreshToken: text('refresh_token'),
    idToken: text('id_token'),
    accessTokenExpiresAt: timestamp('access_token_expires_at', {
      withTimezone: true
    }),
    refreshTokenExpiresAt: timestamp('refresh_token_expires_at', {
      withTimezone: true
    }),
    scope: text('scope'),
    password: text('password'),
    createdAt: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => [
    index('auth_account_user_idx').on(table.userId),
    uniqueIndex('auth_account_provider_idx').on(
      table.providerId,
      table.accountId
    )
  ]
)

export const authVerification = pgTable(
  'auth_verification',
  {
    id: text('id').primaryKey(),
    identifier: text('identifier').notNull(),
    value: text('value').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => [index('auth_verification_identifier_idx').on(table.identifier)]
)

export const authRateLimit = pgTable('auth_rate_limit', {
  id: text('id').primaryKey(),
  key: text('key').notNull().unique(),
  count: integer('count').notNull(),
  lastRequest: bigint('last_request', { mode: 'number' }).notNull()
})

export const authEmailLimit = pgTable('auth_email_limit', {
  key: text('key').primaryKey(),
  count: integer('count').notNull(),
  windowStartedAt: timestamp('window_started_at', {
    withTimezone: true
  }).notNull()
})

export const authJwks = pgTable('auth_jwks', {
  id: text('id').primaryKey(),
  publicKey: text('public_key').notNull(),
  privateKey: text('private_key').notNull(),
  alg: text('alg'),
  crv: text('crv'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true })
})

const dates = () => ({
  created_at: timestamp('created_at', { withTimezone: true })
    .notNull()
    .defaultNow(),
  updated_at: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow(),
  deleted_at: timestamp('deleted_at', { withTimezone: true })
})
export const profiles = pgTable('profiles', {
  id: uuid('id')
    .primaryKey()
    .references(() => authUser.id, { onDelete: 'cascade' }),
  username: text('username').unique(),
  display_name: text('display_name'),
  ...dates()
})
export const beans = pgTable(
  'beans',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    owner_id: uuid('owner_id')
      .notNull()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    roaster: text('roaster').notNull(),
    origin: text('origin'),
    process: text('process'),
    variety: text('variety'),
    roast_level: text('roast_level'),
    roast_date: date('roast_date'),
    tasting_notes: text('tasting_notes'),
    archived_at: timestamp('archived_at', { withTimezone: true }),
    ...dates()
  },
  (t) => [
    check(
      'beans_roast_level_check',
      sql`${t.roast_level} in ('light','medium_light','medium','medium_dark','dark')`
    ),
    index('beans_owner_updated_idx').on(t.owner_id, t.updated_at)
  ]
)
export const brewSessions = pgTable(
  'brew_sessions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    owner_id: uuid('owner_id')
      .notNull()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    bean_id: uuid('bean_id').references(() => beans.id, {
      onDelete: 'set null'
    }),
    method: text('method').notNull(),
    title: text('title').notNull().default('Dial-in'),
    dose_grams: numeric('dose_grams', { precision: 6, scale: 2 }).notNull(),
    yield_grams: numeric('yield_grams', { precision: 6, scale: 2 }),
    water_grams: numeric('water_grams', { precision: 7, scale: 2 }),
    grind_setting: text('grind_setting'),
    water_temperature_c: numeric('water_temperature_c', {
      precision: 4,
      scale: 1
    }),
    extraction_seconds: integer('extraction_seconds').notNull(),
    rating: integer('rating'),
    acidity: integer('acidity'),
    sweetness: integer('sweetness'),
    body: integer('body'),
    clarity: integer('clarity'),
    notes: text('notes'),
    brewed_at: timestamp('brewed_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    ...dates()
  },
  (t) => [
    check(
      'brew_sessions_method_check',
      sql`${t.method} in ('espresso','v60','aeropress','chemex','clever','moka','french_press','other')`
    ),
    check('brew_sessions_dose_check', sql`${t.dose_grams} > 0`),
    check(
      'brew_sessions_yield_check',
      sql`${t.yield_grams} is null or ${t.yield_grams} >= 0`
    ),
    check(
      'brew_sessions_water_check',
      sql`${t.water_grams} is null or ${t.water_grams} >= 0`
    ),
    check('brew_sessions_extraction_check', sql`${t.extraction_seconds} > 0`),
    ...[t.rating, t.acidity, t.sweetness, t.body, t.clarity].map((c) =>
      check('brew_sessions_' + c.name + '_check', sql`${c} between 1 and 5`)
    ),
    index('brew_sessions_owner_brewed_idx').on(t.owner_id, t.brewed_at)
  ]
)
export const brewSteps = pgTable(
  'brew_steps',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    brew_id: uuid('brew_id')
      .notNull()
      .references(() => brewSessions.id, { onDelete: 'cascade' }),
    owner_id: uuid('owner_id')
      .notNull()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    position: integer('position').notNull(),
    label: text('label').notNull(),
    starts_at_seconds: integer('starts_at_seconds').notNull().default(0),
    duration_seconds: integer('duration_seconds'),
    water_grams: numeric('water_grams', { precision: 7, scale: 2 }),
    notes: text('notes'),
    ...dates()
  },
  (t) => [uniqueIndex('brew_steps_brew_position_idx').on(t.brew_id, t.position)]
)
export const brewReminders = pgTable('brew_reminders', {
  id: uuid('id').primaryKey().defaultRandom(),
  owner_id: uuid('owner_id')
    .notNull()
    .references(() => profiles.id, { onDelete: 'cascade' }),
  label: text('label').notNull().default('Morning brew'),
  local_time: time('local_time').notNull(),
  timezone: text('timezone').notNull().default('Europe/London'),
  enabled: boolean('enabled').notNull().default(true),
  ...dates()
})
export const deviceTokens = pgTable(
  'device_tokens',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    user_id: uuid('user_id')
      .notNull()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    apns_token: text('apns_token').notNull(),
    device_name: text('device_name'),
    bundle_id: text('bundle_id').notNull(),
    environment: text('environment').notNull(),
    ...dates()
  },
  (t) => [
    uniqueIndex('device_tokens_user_token_idx').on(t.user_id, t.apns_token),
    check(
      'device_tokens_environment_check',
      sql`${t.environment} in ('sandbox','production')`
    )
  ]
)
export const extractionQuotas = pgTable(
  'extraction_creation_quotas',
  {
    user_id: uuid('user_id')
      .primaryKey()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    lifetime_count: bigint('lifetime_count', { mode: 'number' })
      .notNull()
      .default(0),
    updated_at: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (t) => [
    check(
      'extraction_creation_quotas_count_check',
      sql`${t.lifetime_count} >= 0`
    )
  ]
)
export const extractionEvents = pgTable(
  'extraction_creation_events',
  {
    brew_session_id: uuid('brew_session_id').primaryKey(),
    user_id: uuid('user_id')
      .notNull()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    created_at: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (t) => [index('extraction_creation_events_user_idx').on(t.user_id)]
)
export const iapEntitlements = pgTable(
  'iap_entitlements',
  {
    user_id: uuid('user_id')
      .primaryKey()
      .references(() => profiles.id, { onDelete: 'cascade' }),
    product_id: text('product_id').notNull(),
    original_transaction_id: text('original_transaction_id'),
    transaction_id: text('transaction_id'),
    bundle_id: text('bundle_id'),
    status: text('status').notNull(),
    expires_at: timestamp('expires_at', { withTimezone: true }),
    revoked_at: timestamp('revoked_at', { withTimezone: true }),
    environment: text('environment'),
    signed_at: timestamp('signed_at', { withTimezone: true }),
    verified_at: timestamp('verified_at', { withTimezone: true }),
    verification_source: text('verification_source'),
    updated_at: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (t) => [
    check(
      'iap_entitlements_status_check',
      sql`${t.status} in ('active','expired','revoked','unknown')`
    ),
    check(
      'iap_entitlements_environment_check',
      sql`${t.environment} in ('Production','Sandbox')`
    ),
    check(
      'iap_entitlements_source_check',
      sql`${t.verification_source} in ('device','notification')`
    )
  ]
)

// Published only by the backup verifier, never by the API runtime.
export const recoveryLease = pgTable('recovery_lease', {
  id: integer('id').primaryKey(),
  snapshotStartedAt: timestamp('snapshot_started_at', {
    withTimezone: true
  }).notNull(),
  verifiedAt: timestamp('verified_at', { withTimezone: true }).notNull(),
  snapshotID: text('snapshot_id').notNull()
})
export const notificationInbox = pgTable('notification_inbox', {
  id: text('id').primaryKey(),
  signedPayload: text('signed_payload').notNull(),
  receivedAt: timestamp('received_at', { withTimezone: true })
    .notNull()
    .defaultNow(),
  processedAt: timestamp('processed_at', { withTimezone: true })
})
export const nativeCodes = pgTable('native_codes', {
  id: text('id').primaryKey(),
  challenge: text('challenge').notNull(),
  sessionToken: text('session_token').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull()
})

export const sourceAuthArchive = pgTable('source_auth_archive', {
  id: uuid('id')
    .primaryKey()
    .references(() => authUser.id, { onDelete: 'cascade' }),
  sourceUser: jsonb('source_user').notNull(),
  sourceIdentities: jsonb('source_identities').notNull()
})
