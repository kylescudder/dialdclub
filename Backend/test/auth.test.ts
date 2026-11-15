import { afterAll, beforeAll, expect, test } from 'bun:test'
import { migrate } from 'drizzle-orm/node-postgres/migrator'
import { connectDatabase } from '../src/database'
import { createAuth } from '../src/auth'

const url = process.env.TEST_DATABASE_URL
if (!url)
  throw new Error(
    'TEST_DATABASE_URL must point to a disposable PostgreSQL database'
  )
const { db, pool } = connectDatabase(url)
const sent: { email: string; url: string }[] = []
const auth = createAuth(db, {
  baseURL: 'http://localhost:3147',
  secret: 'diald-local-integration-test-secret-123456789',
  powerSyncURL: 'http://localhost:8080',
  sendEmail: async (email: string, _kind: string, url: string) => {
    sent.push({ email, url })
  }
})

beforeAll(async () => {
  await migrate(db, { migrationsFolder: './drizzle' })
  await pool.query(
    "insert into recovery_lease values (1, clock_timestamp(), clock_timestamp(), 'test-snapshot') on conflict (id) do update set snapshot_started_at = excluded.snapshot_started_at, verified_at = excluded.verified_at"
  )
  await pool.query(
    'truncate auth_user, auth_session, auth_account, auth_verification, auth_rate_limit cascade'
  )
})
afterAll(() => pool.end())

let requestNumber = 0
function request(path: string, body?: unknown, token?: string) {
  return new Request('http://localhost:3147/api/auth/' + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      'cf-connecting-ip': '192.0.2.' + ((++requestNumber % 250) + 1),
      'content-type': 'application/json',
      origin: 'http://localhost:3147',
      ...(token ? { authorization: 'Bearer ' + token } : {})
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  })
}

test('a verified email/password account can sign in using a native bearer session', async () => {
  const signup = await auth.handler(
    request('sign-up/email', {
      email: 'native@example.test',
      password: 'coffee-password-123',
      name: 'Native',
      callbackURL: 'diald://auth-callback'
    })
  )
  expect(signup.status).toBe(200)
  expect(sent).toHaveLength(1)
  const verify = await auth.handler(new Request(sent[0]!.url))
  expect([200, 302]).toContain(verify.status)
  const signin = await auth.handler(
    request('sign-in/email', {
      email: 'native@example.test',
      password: 'coffee-password-123'
    })
  )
  expect(signin.status).toBe(200)
  const token = signin.headers.get('set-auth-token')
  expect(token).toBeTruthy()
  const session = await auth.api.getSession({
    headers: new Headers({ authorization: 'Bearer ' + token })
  })
  expect(session?.user.email).toBe('native@example.test')
  expect(session?.user.id).toMatch(/^[0-9a-f-]{36}$/)
})

test('application data requires authentication', async () => {
  const { createApplication } = await import('../src/application')
  const app = createApplication({ auth, pool })
  const response = await app(new Request('http://localhost:3147/api/me'))
  expect(response.status).toBe(401)
})

async function nativeAccount(email: string) {
  const signup = await auth.handler(
    request('sign-up/email', {
      email,
      password: 'coffee-password-123',
      name: 'Test',
      callbackURL: 'diald://auth-callback'
    })
  )
  expect(signup.status).toBe(200)
  const mail = sent.findLast((m) => m.email === email)!
  await auth.handler(new Request(mail.url))
  const signin = await auth.handler(
    request('sign-in/email', { email, password: 'coffee-password-123' })
  )
  const token = signin.headers.get('set-auth-token')!
  const session = await auth.api.getSession({
    headers: new Headers({ authorization: 'Bearer ' + token })
  })
  return { token, id: session!.user.id }
}

async function dataRequest(path: string, token: string, body?: unknown) {
  const { createApplication } = await import('../src/application')
  return createApplication({ auth, pool })(
    new Request('http://localhost:3147' + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: {
        authorization: 'Bearer ' + token,
        'content-type': 'application/json'
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) })
    })
  )
}

test('an owner can upload and read a bean but another account cannot read or change it', async () => {
  const owner = await nativeAccount('owner@example.test')
  const other = await nativeAccount('other@example.test')
  const id = crypto.randomUUID()
  const inserted = await dataRequest('/api/sync/upload', owner.token, {
    table: 'beans',
    id,
    op: 'put',
    data: { owner_id: owner.id, name: 'Test beans', roaster: 'Test roaster' }
  })
  expect(inserted.status).toBe(200)
  const read = await dataRequest('/api/data/beans/' + id, owner.token)
  expect((await read.json()).name).toBe('Test beans')
  const forbiddenRead = await dataRequest('/api/data/beans/' + id, other.token)
  expect(forbiddenRead.status).toBe(404)
  const forbiddenWrite = await dataRequest('/api/sync/upload', other.token, {
    table: 'beans',
    id,
    op: 'patch',
    data: { name: 'Stolen' }
  })
  expect(forbiddenWrite.status).toBe(403)
  const unchanged = await dataRequest('/api/data/beans/' + id, owner.token)
  expect((await unchanged.json()).name).toBe('Test beans')
})

