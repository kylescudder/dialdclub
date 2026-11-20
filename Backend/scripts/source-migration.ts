import { Pool, type PoolClient } from 'pg'
import { open, readFile } from 'node:fs/promises'
import { createHash } from 'node:crypto'

export const tables = [
  'profiles',
  'beans',
  'brew_sessions',
  'brew_steps',
  'brew_reminders',
  'device_tokens',
  'extraction_creation_quotas',
  'extraction_creation_events',
  'iap_entitlements'
] as const
export type Snapshot = {
  version: 1
  exportedAt: string
  users: Record<string, unknown>[]
  identities: Record<string, unknown>[]
  tables: Record<string, Record<string, unknown>[]>
  storageObjects: number
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']'
  if (value !== null && typeof value === 'object')
    return (
      '{' +
      Object.entries(value)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => JSON.stringify(k) + ':' + canonical(v))
        .join(',') +
      '}'
    )
  return JSON.stringify(value)
}
export const fingerprint = (value: unknown) =>
  createHash('sha256').update(canonical(value)).digest('hex')
async function rows(client: PoolClient, table: string) {
  const columns =
    table === 'extraction_creation_quotas'
      ? 'user_id, lifetime_count::text as lifetime_count, updated_at'
      : '*'
  return (
    await client.query(
      `select to_jsonb(t) as row from (select ${columns} from public.${table}) t order by to_jsonb(t)::text`
    )
  ).rows.map((r) => r.row) as Record<string, unknown>[]
}
export async function exportSource(pool: Pool): Promise<Snapshot> {
  const client = await pool.connect()
  try {
    await client.query('begin isolation level repeatable read read only')
    await client.query("set local timezone = 'UTC'")
    const users = (
      await client.query(
        'select to_jsonb(t) as row from auth.users t order by id'
      )
    ).rows.map((r) => r.row)
    const identities = (
      await client.query(
        'select to_jsonb(t) as row from auth.identities t order by id'
      )
    ).rows.map((r) => r.row)
    const data: Snapshot['tables'] = {}
    for (const table of tables) data[table] = await rows(client, table)
    const exists = (
      await client.query("select to_regclass('storage.objects') as name")
    ).rows[0].name
    const storageObjects = exists
      ? Number(
          (await client.query('select count(*) from storage.objects')).rows[0]
            .count
        )
      : 0
    const snapshot: Snapshot = {
      version: 1,
      exportedAt: new Date().toISOString(),
      users,
      identities,
      tables: data,
      storageObjects
    }
    await client.query('commit')
    return snapshot
  } catch (error) {
    await client.query('rollback')
    throw error
  } finally {
    client.release()
  }
}
async function insert(
  client: PoolClient,
  table: string,
  row: Record<string, unknown>
) {
  const columns = Object.keys(row)
  // All identifier names must exist in the actual target schema.
  const actual = new Set(
    (
      await client.query(
        "select column_name from information_schema.columns where table_schema='public' and table_name=$1",
        [table]
      )
    ).rows.map((r) => r.column_name)
  )
  if (!columns.length || columns.some((c) => !actual.has(c)))
    throw new Error('Target schema differs: ' + table)
  const quoted = columns.map((c) => '"' + c.replaceAll('"', '""') + '"')
  await client.query(
    `insert into public.${table} (${quoted.join(',')}) values (${columns.map((_, i) => '$' + (i + 1)).join(',')})`,
    columns.map((c) => row[c])
  )
}
export async function importSnapshot(
  pool: Pool,
  snapshot: Snapshot,
  apply = false
) {
  if (snapshot.version !== 1 || snapshot.storageObjects !== 0)
    throw new Error(
      'Unsupported snapshot version or nonempty object storage: a verified file migration is required before import'
    )
  if (new Set(snapshot.users.map((u) => u.id)).size !== snapshot.users.length)
    throw new Error('Duplicate source UUID')
  const client = await pool.connect()
  const domain = [...tables]
  const all = [
    'auth_user',
    'auth_account',
    'auth_session',
    'auth_verification',
    'native_codes',
    'source_auth_archive',
    ...domain
  ]
  try {
    await client.query('begin')
    await client.query("set local timezone = 'UTC'")
    await client.query('select public.require_recovery_lease()')
    // No image rollback or concurrent target traffic is safe during this operation.
    await client.query(
      `lock table ${all.map((t) => 'public.' + t).join(',')} in access exclusive mode`
    )
    for (const table of all)
      if (
        Number(
          (await client.query(`select count(*) from public.${table}`)).rows[0]
            .count
        ) !== 0
      )
        throw new Error('Target must be empty: ' + table)
    // Do not re-count history or alter source timestamps while restoring it.
    for (const table of all)
      await client.query(`alter table public.${table} disable trigger user`)
    for (const user of snapshot.users) {
      if (
        !user.email ||
        user.is_anonymous ||
        user.deleted_at ||
        (user.banned_until && new Date(String(user.banned_until)) > new Date())
      )
        throw new Error(
          'Source account requires explicit migration policy; no account was dropped'
        )
      const metadata = (user.raw_user_meta_data ?? {}) as Record<
        string,
        unknown
      >
      await insert(client, 'auth_user', {
        id: user.id,
        email: String(user.email).toLowerCase(),
        name:
          metadata.display_name ?? metadata.full_name ?? metadata.name ?? '',
        email_verified: Boolean(user.email_confirmed_at),
        created_at: user.created_at,
        updated_at: user.updated_at
      })
      await insert(client, 'source_auth_archive', {
        id: user.id,
        source_user: JSON.stringify(user),
        source_identities: JSON.stringify(
          snapshot.identities.filter((i) => i.user_id === user.id)
        )
      })
      if (user.encrypted_password) {
        if (!/^\$2[aby]\$/.test(String(user.encrypted_password)))
          throw new Error(
            'Unsupported password hash; original account needs a verified recovery path'
          )
        await insert(client, 'auth_account', {
          id: crypto.randomUUID(),
          user_id: user.id,
          provider_id: 'credential',
          account_id: user.id,
          password: user.encrypted_password
        })
      }
    }
    for (const identity of snapshot.identities) {
      if (identity.provider === 'email') continue
      if (!['apple', 'google'].includes(String(identity.provider)))
        throw new Error('Unsupported source identity provider')
      const data = identity.identity_data as Record<string, unknown>
      const subject = identity.provider_id ?? data?.sub
      if (!subject || !snapshot.users.some((u) => u.id === identity.user_id))
        throw new Error('Unbound source identity')
      await insert(client, 'auth_account', {
        id: identity.id,
        user_id: identity.user_id,
        provider_id: identity.provider,
        account_id: subject,
        created_at: identity.created_at,
        updated_at: identity.updated_at
      })
    }
    for (const table of domain) {
      const data = snapshot.tables[table]
      if (!Array.isArray(data))
        throw new Error('Missing source table: ' + table)
      for (const row of data) await insert(client, table, row)
    }
    // The ledger and monotonic count must include historical deletions.
    const invalid = await client.query(
      'select q.user_id from extraction_creation_quotas q where q.lifetime_count < (select count(*) from extraction_creation_events e where e.user_id=q.user_id) union select p.id from profiles p where not exists(select 1 from extraction_creation_quotas q where q.user_id=p.id) union select u.id from auth_user u where not exists(select 1 from profiles p where p.id=u.id)'
    )
    if (invalid.rowCount) throw new Error('Quota/ledger reconciliation failed')
    for (const table of all)
      await client.query(`alter table public.${table} enable trigger user`)
    for (const table of domain) {
      const actual = await rows(client, table)
      if (
        fingerprint(actual) !==
        fingerprint(
          [...snapshot.tables[table]].sort((a, b) =>
            canonical(a).localeCompare(canonical(b))
          )
        )
      ) {
        // Compare independently of database collation / JSON textual key order.
        if (
          fingerprint(actual.map(fingerprint).sort()) !==
          fingerprint(snapshot.tables[table].map(fingerprint).sort())
        )
          throw new Error('Full-row reconciliation failed: ' + table)
      }
    }
    await client.query('select public.require_recovery_lease()')
    await client.query(apply ? 'commit' : 'rollback')
    return {
      applied: apply,
      users: snapshot.users.length,
      identities: snapshot.identities.length,
      tables: Object.fromEntries(
        domain.map((t) => [
          t,
          {
            count: snapshot.tables[t].length,
            fingerprint: fingerprint(snapshot.tables[t].map(fingerprint).sort())
          }
        ])
      )
    }
  } catch (error) {
    await client.query('rollback')
    throw error
  } finally {
    client.release()
  }
}

