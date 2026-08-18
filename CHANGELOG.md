# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been published to npm yet. On release, rename `[Unreleased]` to the version
and date, and open a fresh `[Unreleased]` above it.

## [Unreleased]

### Added

- Scaffolder for an agent-first knowledge vault: markdown in git, published as a private
  Quartz site with an Obsidian-style link graph, search and backlinks.
- Two deploy targets. `--target gitlab` (default) publishes to GitLab Pages, private via
  Pages access control on the Free tier. `--target fly` runs Caddy on Fly behind HTTP
  basic auth, for readers who are not project members.
- `--ci github|gitlab` for the Fly target, so the vault can live on either host. Only the
  chosen pipeline is written; an unknown value is rejected rather than producing a project
  with no pipeline.
- Titles derived from each note's `# H1` at build time, on a staged copy, so source files
  are never modified and no frontmatter convention has to be remembered. Long headings are
  shortened for the graph — cut at the first em dash, en dash, colon or comma, then capped
  at `TITLE_MAX` (32) on a word boundary. Frontmatter `title:` overrides.
- `scripts/validate-note-titles.sh`, which fails the build when a note has neither an H1
  nor a frontmatter title, so a graph label never silently regresses to a filename.
- `scripts/doctor.sh`, which detects the deploy target and checks the setup steps a
  scaffolder cannot perform — including the `fly.toml` app versus `quartz.config.yaml`
  `baseUrl` drift whose only symptom is silently 404ing fonts.
- `scripts/add-cog.sh`, which installs [COG](https://github.com/huytieu/COG-second-brain)
  from upstream rather than vendoring it, so attribution stays with its authors and COG's
  own updater keeps working. Runs by default; `--no-cog` opts out, and a failed fetch
  warns rather than aborting the scaffold. Merges into directories that already exist —
  `scripts/` does — rather than skipping them wholesale, so COG's own validators arrive;
  your files are never overwritten.
- `.obsidian/` shipped configured: graph filtered to the folders the site publishes,
  wikilinks in the shortest form Quartz resolves, per-machine state gitignored.
- `scripts/link-repo.sh`, which links a work repository to the vault so agents working in
  that repo read it before answering and offer to harvest what transfers. `--list` and
  `--unlink <slug>` manage the links; `--unlink` keeps the project page and removes only
  the wiring. The link is split in two: the durable half is a `repo:` key in
  `04-projects/<name>/README.md`, committed here, and the machine-specific half is the
  `second-brain` skill plus a marked block in `~/.claude/CLAUDE.md`. The list of linked
  repos is derived from the project pages rather than kept in a registry file, so there is
  nothing to drift.
- `doctor.sh` now reports linked repositories and fails when the vault lists links that
  `~/.claude` knows nothing about — the state a fresh clone on a second machine lands in,
  where the vault looks correctly configured and the agent side does not exist.

- `scripts/check-agent-surface.sh` and `local-skills.txt`, which reconcile COG's surface
  validator against skills you add yourself. COG's validator is a publishing gate for
  COG's own plugin, so your skills make it report an error permanently; registering them
  in COG's manifests would be undone by `cog-update.sh`. Declaring them here keeps the
  check expected to pass, which is what makes a red result mean something. It no-ops
  cleanly when COG, or COG's manifests, are absent.
- Fonts downloaded at build time and self-hosted, so no reader's browser calls Google
  Fonts.
- Quartz cloned at a pinned commit rather than vendored, because its config schema changes
  between versions.

### Security

- Publishing is an **allowlist**, not a filter. A top-level folder not named in
  `site/build-content.sh` never reaches the site, so a new folder is private by default
  rather than published by accident.
- The build fails rather than publishing an empty site, so a misconfiguration cannot
  silently replace a working deploy with nothing.
- On the Fly target, missing or half-configured credentials **fail closed and stay up**:
  the entrypoint substitutes an unguessable placeholder, the site answers 401 to
  everything, and setting the secrets fixes it without a redeploy. Caddy refuses to parse
  an empty username or password, so without this a half-configured app would crash-loop.
- The basic-auth password is hashed with bcrypt at container start and unset before exec,
  so it is absent from the served process's environment and never appears in a process
  list. `BASIC_AUTH_HASH` takes precedence when supplied.
- Linking a work repo writes **nothing into that repo** — no file, no commit, no
  `.gitignore` entry. Committed wiring rides every branch, appears in every PR diff and
  becomes a merge-conflict surface on long-lived branches; the machine-specific half lives
  in `~/.claude` instead. The bridge skill refuses requests to install itself into a work
  repo. Linking the vault to itself is refused.
- Analytics, sitemap, RSS and OG images are off, and responses carry
  `X-Robots-Tag: noindex, nofollow, noarchive`.
- Caddy logs at `ERROR` only, so note titles do not reach the platform log stream.

[Unreleased]: https://github.com/AWolf81/create-second-brain/commits/main