test('concurrent new brews enforce five lifetime creations and duplicate replay consumes no allowance', async () => {
  const owner = await nativeAccount('quota@example.test')
  const brews = Array.from({ length: 8 }, () => ({
    table: 'brew_sessions',
    id: crypto.randomUUID(),
    op: 'put',
    data: {
      owner_id: owner.id,
      method: 'espresso',
      dose_grams: '18',
      extraction_seconds: '30'
    }
  }))
  const results = await Promise.all(
    brews.map(async (brew) => ({
      brew,
      response: await dataRequest('/api/sync/upload', owner.token, brew)
    }))
  )
  const accepted = results.filter((r) => r.response.status === 200)
  expect(accepted).toHaveLength(5)
  const rejected = results.filter((r) => r.response.status !== 200)
  expect(
    await Promise.all(
      rejected.map((r) => r.response.json().then((b) => b.code))
    )
  ).toEqual(['DX001', 'DX001', 'DX001'])
  const replay = await Promise.all(
    Array.from({ length: 3 }, () =>
      dataRequest('/api/sync/upload', owner.token, accepted[0]!.brew)
    )
  )
  expect(replay.map((r) => r.status)).toEqual([200, 200, 200])
  const status = await dataRequest('/api/extractions/status', owner.token)
  expect(await status.json()).toEqual({
    lifetime_count: 5,
    free_limit: 5,
    has_verified_entitlement: false
  })
  const deleted = await dataRequest('/api/sync/upload', owner.token, {
    table: 'brew_sessions',
    id: accepted[0]!.brew.id,
    op: 'delete'
  })
  expect(deleted.status).toBe(200)
  const recreate = await dataRequest(
    '/api/sync/upload',
    owner.token,
    accepted[0]!.brew
  )
  expect(recreate.status).toBe(200)
  const tombstone = await dataRequest(
    '/api/data/brew_sessions/' + accepted[0]!.brew.id,
    owner.token
  )
  expect((await tombstone.json()).deleted_at).toBeTruthy()
  // Historical hard-deleted IDs must still be rejected.
  await pool.query('delete from brew_sessions where id = $1', [
    accepted[0]!.brew.id
  ])
  const hardDeletedReplay = await dataRequest(
    '/api/sync/upload',
    owner.token,
    accepted[0]!.brew
  )
  expect(hardDeletedReplay.status).toBe(422)
  const finalStatus = await dataRequest('/api/extractions/status', owner.token)
  expect((await finalStatus.json()).lifetime_count).toBe(5)
})

test('missing recovery proof fails closed before signup and sync writes', async () => {
  await pool.query('delete from recovery_lease')
  try {
    const { createApplication } = await import('../src/application')
    const response = await createApplication({ auth, pool })(
      request('sign-up/email', {
        email: 'fenced@example.test',
        name: 'Fenced',
        password: 'coffee-password-123'
      })
    )
    expect(response.status).toBe(503)
    const owner = await pool.query(
      "select id from auth_user where email = 'owner@example.test'"
    )
    const token = (
      await pool.query(
        'select token from auth_session where user_id = $1 limit 1',
        [owner.rows[0].id]
      )
    ).rows[0].token
    const upload = await dataRequest('/api/sync/upload', token, {
      table: 'beans',
      id: crypto.randomUUID(),
      op: 'put',
      data: { name: 'Fenced', roaster: 'Test' }
    })
    expect(upload.status).toBe(503)
  } finally {
    await pool.query(
      "insert into recovery_lease values (1, clock_timestamp(), clock_timestamp(), 'test-snapshot')"
    )
  }
})

test('stale, future and failed backup proofs block writes and cannot be forged by the API role', async () => {
  for (const interval of ["interval '601 seconds'", "interval '-5 seconds'"]) {
    await pool.query(
      `update recovery_lease set snapshot_started_at = clock_timestamp() - ${interval}`
    )
    const response = await dataRequest('/api/sync/upload', 'invalid', {})
    expect(response.status).toBe(503)
  }
  await pool.query(
    "update recovery_lease set snapshot_started_at=clock_timestamp(), verified_at=clock_timestamp() - interval '1 minute'"
  )
  expect((await dataRequest('/api/sync/upload', 'invalid', {})).status).toBe(
    503
  )
  await pool.query(
    'update recovery_lease set snapshot_started_at=clock_timestamp(), verified_at=clock_timestamp()'
  )
  const client = await pool.connect()
  try {
    await client.query('begin')
    await client.query('set local role diald_api')
    await expect(
      client.query(
        'update recovery_lease set snapshot_started_at=clock_timestamp()'
      )
    ).rejects.toMatchObject({ code: '42501' })
  } finally {
    await client.query('rollback')
    client.release()
  }
})

