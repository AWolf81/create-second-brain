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
