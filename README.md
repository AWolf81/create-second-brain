# create-second-brain

Scaffold a private knowledge vault with an Obsidian-style **graph view** — Quartz built from
your markdown, served by Caddy on Fly behind HTTP basic auth.

```bash
pnpm create second-brain my-brain
# or: npm create second-brain my-brain
# or: npx create-second-brain my-brain
```

Then four steps the scaffolder cannot do for you — creating the Fly app, setting two
secrets, and adding a deploy token to GitHub. The generated project ships a
`scripts/doctor.sh` that tells you which are still missing.

## Why this exists

The obvious way to publish a markdown vault is GitHub Pages. Pages serves **publicly even
from a private repository**, and private visibility is Enterprise Cloud only — so the
obvious path quietly publishes everything. A knowledge base accumulates the things you would
least like to publish, so the default should be the other way round.

## What you get

| | |
|---|---|
| **Graph view** | Obsidian-style link graph, plus search, backlinks and an explorer tree |
| **Real auth** | HTTP basic auth with bcrypt, credentials from platform secrets |
| **Titles for free** | Page titles and graph labels derived from each note's `# H1` |
| **Allowlisted publishing** | A new folder is private by default |
| **CI deploy** | Push to `main`, GitHub Actions rebuilds and deploys |
| **Scales to zero** | A static site on a machine that stops when idle |

## Design notes

**Titles are derived, not declared.** The build reads each note's `# H1` and writes the
title into a staged copy — your files are never modified. There is no convention for an
author to remember and no frontmatter to forget, which is why a note written a year from now
is still labelled correctly. Long headings are shortened for the graph, where labels do not
wrap.

**The password is plaintext by design.** Caddy's `basic_auth` needs a bcrypt hash, which
normally means finding a shell to generate one. The container hashes at startup instead, so
the whole deployment is configurable from a dashboard on a phone. `BASIC_AUTH_HASH` still
takes precedence if you would rather store a hash.

**Half-configured fails closed and stays up.** Caddy refuses to parse an empty username or
password, which would crash-loop a machine set up halfway. The entrypoint substitutes an
unguessable placeholder instead: the site answers 401 to everything and starts working the
moment the secrets land, with no redeploy.

## Options

```bash
pnpm create second-brain my-brain --app my-fly-app --title "My Brain" --yes
```

| Flag | Meaning |
|---|---|
| `--app` | Fly app name; also sets the site's `baseUrl` |
| `--title` | Site title |
| `--repo` | Repository URL, linked in the site footer |
| `--yes` | Skip the prompts |

## Requirements

Node 18+, a Fly account, and a GitHub repository. No npm dependencies — the scaffolder is
one dependency-free file.

## Not affiliated

"Building a Second Brain" is a trademark of Forte Labs. This project is unaffiliated and
implements no part of that method; it is a static-site scaffolder that happens to use the
generic phrase.

MIT licensed.
