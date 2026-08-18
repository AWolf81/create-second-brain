# __VAULT_TITLE__

A private knowledge vault with an Obsidian-style **graph view**, search, backlinks and an
explorer tree. Markdown in, static site out, served behind HTTP basic auth.

- Write notes in `05-knowledge/`
- Push to `main`, GitHub Actions rebuilds and deploys
- Read it at `https://__APP_NAME__.fly.dev`

## Why not GitHub Pages

Pages serves publicly **even from a private repository**, and private Pages visibility is
GitHub Enterprise Cloud only. For a vault that will accumulate things you would not post
publicly, that default is the wrong way round. Fly plus basic auth gives real credentials
and no public surface.

## Setup

Four steps the scaffolder cannot do for you. Run `./scripts/doctor.sh` at any point to see
which are still outstanding.

```bash
fly apps create __APP_NAME__

fly secrets set --app __APP_NAME__ \
  BASIC_AUTH_USER='you' \
  BASIC_AUTH_PASSWORD='a-real-password'

fly tokens create deploy -x 8760h    # → GitHub repo secret FLY_API_TOKEN

git init && git add -A && git commit -m "init" && fly deploy
```

The password is plaintext on purpose: the container hashes it with bcrypt at startup, so
setup works from Fly's dashboard on a phone with no tooling. Supply `BASIC_AUTH_HASH`
instead if you would rather Fly stored a hash — it takes precedence.

**Do not run `fly launch`.** It is a bootstrapper: it detects a runtime and *generates* a
`fly.toml`, overwriting the one here. `fly apps create` then `fly deploy`.

## Writing notes

Open every note with a single `# Heading`. The build derives the page title, graph label,
search entry and breadcrumb from it — nothing else is required, and notes are never
modified: the derivation happens on a staged copy.

Long headings are shortened for the graph, where labels do not wrap: cut at the first em
dash, en dash, colon or comma, then capped at 32 characters (`TITLE_MAX`). So
`# Metrics, activation, and instrumentation` labels as *Metrics*. Override with frontmatter
when that reads badly:

```markdown
---
title: "Short label"
---

# A much longer heading
```

`./scripts/validate-note-titles.sh` fails the deploy if a note has neither, so a label never
silently regresses to a filename.

## What gets published

`site/build-content.sh` holds an **allowlist** — `04-projects` and `05-knowledge` by default.
A folder not named there never reaches the site, so a new folder is private by default rather
than published by accident. The build fails rather than publishing an empty site.

## Renaming the app

`app` in `fly.toml` and `baseUrl` in `site/quartz.config.yaml` must agree. Self-hosted fonts
are emitted as absolute `https://<baseUrl>/static/fonts/...` URLs and 404 silently otherwise.
`./scripts/doctor.sh` checks this.

## Known characteristics

- **The graph fetches d3 and pixi.js from `cdn.jsdelivr.net` at runtime.** Quartz hardcodes
  this with no self-host option. Your note content never goes there, but the request is
  visible to that CDN.
- **Fonts are self-hosted**, downloaded at build time — no reader calls Google Fonts.
- **Missing credentials fail closed and stay up.** The entrypoint substitutes an unguessable
  placeholder, so a half-configured app answers 401 rather than crash-looping, and setting
  the secrets fixes it without a redeploy.
- **Machines scale to zero.** The first request after idle pays a short cold start.
- **Request paths are not logged**, so note titles stay out of the platform log stream.

## Bumping Quartz

Quartz is cloned at a pinned commit (`QUARTZ_REF` in `Dockerfile`), not vendored — its config
schema changes between versions. Rebuild locally before changing the ref:

```bash
docker build -t vault-site .
docker run --rm -p 8080:8080 -e BASIC_AUTH_USER=test -e BASIC_AUTH_PASSWORD=test vault-site
```