test('a write whose proof expires before COMMIT is rolled back', async () => {
  const client = await pool.connect()
  await pool.query(
    'update recovery_lease set snapshot_started_at=clock_timestamp(), verified_at=clock_timestamp()'
  )
  try {
    await client.query('begin')
    await client.query(
      "insert into auth_email_limit values ('commit-boundary',1,clock_timestamp())"
    )
    await pool.query(
      "update recovery_lease set snapshot_started_at=clock_timestamp() - interval '601 seconds'"
    )
    await expect(client.query('commit')).rejects.toMatchObject({
      code: 'DX006'
    })
  } finally {
    await client.query('rollback')
    client.release()
    await pool.query(
      'update recovery_lease set snapshot_started_at=clock_timestamp(), verified_at=clock_timestamp()'
    )
  }
  expect(
    (
      await pool.query(
        "select count(*)::int as count from auth_email_limit where key='commit-boundary'"
      )
    ).rows[0].count
  ).toBe(0)
})

test('password reset links are single-use and the imported bcrypt password remains supported', async () => {
  const account = await nativeAccount('reset@example.test')
  const hash = await Bun.password.hash('imported-password-123', {
    algorithm: 'bcrypt',
    cost: 4
  })
  await pool.query(
    "update auth_account set password=$1 where user_id=$2 and provider_id='credential'",
    [hash, account.id]
  )
  const signin = await auth.handler(
    request('sign-in/email', {
      email: 'reset@example.test',
      password: 'imported-password-123'
    })
  )
  expect(signin.status).toBe(200)
  const reset = await auth.handler(
    request('request-password-reset', {
      email: 'reset@example.test',
      redirectTo: 'diald://auth-callback?type=recovery'
    })
  )
  expect(reset.status).toBe(200)
  const mail = sent.findLast((m) => m.email === 'reset@example.test')!
  const redirect = await auth.handler(new Request(mail.url))
  const token = new URL(redirect.headers.get('location')!).searchParams.get(
    'token'
  )!
  expect(token).toBeTruthy()
  const change = () =>
    auth.handler(
      request('reset-password', { token, newPassword: 'new-password-123' })
    )
  expect((await change()).status).toBe(200)
  expect((await change()).status).toBe(400)
  expect(
    (
      await auth.handler(
        request('sign-in/email', {
          email: 'reset@example.test',
          password: 'new-password-123'
        })
      )
    ).status
  ).toBe(200)
})

test('off-site and malformed callback targets cannot receive auth links', async () => {
  for (const callbackURL of [
    'https://evil.test',
    '//evil.test',
    '/.//evil.test',
    '/\t/evil.test',
    '/\\evil.test',
    'diald://evil.test'
  ]) {
    const response = await auth.handler(
      request('sign-up/email', {
        email: 'redirect@example.test',
        password: 'coffee-password-123',
        name: 'Test',
        callbackURL
      })
    )
    expect(response.status).toBe(400)
  }
})

test('JWKS and PowerSync JWT bind the authenticated original UUID, issuer and audience', async () => {
  const account = await nativeAccount('jwt@example.test')
  const response = await auth.handler(
    request('token', undefined, account.token)
  )
  expect(response.status).toBe(200)
  const { token } = await response.json()
  const jwks = await (await auth.handler(request('jwks'))).json()
  const { jwtVerify, createLocalJWKSet } = await import('jose')
  const { payload } = await jwtVerify(token, createLocalJWKSet(jwks), {
    issuer: 'http://localhost:3147',
    audience: 'http://localhost:8080'
  })
  expect(payload.sub).toBe(account.id)
  expect(payload.exp! - payload.iat!).toBe(300)
})

test('native Google codes require the original proof key and cannot be replayed', async () => {
  const { hash } = await import('../src/native-oauth')
  const account = await nativeAccount('pkce@example.test')
  const verifier = 'a'.repeat(64),
    code = 'only-this-code'
  await pool.query(
    "insert into native_codes values ($1,$2,$3,clock_timestamp()+interval '2 minutes')",
    [hash(code), hash(verifier), account.token]
  )
  expect(
    (
      await dataRequest('/api/native/exchange', '', {
        code,
        verifier: 'b'.repeat(64)
      })
    ).status
  ).toBe(401)
  const valid = await dataRequest('/api/native/exchange', '', {
    code,
    verifier
  })
  expect((await valid.json()).token).toBe(account.token)
  expect(
    (await dataRequest('/api/native/exchange', '', { code, verifier })).status
  ).toBe(401)
})

