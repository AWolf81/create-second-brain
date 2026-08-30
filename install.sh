#!/usr/bin/env bash
#
# Scaffold a vault without npm.
#
#   curl -fsSL https://raw.githubusercontent.com/AWolf81/create-second-brain/main/install.sh | sh -s -- my-brain --target fly
#
# Piped that way stdin is the script, not a terminal, so the prompts are skipped
# and defaults apply — pass the flags you care about, or download and run the
# file directly to answer interactively.
#
# Equivalent to `pnpm create @awolf81/second-brain`, and takes the same flags —
# it fetches this repository to a temporary directory and runs the real
# scaffolder from it. That matters: index.js resolves template/ relative to
# itself, so running it in place is what makes --target, --ci, --app, --title
# and --repo behave identically to the npm path.
#
# This exists because copying template/ out of the repo directly (with degit or
# a tarball) does NOT produce a working vault. The scaffolder is what picks one
# targets/ directory and lifts it to the root, restores the underscore-prefixed
# files (_gitignore -> .gitignore, _obsidian -> .obsidian), splices the target's
# setup into the README, and substitutes every __PLACEHOLDER__. A raw copy
# leaves `baseUrl: __BASE_URL__` in the Quartz config and no Dockerfile, no
# fly.toml, no CI workflow.
#
# Needs: bash, git, node >= 18. No npm, no network access to a registry.
#
# Usage:
#   ./install.sh <dir> [scaffolder flags…]
#   ./install.sh my-brain --target fly --ci github --repo https://github.com/me/my-brain

set -euo pipefail

REPO="${CSB_REPO:-https://github.com/AWolf81/create-second-brain.git}"
REF="${CSB_REF:-main}"

die() { echo "✗ $*" >&2; exit 1; }

[ $# -gt 0 ] || die "usage: install.sh <dir> [--target fly|gitlab] [--ci github|gitlab] [--app name] [--title \"…\"] [--repo url]"

command -v git >/dev/null 2>&1 || die "git is required."
command -v node >/dev/null 2>&1 || die "node >= 18 is required."

# The scaffolder uses readline/promises and top-level await.
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "node >= 18 is required (found $(node -v))."

# Resolve the destination before cd-ing anywhere, so a relative path is taken
# against the caller's directory rather than the checkout's.
DEST="$1"; shift
case "$DEST" in
  -*) die "first argument must be the target directory, not a flag." ;;
esac
mkdir -p "$(dirname "$DEST")"
DEST="$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")"

[ ! -e "$DEST" ] || [ -z "$(ls -A "$DEST" 2>/dev/null)" ] \
  || die "$DEST already exists and is not empty."

# Piped into a shell (curl … | sh), stdin is the script, so the scaffolder's
# prompts cannot read a reply. It checks isTTY and silently falls back to
# defaults rather than hanging — which means a piped run without --yes quietly
# produces a vault named "Second Brain" that nobody chose. Say so, once.
if [ ! -t 0 ]; then
  case " $* " in
    *" --yes "*) ;;
    *) echo "! Piped into a shell, so the prompts are skipped and defaults apply." >&2
       echo "  Pass --app/--title/--target/--repo explicitly, or download and run the" >&2
       echo "  script directly to answer them interactively." >&2 ;;
  esac
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Fetching create-second-brain ($REF) …"
git clone --quiet --depth 1 --branch "$REF" "$REPO" "$TMP/src" \
  || die "could not clone $REPO at $REF."

exec node "$TMP/src/index.js" "$DEST" "$@"