if (import.meta.main) {
  const [command, filename, flag] = process.argv.slice(2)
  if (
    !filename ||
    !['export', 'import'].includes(command) ||
    !process.env.MIGRATION_DATABASE_URL
  )
    throw new Error(
      'Usage: MIGRATION_DATABASE_URL=... bun scripts/source-migration.ts export|import protected-snapshot.json [--apply]'
    )
  const pool = new Pool({
    connectionString: process.env.MIGRATION_DATABASE_URL,
    max: 1,
    statement_timeout: 55_000,
    idle_in_transaction_session_timeout: 55_000
  })
  try {
    if (command === 'export') {
      const snapshot = await exportSource(pool)
      const file = await open(filename, 'wx', 0o600)
      try {
        await file.writeFile(JSON.stringify(snapshot))
        await file.sync()
      } finally {
        await file.close()
      }
      console.log(
        JSON.stringify({
          users: snapshot.users.length,
          storageObjects: snapshot.storageObjects,
          fingerprint: fingerprint(snapshot)
        })
      )
    } else {
      const snapshot = JSON.parse(await readFile(filename, 'utf8')) as Snapshot
      if (
        flag === '--apply' &&
        process.env.EXPECTED_SNAPSHOT_SHA256 !== fingerprint(snapshot)
      )
        throw new Error(
          'EXPECTED_SNAPSHOT_SHA256 must match the reviewed source export fingerprint'
        )
      console.log(
        JSON.stringify(await importSnapshot(pool, snapshot, flag === '--apply'))
      )
    }
  } finally {
    await pool.end()
  }
}
