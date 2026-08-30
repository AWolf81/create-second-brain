# Working on create-second-brain

This repo is a **scaffolder**, not a vault. It generates knowledge vaults; it is not one.
That distinction causes most of the confusion here, so start with it.

## The two CLAUDE.md files

| File | Read by | Purpose |
|---|---|---|
| `CLAUDE.md` (this one) | an agent working **on the scaffolder** | how the generator works |
| `template/CLAUDE.md` | an agent working **in a generated vault** | how to write notes |

Editing the wrong one is the easiest mistake to make. Instructions about notes, harvesting
or `WHERE-THINGS-LIVE.md` belong in `template/CLAUDE.md`. Instructions about `index.js`,
substitution or targets belong here.

The same applies to `README.md` vs `template/README.md`, and to `scripts/` — this repo has
none, while `template/scripts/` ships seven into every vault.

## What `index.js` actually does

Dependency-free by design; do not add a package tree to a file-copier.

1. Reads flags: `--target`, `--ci`, `--app`, `--title`, `--repo`, `--yes`. Prompts for them
   when `stdin.isTTY` and `--yes` is absent.
2. Copies `template/` to the destination, **skipping `targets/`**.
3. Copies `template/targets/<target>/` on top, so one target's files land at the root.
4. Copies `template/targets/<target>/ci-<ci>/` when that target offers a CI choice.
5. Splices `_setup.md` into the destination README at `<!-- TARGET_SETUP -->`.
6. Writes `.template-manifest`: every file written, with the sha256 of the **substituted**
   bytes.

### Substitution

Every `__TOKEN__` in the `replace` map is replaced in every copied file. Adding a
placeholder means adding it to that map — an unmapped token ships literally into the vault,
which is exactly the `baseUrl: __BASE_URL__` failure the degit route produced.

`__FOOTER_LINKS__` is the odd one: it covers a whole YAML entry rather than a value, so the
footer link can be **omitted** when no `--repo` is given. Filling a placeholder with a fake
value (it used to be `https://example.com`) ships a dead link that looks deliberate and
nothing ever prompts a fix. Prefer omitting over faking.

### Underscore-prefixed files

npm strips a file literally named `.gitignore` from published tarballs, so the template
ships `_gitignore`, `_obsidian`, `_github`, `_dockerignore`, `_gitlab-ci.yml` and they are
renamed on the way out via `RENAME`. A new dotfile in the template needs both the
underscore name **and** a `RENAME` entry, or it silently never arrives.

`_setup.md` is deliberately *not* renamed — it is spliced, then skipped.

## The manifest, and why notes are absent from it

`.template-manifest` is what lets `template/scripts/update-template.sh` update a vault in
place. It hashes the substituted bytes because that is what landed on disk.

A vault holds three kinds of file:

- **machinery** the template owns — overwrite freely
- **notes** the owner owns — never touch
- **seeded** files the template writes and the owner then edits (`05-knowledge/README.md`,
  `WHERE-THINGS-LIVE.md`, `CLAUDE.md`)

The third kind is the one a naive whole-tree copy destroys, and it did: a populated routing
table was replaced by the empty placeholder, silently. A hash match means untouched, so the
template still owns it; a drift means the vault owns it and it is skipped with `~`.

Two invariants worth not breaking:

- **Notes never enter the manifest.** The updater then has no path to one at all — safe by
  construction rather than by remembering to be careful.
- **A drifted file keeps its old hash.** Re-recording it would silently hand ownership back
  and let the next update clobber the edits this one protected.

The README splice happens after `copyTree`, so the README is **re-hashed** afterwards. A
stale entry there reports an untouched README as edited.

## Testing a change

There is no test suite. Scaffold and inspect — and check the things that fail silently:

```bash
node index.js /tmp/t1 --target fly --ci github --app t --title T --repo https://example.org/r --no-cog --yes
node index.js /tmp/t2 --target gitlab --app t --title T --no-cog --yes   # no --repo
```

Then verify:

- no `__PLACEHOLDER__` survives (`grep -rn '__[A-Z_]*__'`), excluding `__VAULT_PATH__` and
  `__LINKED_REPOS__`, which `link-repo.sh` fills in later by design
- no `targets/` or `_gitignore` left in the output
- the dotfiles arrived: `.gitignore`, `.obsidian`, `.github`, `.dockerignore`
- `site/quartz.config.yaml` parses as YAML, both with and without `--repo`
- manifest hashes match the files on disk

`--no-cog` keeps test runs fast; at least one run should omit it, since COG installs 11
paths and merges into `scripts/`.

## Gotchas that have already bitten

- **`fly.toml` app vs `quartz.config.yaml` baseUrl drift.** Self-hosted fonts are rewritten
  to absolute URLs, so a mismatch 404s the fonts with no other symptom. `doctor.sh` checks
  this.
- **Caddy refuses an empty basic_auth username or password**, so a Fly app deployed before
  its secrets are set crash-loops. `entrypoint.sh` substitutes a random credential: 401 is
  right, down is not.
- **Piped `curl … | sh` cannot prompt** — stdin is the script. `index.js` checks `isTTY` and
  applies defaults rather than hanging, so `install.sh` warns when that happens without
  `--yes`.
- **`install.sh` is intentionally absent from `package.json` "files"** — npm users get
  `pnpm create`.

## Release

`CHANGELOG.md` follows Keep a Changelog; `package.json` version, the git tag and the
changelog heading must agree. Rename `[Unreleased]`, open a fresh one, update both link
refs at the bottom, tag `vX.Y.Z`, then `gh release create`.

**The npm package is not published yet** (`@awolf81/create-second-brain` 404s), so
`install.sh` is the only working install path. The README leads with it deliberately —
if you publish, that ordering and the CHANGELOG's note both need revisiting.
