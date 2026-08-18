#!/usr/bin/env node
//
// Scaffold an agent-first knowledge vault: markdown your AI agents read and
// write, published privately with an Obsidian-style graph view.
//
//   pnpm create @awolf81/second-brain my-brain
//
// Dependency-free on purpose. A scaffolder that copies files should not drag a
// package tree along with it.

import fs from "node:fs"
import path from "node:path"
import readline from "node:readline/promises"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { stdin, stdout } from "node:process"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const TEMPLATE = path.join(HERE, "template")
const TARGETS = path.join(TEMPLATE, "targets")

// npm strips a file literally named .gitignore from published tarballs, so the
// template ships these prefixed and they are restored on the way out.
const RENAME = {
  _gitignore: ".gitignore",
  _dockerignore: ".dockerignore",
  _github: ".github",
  _obsidian: ".obsidian",
  "_gitlab-ci.yml": ".gitlab-ci.yml",
}

const argv = process.argv.slice(2)
const VALUE_FLAGS = new Set(["app", "title", "repo", "target", "ci"])
const flag = (name) => {
  const i = argv.indexOf(`--${name}`)
  return i !== -1 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : undefined
}
const has = (name) => argv.includes(`--${name}`)
const positional = argv.filter(
  (a, i) => !a.startsWith("--") && !(i > 0 && VALUE_FLAGS.has(argv[i - 1]?.replace(/^--/, ""))),
)

// Fly app names and GitLab project paths are both DNS-ish labels.
const slug = (s) =>
  s.toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30) || "second-brain"

function copyTree(from, to, replace, skip = new Set()) {
  fs.mkdirSync(to, { recursive: true })
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue
    const src = path.join(from, entry.name)
    const dst = path.join(to, RENAME[entry.name] ?? entry.name)

    if (entry.isDirectory()) {
      copyTree(src, dst, replace, skip)
      continue
    }

    let body = fs.readFileSync(src, "utf8")
    for (const [token, value] of Object.entries(replace)) body = body.split(token).join(value)
    fs.writeFileSync(dst, body)
    if (dst.endsWith(".sh")) fs.chmodSync(dst, 0o755)
  }
}

const dir = positional[0] ?? "my-brain"
const target_dir = path.resolve(process.cwd(), dir)

if (fs.existsSync(target_dir) && fs.readdirSync(target_dir).length > 0) {
  console.error(`✗ ${target_dir} already exists and is not empty.`)
  process.exit(1)
}

let target = flag("target") ?? "gitlab"
let app = flag("app") ?? slug(path.basename(target_dir))
let title = flag("title") ?? "Second Brain"
let repo = flag("repo") ?? ""
// Which CI system drives the deploy. GitLab Pages is published by GitLab, so
// the choice only exists for the Fly target.
let ci = flag("ci") ?? "github"

if (!has("yes") && stdin.isTTY) {
  const rl = readline.createInterface({ input: stdin, output: stdout })
  target = ((await rl.question(`Deploy target — gitlab (private Pages, free) or fly (own credentials) [${target}]: `)) || target).trim()
  app = slug((await rl.question(`Project / app name [${app}]: `)) || app)
  title = (await rl.question(`Site title [${title}]: `)) || title
  repo = (await rl.question(`Repository URL (optional): `)) || repo
  if (target === "fly") ci = ((await rl.question(`CI — github or gitlab [${ci}]: `)) || ci).trim()
  rl.close()
}

if (!fs.existsSync(path.join(TARGETS, target))) {
  console.error(`✗ Unknown target "${target}". Available: ${fs.readdirSync(TARGETS).join(", ")}`)
  process.exit(1)
}

const replace = {
  __APP_NAME__: app,
  __VAULT_TITLE__: title,
  __REPO_URL__: repo || "https://example.com",
  __BASE_URL__: target === "fly" ? `${app}.fly.dev` : `<your-namespace>.gitlab.io/${app}`,
  __SITE_URL_HUMAN__: target === "fly" ? `https://${app}.fly.dev` : `https://<your-namespace>.gitlab.io/${app}`,
}

copyTree(TEMPLATE, target_dir, replace, new Set(["targets"]))
copyTree(path.join(TARGETS, target), target_dir, replace, new Set(["_setup.md", "ci-github", "ci-gitlab"]))

// Targets that can be driven by more than one CI system keep each option in its
// own directory; copy only the chosen one.
const ciDir = path.join(TARGETS, target, `ci-${ci}`)
if (fs.existsSync(path.join(TARGETS, target, "ci-github"))) {
  if (!fs.existsSync(ciDir)) {
    console.error(`✗ Unknown --ci "${ci}" for target "${target}". Available: github, gitlab`)
    process.exit(1)
  }
  copyTree(ciDir, target_dir, replace)
}

// Each target documents its own setup; splice it into the README so the reader
// sees one path, not a menu of options that do not apply to them.
const setupSrc = path.join(TARGETS, target, "_setup.md")
const ciNote = ci === "gitlab"
  ? "\n\nCI runs on GitLab: set `FLY_API_TOKEN` under Settings → CI/CD → Variables (masked, protected) instead of as a GitHub secret."
  : ""
if (fs.existsSync(setupSrc)) {
  let setup = fs.readFileSync(setupSrc, "utf8")
  for (const [token, value] of Object.entries(replace)) setup = setup.split(token).join(value)
  const readme = path.join(target_dir, "README.md")
  fs.writeFileSync(readme, fs.readFileSync(readme, "utf8").replace("<!-- TARGET_SETUP -->", setup.trim() + (target === "fly" ? ciNote : "")))
}

// COG is the point of an agent-first vault, so it installs by default. It is a
// network fetch from upstream, so a failure warns and moves on rather than
// aborting a scaffold that is otherwise complete.
let cogInstalled = false
if (!has("no-cog")) {
  try {
    execFileSync("bash", ["scripts/add-cog.sh"], { cwd: target_dir, stdio: "inherit" })
    cogInstalled = true
  } catch {
    console.warn("\n! COG install failed — run ./scripts/add-cog.sh once you are online.\n")
  }
}

const steps =
  target === "gitlab"
    ? `  1  Push this to a GitLab project named "${app}"
  2  Settings → General → Visibility, project features, permissions → Pages
     → enable access control, so only project members can view it
  3  The pipeline builds and publishes on the next push to your default branch`
    : `  1  fly apps create ${app}
  2  fly secrets set --app ${app} BASIC_AUTH_USER='you' BASIC_AUTH_PASSWORD='a-real-password'
  3  fly tokens create deploy -x 8760h     → GitHub repo secret FLY_API_TOKEN
  4  git init && git add -A && git commit -m "init" && fly deploy`

console.log(`
✓ Created ${path.relative(process.cwd(), target_dir) || "."}  (target: ${target})

Next:

${steps}

Then:

  ./scripts/doctor.sh       check what is still missing${cogInstalled ? "" : "\n  ./scripts/add-cog.sh      install the COG agent skills"}
  ./scripts/link-repo.sh ~/code/my-product
                            point a work repo at this vault, so agents there
                            read it before answering. Nothing is written into
                            that repo.

Write notes in 05-knowledge/. Each opens with a '# Heading' — the site derives
its title, graph label and search entry from it. Nothing else needed.
`)
