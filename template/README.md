# __VAULT_TITLE__

An agent-first knowledge vault. Markdown in git, so your coding agents can read and write
it directly; a private Quartz site with a graph view, search and backlinks for when you
want to browse it; and the same folder opens in Obsidian.

Read it at __SITE_URL_HUMAN__

## Setup

Run `./scripts/doctor.sh` at any point to see what is still outstanding.

<!-- TARGET_SETUP -->

Optional, once:

```bash
./scripts/add-cog.sh     # COG agent skills — 33 skills, workers, verifiers
```

## Linking your work repos

A vault only helps if the agent working in your *product* repo knows it exists. Link one:

```bash
./scripts/link-repo.sh ~/code/my-product          # a local path, or
./scripts/link-repo.sh git@github.com:me/my-product.git

./scripts/link-repo.sh --list
./scripts/link-repo.sh --unlink my-product
```

From then on every session in that repo reads the vault before answering about strategy,
pricing, compliance, or a past decision, and offers to harvest what transfers when a piece
of work closes.

**Nothing is written into the work repo** — not a file, not a commit, not a `.gitignore`
line. Committed wiring rides every branch, shows up in every PR diff, and turns into a
merge-conflict surface on long-lived branches. The link is split instead:

| Half | Where | Committed |
|---|---|---|
| Which repos exist, and what they are | `04-projects/<name>/README.md`, `repo:` frontmatter | yes, here |
| Where the vault sits on *this* machine | `~/.claude/CLAUDE.md` + `~/.claude/skills/second-brain/` | no, machine-local |

That split is also why the durable half is derived rather than registered: the list of
linked repos is read back out of the project pages, so there is no registry file to drift.

On a second machine, clone the vault and run `./scripts/link-repo.sh` once per repo again —
the committed half is already there, so it only rebuilds the local half.

## Proof it was actually read

The bridge skill tells agents to consult the vault before answering. Nothing about that
claim was checkable, which is the same shape as a metric whose numerator is structurally
zero — it looks like coverage and cannot fail visibly.

`link-repo.sh` installs a `PostToolUse` hook at user level that records every vault file an
agent opens. Report on it:

```bash
./scripts/vault-usage.sh                  # reads per note, and which notes nothing has opened
./scripts/vault-usage.sh --since 2026-08-01
```

The **never read** section is the useful half. A note nothing has opened is either a question
that stopped being asked or one the routing table fails to route — opposite fixes, and you
cannot tell which without knowing it happened.

Only the note path, the tool, a session id and a timestamp are recorded — never the question,
the answer, or anything outside the vault. The ledger lives in your user config directory and
is never committed. Delete it any time; it rebuilds.

Needs `jq`. Without it the link still works and `doctor.sh` says the hook is not registered.

## Writing notes

Open every note with a single `# Heading`. The build derives the page title, graph label,
search entry and breadcrumb from it. Nothing else is required, and your files are never
modified — the derivation happens on a staged copy.

Long headings are shortened for the graph, where labels do not wrap: cut at the first em
dash, en dash, colon or comma, then capped at 32 characters (`TITLE_MAX`). So
`# Metrics, activation, and instrumentation` labels as *Metrics*. Override when that reads
badly:

```markdown
---
title: "Short label"
---

# A much longer heading
```

`./scripts/validate-note-titles.sh` fails the build if a note has neither, so a label never
silently regresses to a filename.

## What gets published

`site/build-content.sh` holds an **allowlist** — `04-projects` and `05-knowledge` by
default. A folder not named there never reaches the site, so a new folder is private by
default rather than published by accident. The build fails rather than publishing an empty
site.

## Obsidian

`.obsidian/` is configured and committed: graph filtered to the same folders the site
publishes, wikilinks in the shortest form Quartz resolves. Per-machine state
(`workspace`, `cache`, installed plugins) is gitignored, so the vault behaves the same on
every machine without syncing window layouts.

One difference worth knowing: **Obsidian labels graph nodes by filename**, not by heading.
Two files both called `README.md` look identical in Obsidian's graph even though the site
shows their derived titles. Either give files distinct names, or install the *Front Matter
Title* community plugin.

## Known characteristics

- **The graph fetches d3 and pixi.js from `cdn.jsdelivr.net`** at runtime. Quartz hardcodes
  this. Your notes never go there, but the request is visible to that CDN.
- **Fonts are self-hosted**, downloaded at build time — no reader calls Google Fonts.
- Quartz is cloned at a pinned commit, not vendored; its config schema changes between
  versions. Rebuild locally before changing the ref.
