import { Pool } from 'pg'
import { readFile } from 'node:fs/promises'
import { z } from 'zod'

// Called by the trusted backup verifier, with its private database credential.
// This is a narrow input contract, NOT evidence that recovery.py already emits it.
// The host adapter must use snapshot START time and only a verified NAS object.
const proof = z
  .object({
    snapshotStartedAt: z.iso.datetime({ offset: true }),
    verifiedAt: z.iso.datetime({ offset: true }),
    snapshotID: z.string().min(1),
    nasVerified: z.literal(true)
  })
  .strict()
  .parse(JSON.parse(await readFile(process.argv[2], 'utf8')))
const start = Date.parse(proof.snapshotStartedAt),
  verified = Date.parse(proof.verifiedAt),
  now = Date.now()
if (start > now || verified > now || verified < start || now - start >= 600_000)
  throw new Error('Recovery proof is not fresh')
if (!process.env.RECOVERY_DATABASE_URL)
  throw new Error('RECOVERY_DATABASE_URL is required')
const pool = new Pool({
  connectionString: process.env.RECOVERY_DATABASE_URL,
  max: 1
})
try {
  await pool.query(
    'insert into recovery_lease values(1,$1,$2,$3) on conflict(id) do update set snapshot_started_at=excluded.snapshot_started_at,verified_at=excluded.verified_at,snapshot_id=excluded.snapshot_id where recovery_lease.snapshot_started_at <= excluded.snapshot_started_at',
    [proof.snapshotStartedAt, proof.verifiedAt, proof.snapshotID]
  )
} finally {
  await pool.end()
}
