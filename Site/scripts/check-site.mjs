// Verifies the built site before it is packaged: every page the app and App
// Store listing link to exists, has its content, and references only assets
// that were built.
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const root = 'dist'
for (const [path, heading] of [
  ['index.html', 'Make every cup easier to repeat.'],
  ['privacy/index.html', 'Privacy Policy'],
  ['terms/index.html', 'Terms of Use'],
  ['support/index.html', 'Support']
]) {
  const html = readFileSync(join(root, path), 'utf8')
  assert(html.includes(heading), `Missing content: ${path}`)
  assert(
    html.includes('mailto:kyle@kylescudder.co.uk'),
    `Missing contact: ${path}`
  )
  const assets = [
    ...html.matchAll(/(?:src|href)="(\/(?:_astro|assets)\/[^"?#]+)"/g)
  ]
  assert(assets.length > 0, `Missing assets: ${path}`)
  for (const [, asset] of assets) {
    assert(existsSync(join(root, asset)), `Missing asset: ${asset}`)
  }
}
console.log('Home, legal and support pages and their assets verified.')