test('forged Apple transactions and notifications never create entitlement access', async () => {
  const account = await nativeAccount('forged@example.test')
  const encode = (value: unknown) =>
    Buffer.from(JSON.stringify(value)).toString('base64url')
  const forged =
    encode({ alg: 'none' }) +
    '.' +
    encode({
      environment: 'Sandbox',
      appAccountToken: account.id,
      productId: 'club.diald.supporter.monthly',
      bundleId: 'club.diald'
    }) +
    '.forged'
  expect(
    (
      await dataRequest('/api/iap/transactions', account.token, {
        signedTransactionInfo: forged
      })
    ).status
  ).not.toBe(200)
  expect(
    (await dataRequest('/api/iap/notifications', '', { signedPayload: forged }))
      .status
  ).not.toBe(200)
  expect(
    (await (await dataRequest('/api/extractions/status', account.token)).json())
      .has_verified_entitlement
  ).toBe(false)
})

test('the runtime cannot alter quota, verification evidence, or another account during deletion', async () => {
  const account = await nativeAccount('delete@example.test')
  const other = await nativeAccount('delete-other@example.test')
  const client = await pool.connect()
  for (const sql of [
    'update extraction_creation_quotas set lifetime_count=0',
    "update iap_entitlements set status='active'",
    'select * from source_auth_archive'
  ]) {
    try {
      await client.query('begin')
      await client.query('set local role diald_api')
      await expect(client.query(sql)).rejects.toMatchObject({ code: '42501' })
    } finally {
      await client.query('rollback')
    }
  }
  client.release()
  const { createApplication } = await import('../src/application')
  const app = createApplication({ auth, pool })
  expect(
    (
      await app(
        new Request('http://localhost:3147/api/account', {
          method: 'DELETE',
          headers: { authorization: 'Bearer ' + account.token }
        })
      )
    ).status
  ).toBe(200)
  expect((await dataRequest('/api/me', account.token)).status).toBe(401)
  expect((await dataRequest('/api/me', other.token)).status).toBe(200)
})

test('email budgets count delivered mail, keep recipient cooldown silent, and cap the app total', async () => {
  const { createEmailSender } = await import('../src/email')
  await pool.query('truncate auth_email_limit')
  let attempts = 0
  const send = (async () => {
    attempts++
    return new Response(null, { status: attempts === 1 ? 503 : 201 })
  }) as unknown as typeof fetch
  const sender = createEmailSender(
    pool,
    {
      key: 'test-only',
      from: 'hello@example.test',
      origin: 'https://api.example.test',
      dailyLimit: 1
    },
    send
  )
  const link = 'https://api.example.test/api/auth/verify-email?token=fixture'
  await expect(sender('first@example.test', 'verify', link)).rejects.toThrow(
    'Email delivery unavailable'
  )
  await sender('first@example.test', 'verify', link)
  // With a larger app budget, the recipient-specific limit is a silent no-send.
  const cooldown = createEmailSender(
    pool,
    {
      key: 'test-only',
      from: 'hello@example.test',
      origin: 'https://api.example.test',
      dailyLimit: 40
    },
    send
  )
  await cooldown('first@example.test', 'verify', link)
  expect(attempts).toBe(2)
  await expect(sender('second@example.test', 'verify', link)).rejects.toThrow(
    'Daily email budget exhausted'
  )
})

test('the verified-entitlement SQL boundary preserves revocation/event ordering and current expiry', async () => {
  const account = await nativeAccount('ordered-entitlement@example.test')
  const now = Date.now()
  const record = async (
    status: string,
    signed: number,
    expires = now + 86_400_000
  ) =>
    pool.query(
      'select record_verified_iap_entitlement($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
      [
        account.id,
        'club.diald.supporter.monthly',
        'club.diald',
        'original',
        'transaction',
        status,
        new Date(expires),
        status === 'revoked' ? new Date(now) : null,
        'Sandbox',
        new Date(signed),
        'notification'
      ]
    )
  const active = async () =>
    (await (await dataRequest('/api/extractions/status', account.token)).json())
      .has_verified_entitlement
  await record('active', now)
  expect(await active()).toBe(true)
  await record('revoked', now + 1000)
  await record('active', now)
  expect(await active()).toBe(false)
  await record('active', now + 1000)
  expect(await active()).toBe(false)
  await record('active', now + 2000)
  expect(await active()).toBe(true)
  await record('active', now + 3000, now - 1000)
  expect(await active()).toBe(false)
})
