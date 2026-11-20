import { migrate } from 'drizzle-orm/node-postgres/migrator'
import { connectDatabase } from '../src/database'

if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required')
const { db, pool } = connectDatabase(process.env.DATABASE_URL)
try {
  await migrate(db, {
    migrationsFolder: new URL('../drizzle', import.meta.url).pathname
  })
} finally {
  await pool.end()
}
