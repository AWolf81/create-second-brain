# create-second-brain

**The knowledge base your coding agents read and write — published privately, with a graph view.**

Markdown in git, so Claude Code, Codex and friends can read and edit it directly. A Quartz
site with an Obsidian-style link graph, search and backlinks, behind authentication. The
same folder opens in Obsidian locally.

```bash
pnpm create @awolf81/second-brain my-brain
```

No npm? `npx degit AWolf81/create-second-brain/template my-brain`

## Why this exists

Two mature ecosystems, and nothing in between them.

**Agent vaults** — [COG](https://github.com/huytieu/COG-second-brain), [agent-brain](https://github.com/Railly/agent-brain) — give you markdown conventions and agent skills, and stop at the filesystem. No site.

**Digital-garden publishers** — Quartz, the Obsidian Digital Garden plugin, Flowershow — publish beautifully and are **public by default**. A knowledge base accumulates precisely the material you would least like to publish.

This is the intersection: agent-readable markdown, published privately, on infrastructure you choose.

## Two deploy targets

```bash
pnpm create @awolf81/second-brain my-brain                 # GitLab Pages (default)
pnpm create @awolf81/second-brain my-brain --target fly    # Fly + Caddy basic auth
```

| | GitLab Pages | Fly |
|---|---|---|
| Cost | free (400 CI min/mo) | ~free, scales to zero |
| Who can read it | project members, Guest+ | anyone with the password you set |
| Setup | push, then flip one setting | app + 2 secrets + deploy token |
| Ships | `.gitlab-ci.yml` | Dockerfile, Caddy, GitHub Actions |

**GitLab if you can.** It is simpler, free, and access control is a checkbox. **Fly** when readers should not need a GitLab account, or you want the region and credentials under your control.

## What you get

**Titles you never write.** The build reads each note's `# H1` and derives the page title, graph label, search entry and breadcrumb — on a *staged copy*, so your files are never modified. No frontmatter convention for an author or an agent to remember. Long headings are shortened for the graph, where labels do not wrap: `# Metrics, activation, and instrumentation` becomes *Metrics*.

**Private by default.** `site/build-content.sh` is an allowlist. A folder that is not named there never reaches the site, so a new folder is private by accident-proof default rather than published by one.

**Guards that fail loudly.** `validate-note-titles.sh` fails the build when a note has no title source. `doctor.sh` checks the steps a scaffolder cannot do — and the `baseUrl` drift whose only symptom is silently 404ing fonts.

**Obsidian and the site agree.** `.obsidian/` ships configured, with graph filters matching the publish allowlist. Settings are committed; per-machine state is gitignored.

**COG optional.** `./scripts/add-cog.sh` fetches [COG](https://github.com/huytieu/COG-second-brain) from upstream — 33 agent skills, workers and verifiers. Fetched rather than vendored, so attribution stays upstream and COG's own updater keeps working.

## Honest alternatives

| Use instead | When |
|---|---|
| [Obsidian Publish](https://obsidian.md/publish) — $8/mo | You want it working in minutes, site-wide password is enough, and you would rather not run anything. Genuinely the right answer for most people. |
| Plain GitLab Pages + `npx quartz create` | You want the private site and none of the agent conventions. This project is then a thin convenience. |
| [COG](https://github.com/huytieu/COG-second-brain) or [agent-brain](https://github.com/Railly/agent-brain) alone | You want the agent vault and never need to read it in a browser. |
| Digital-garden plugins | Your notes are meant to be public. |

## Known characteristics

- **The graph fetches d3 and pixi.js from `cdn.jsdelivr.net` at runtime.** Quartz hardcodes this with no self-host option. Note content never goes there; the request is visible to that CDN.
- **Fonts are self-hosted**, downloaded at build time — no reader calls Google Fonts.
- **Obsidian labels graph nodes by filename**, so identically-named files look identical locally even though the site shows derived titles. The build-time derivation cannot reach into Obsidian.
- Quartz is cloned at a pinned commit, not vendored — its config schema changes between versions.

## Credits

[Quartz](https://github.com/jackyzha0/quartz) by jackyzha0 does the site generation. [COG](https://github.com/huytieu/COG-second-brain) by huytieu provides the agent framework. Both MIT.

Not affiliated with Forte Labs; "Building a Second Brain" is their trademark and this implements no part of that method.

MIT licensed.
