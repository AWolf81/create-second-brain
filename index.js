#!/usr/bin/env node
//
// Scaffold a private knowledge vault: Quartz built from markdown, served by
// Caddy on Fly behind HTTP basic auth.
//
//   pnpm create second-brain my-brain
//
// Deliberately dependency-free. A scaffolder that copies files should not drag
// a package tree along with it.

import fs from "node:fs"
import path from "node:path"
import readline from "node:readline/promises"
import { fileURLToPath } from "node:url"
import { stdin, stdout } from "node:process"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const TEMPLATE = path.join(HERE, "template")

// npm strips a file literally named .gitignore from published tarballs, so the
// template ships these prefixed and they are restored on the way out.
const RENAME = { _gitignore: ".gitignore", _dockerignore: ".dockerignore", _github: ".github" }

const argv = process.argv.slice(2)
const flag = (name) => {
  const i = argv.indexOf(`--${name}`)
  return i !== -1 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : undefined
}
const has = (name) => argv.includes(`--${name}`)
const positional = argv.filter((a) => !a.startsWith("--") && argv[argv.indexOf(a) - 1] !== "--app")

// Fly app names are DNS labels: lowercase alphanumeric and hyphens.
const slug = (s) =>
  s.toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30) || "second-brain"

function copyTree(from, to, replace) {
  fs.mkdirSync(to, { recursive: true })
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const target = RENAME[entry.name] ?? entry.name
    const src = path.join(from, entry.name)
    const dst = path.join(to, target)

    if (entry.isDirectory()) {
      copyTree(src, dst, replace)
      continue
    }

    let body = fs.readFileSync(src, "utf8")
    for (const [token, value] of Object.entries(replace)) body = body.split(token).join(value)
    fs.writeFileSync(dst, body)
    if (dst.endsWith(".sh")) fs.chmodSync(dst, 0o755)
  }
}

const dir = positional[0] ?? "my-brain"
const target = path.resolve(process.cwd(), dir)

if (fs.existsSync(target) && fs.readdirSync(target).length > 0) {
  console.error(`✗ ${target} already exists and is not empty.`)
  process.exit(1)
}

let app = flag("app") ?? slug(path.basename(target))
let title = flag("title") ?? "Second Brain"
let repo = flag("repo") ?? ""

if (!has("yes") && stdin.isTTY) {
  const rl = readline.createInterface({ input: stdin, output: stdout })
  app = slug((await rl.question(`Fly app name [${app}]: `)) || app)
  title = (await rl.question(`Site title [${title}]: `)) || title
  repo = (await rl.question(`Repository URL (optional): `)) || repo
  rl.close()
}

copyTree(TEMPLATE, target, {
  __APP_NAME__: app,
  __VAULT_TITLE__: title,
  __REPO_URL__: repo || "https://example.com",
})

console.log(`
✓ Created ${path.relative(process.cwd(), target) || "."}
  Fly app:  ${app}
  Site URL: https://${app}.fly.dev

Next — the four steps a scaffolder cannot do for you:

  1  fly apps create ${app}
  2  fly secrets set --app ${app} BASIC_AUTH_USER='you' BASIC_AUTH_PASSWORD='a-real-password'
  3  fly tokens create deploy -x 8760h     → GitHub repo secret FLY_API_TOKEN
  4  git init && git add -A && git commit -m "init" && fly deploy

Then run ./scripts/doctor.sh to check what is still missing.

Write notes in 05-knowledge/. Each one opens with a '# Heading' — the site
derives its title, graph label and search entry from it. Nothing else needed.
`)
