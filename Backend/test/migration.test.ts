import { afterAll, beforeAll, expect, test } from 'bun:test'
import { Pool } from 'pg'
import { migrate } from 'drizzle-orm/node-postgres/migrator'
import { connectDatabase } from '../src/database'
import { exportSource, importSnapshot } from '../scripts/source-migration'
import { createAuth } from '../src/auth'
import { createApplication } from '../src/application'

const connection = process.env.TEST_DATABASE_URL
if (!connection) throw new Error('TEST_DATABASE_URL is required')
const admin = new Pool({ connectionString: connection, max: 1 })
const suffix = crypto.randomUUID().replaceAll('-', '')
const names = ['diald_source_' + suffix, 'diald_target_' + suffix]
const databases = names.map((name) => {
  const url = new URL(connection)
  url.pathname = '/' + name
  return connectDatabase(url.href)
})
const [source, target] = databases
const userID = '11111111-1111-4111-8111-111111111111'
const hardDeleted = '22222222-2222-4222-8222-222222222222'
beforeAll(async () => {
  for (let i = 0; i < names.length; i++) {
    await admin.query('create database ' + names[i])
    await migrate(databases[i].db, { migrationsFolder: './drizzle' })
    await databases[i].pool.query(
      "insert into recovery_lease values (1,clock_timestamp(),clock_timestamp(),'restore-fixture')"
    )
  }
  await source.pool.query(
    'create schema auth; create table auth.users(id uuid primary key, email text, encrypted_password text, raw_user_meta_data jsonb, email_confirmed_at timestamptz, created_at timestamptz, updated_at timestamptz); create table auth.identities(id uuid primary key, user_id uuid, provider text, provider_id text, identity_data jsonb, created_at timestamptz, updated_at timestamptz)'
  )
  const password = await Bun.password.hash('preserved-password-123', {
    algorithm: 'bcrypt',
    cost: 4
  })
  await source.pool.query(
    "insert into auth.users values ($1,'import@example.test',$2,'{}',now(),now(),now())",
    [userID, password]
  )
  await source.pool.query(
    "insert into auth.identities values (gen_random_uuid(),$1,'apple','original-apple-subject','{}',now(),now()), (gen_random_uuid(),$1,'google','original-google-subject','{}',now(),now())",
    [userID]
  )
  await source.pool.query(
    "insert into auth_user(id,email,name,email_verified) values($1,'import@example.test','Imported',true)",
    [userID]
  )
  await source.pool.query("select set_config('diald.user_id',$1,false)", [
    userID
  ])
  await source.pool.query(
    "insert into brew_sessions(id,owner_id,method,dose_grams,extraction_seconds) values($1,$2,'espresso',18,30), (gen_random_uuid(),$2,'v60',20,180)",
    [hardDeleted, userID]
  )
  await source.pool.query('delete from brew_sessions where id=$1', [
    hardDeleted
  ])
  await source.pool.query('update brew_sessions set deleted_at=now()')
})
afterAll(async () => {
  for (let i = 0; i < names.length; i++) {
    await databases[i].pool.end()
    await admin.query('drop database if exists ' + names[i])
  }
  await admin.end()
})
test('a source restore preserves UUID/password, tombstones and lifetime history, with a dry-run first', async () => {
  const snapshot = await exportSource(source.pool)
  expect((await importSnapshot(target.pool, snapshot)).applied).toBe(false)
  expect((await importSnapshot(target.pool, snapshot, true)).applied).toBe(true)
  const auth = createAuth(target.db, {
    baseURL: 'http://localhost:3147',
    secret: 'migration-integration-secret-123456789012345',
    powerSyncURL: 'http://localhost:8080',
    sendEmail: async () => {}
  })
  const app = createApplication({ auth, pool: target.pool })
  const signin = await app(
    new Request('http://localhost:3147/api/auth/sign-in/email', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email: 'import@example.test',
        password: 'preserved-password-123'
      })
    })
  )
  expect(signin.status).toBe(200)
  const session = await signin.json()
  expect(session.user.id).toBe(userID)
  const headers = {
    authorization: 'Bearer ' + session.token,
    'content-type': 'application/json'
  }
  const status = await app(
    new Request('http://localhost:3147/api/extractions/status', { headers })
  )
  expect((await status.json()).lifetime_count).toBe(2)
  const replay = await app(
    new Request('http://localhost:3147/api/sync/upload', {
      method: 'POST',
      headers,
      body: JSON.stringify({
        table: 'brew_sessions',
        id: hardDeleted,
        op: 'put',
        data: { method: 'espresso', dose_grams: 18, extraction_seconds: 30 }
      })
    })
  )
  expect(replay.status).toBe(422)
  const subjects = (
    await target.pool.query(
      "select provider_id,account_id from auth_account where provider_id <> 'credential' order by provider_id"
    )
  ).rows
  expect(subjects).toEqual([
    { provider_id: 'apple', account_id: 'original-apple-subject' },
    { provider_id: 'google', account_id: 'original-google-subject' }
  ])
  await expect(importSnapshot(target.pool, snapshot, true)).rejects.toThrow(
    'Target must be empty'
  )
})
test('nonempty source file storage blocks import instead of silently losing files', async () => {
  const snapshot = await exportSource(source.pool)
  await expect(
    importSnapshot(target.pool, { ...snapshot, storageObjects: 1 })
  ).rejects.toThrow('verified file migration')
})
