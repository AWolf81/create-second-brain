#!/usr/bin/env bash
#
# Link a work repository to this vault.
#
# Nothing is written into the work repository — not a file, not a commit, not a
# gitignore line. Committed wiring rides every branch, lands in every PR diff and
# becomes a merge-conflict surface on long-lived branches. Everything goes to
# ~/.claude instead, which is machine-local and outside every repo.
#
# What this does write:
#   this vault      04-projects/<name>/README.md with `repo:` frontmatter — the
#                   durable, machine-independent half. Committed.
#   ~/.claude       the second-brain skill, and a marked block naming the vault's
#                   path on this machine and every repo linked to it — the
#                   machine-specific half. Never committed.
#
# The list of linked repos is derived from 04-projects/*/README.md rather than
# kept in a separate file, so there is nothing to drift.
#
# Usage:
#   ./scripts/link-repo.sh <path-or-url> [--name <slug>]
#   ./scripts/link-repo.sh --list
#   ./scripts/link-repo.sh --unlink <slug>

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MEMORY="$CLAUDE_DIR/CLAUDE.md"
SKILL_DIR="$CLAUDE_DIR/skills/second-brain"
BEGIN="<!-- second-brain:begin -->"
END="<!-- second-brain:end -->"

die() { echo "✗ $*" >&2; exit 1; }

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's#.*/##; s#\.git$##; s#[^a-z0-9-]+#-#g; s#^-+|-+$##g'; }

# Every linked repo, read back out of the project pages.
list_links() {
  local f name repo
  for f in 04-projects/*/README.md; do
    [ -e "$f" ] || continue
    head -1 "$f" | grep -q '^---$' || continue
    repo="$(sed -n '2,/^---$/p' "$f" | sed -nE 's/^repo: *(.*)/\1/p' | head -1)"
    [ -n "$repo" ] || continue
    name="$(basename "$(dirname "$f")")"
    printf '%s\t%s\n' "$name" "$repo"
  done
}

if [ "${1:-}" = "--list" ]; then
  links="$(list_links)"
  if [ -z "$links" ]; then
    echo "No linked repositories yet. Link one with: ./scripts/link-repo.sh <path-or-url>"
  else
    echo "Linked repositories:"
    while IFS=$'\t' read -r name repo; do printf '  %-24s %s\n' "$name" "$repo"; done <<<"$links"
  fi
  exit 0
fi

# Rewrite the marked block in user memory from whatever is linked right now, so
# the block is a projection of the vault rather than an append-only log.
sync_memory() {
  local tmp block links name repo
  links="$(list_links)"
  mkdir -p "$CLAUDE_DIR"
  [ -f "$MEMORY" ] || : > "$MEMORY"

  block="$BEGIN
## Knowledge vault

A companion knowledge vault holds durable, cross-project knowledge, at \`$ROOT_DIR\`.
Skill: \`second-brain\`.

**Read it before answering** anything about strategy, pricing, compliance, legal or tax
setup, launch, positioning, or a past architectural decision. Start at
\`$ROOT_DIR/05-knowledge/README.md\`. The vault records decisions **and what they were
decided against**; if it is silent, say so rather than answering from general knowledge.
Always read it at \`main\`.

**Never write vault wiring into a work repo.** No block in its \`CLAUDE.md\`, no skill in
its \`.claude/skills/\`, no hook, no gitignore entry. That is why this lives here.

Linked repositories:
"
  if [ -z "$links" ]; then
    block="$block
- none yet
"
  else
    while IFS=$'\t' read -r name repo; do
      block="$block
- \`$name\` — $repo"
    done <<<"$links"
    block="$block
"
  fi
  block="$block$END"

  tmp="$(mktemp)"
  if grep -qF "$BEGIN" "$MEMORY"; then
    awk -v b="$BEGIN" -v e="$END" -v new="$block" '
      index($0, b) { print new; skip = 1; next }
      index($0, e) { skip = 0; next }
      !skip { print }
    ' "$MEMORY" > "$tmp"
  else
    cat "$MEMORY" > "$tmp"
    [ -s "$tmp" ] && printf '\n' >> "$tmp"
    printf '%s\n' "$block" >> "$tmp"
  fi
  mv "$tmp" "$MEMORY"
}

# Install the bridge skill, with this vault's path and links baked in.
sync_skill() {
  local src=integrations/second-brain.skill.md links rendered name repo
  [ -f "$src" ] || die "$src is missing — is this a vault created by create-second-brain?"

  links="$(list_links)"
  if [ -z "$links" ]; then
    rendered="- none yet"
  else
    rendered=""
    while IFS=$'\t' read -r name repo; do
      rendered="$rendered- \`$name\` — $repo
"
    done <<<"$links"
  fi

  mkdir -p "$SKILL_DIR"
  awk -v vault="$ROOT_DIR" -v links="$rendered" '
    { gsub(/__VAULT_PATH__/, vault); gsub(/__LINKED_REPOS__/, links); print }
  ' "$src" > "$SKILL_DIR/SKILL.md"
}

# Removing the only key leaves a `---\n---` husk, which Obsidian and Quartz both
# render as an empty properties block. Drop the whole thing instead.
#
# The emptiness test is awk rather than the obvious `sed -n '2,/^---$/p'`: a sed
# range never matches its end address on the line that opened it, so a block whose
# second line is already the closing `---` reads as the whole rest of the file —
# the husk case, and precisely the one being looked for.
strip_empty_frontmatter() {
  local f="$1" tmp
  awk '
    NR == 1        { if ($0 != "---") exit 1; next }
    $0 == "---"    { empty = 1; exit }
    /[^[:space:]]/ { exit 1 }
    END            { exit empty ? 0 : 1 }
  ' "$f" || return 0

  tmp="$(mktemp)"
  awk '
    NR == 1                                    { next }
    !closed && $0 == "---"                     { closed = 1; next }
    !closed                                    { next }
    !started && $0 ~ /^[[:space:]]*$/          { next }
    { started = 1; print }
  ' "$f" > "$tmp"
  mv "$tmp" "$f"
}

if [ "${1:-}" = "--unlink" ]; then
  UNLINK="${2:-}"
  [ -n "$UNLINK" ] || die "usage: link-repo.sh --unlink <slug>"
  page="04-projects/$UNLINK/README.md"
  [ -f "$page" ] || die "no linked repo called '$UNLINK' — see --list"
  # Drop only the link, not the project page: the notes stay, the wiring goes.
  tmp="$(mktemp)"
  sed -E '/^repo: /d' "$page" > "$tmp" && mv "$tmp" "$page"
  strip_empty_frontmatter "$page"
  sync_skill; sync_memory
  echo "✓ unlinked '$UNLINK'. Its project page is kept; only the repo link was removed."
  exit 0
fi

TARGET="${1:-}"
[ -n "$TARGET" ] ||
  die "usage: link-repo.sh <path-or-url> [--name <slug>] | --list | --unlink <slug>"
NAME=""
if [ "${2:-}" = "--name" ]; then
  NAME="${3:-}"
  [ -n "$NAME" ] || die "--name needs a value"
fi

# A path or a URL. A path is resolved to its origin remote so the vault records
# something machine-independent.
#
# The vault refuses to link itself, and that check runs *before* the remote
# lookup. The other way round, pointing the script at the vault reports "has no
# 'origin' remote" whenever the vault has not been pushed yet — a true statement
# about the wrong problem.
LOCAL_PATH=""
if [ -d "$TARGET" ]; then
  LOCAL_PATH="$(cd "$TARGET" && pwd)"
  [ "$LOCAL_PATH" = "$ROOT_DIR" ] &&
    die "that is this vault — link a work repo, not the vault itself"
  REPO_URL="$(git -C "$LOCAL_PATH" remote get-url origin 2>/dev/null || true)"
  [ -n "$REPO_URL" ] || die "$LOCAL_PATH has no 'origin' remote — pass the URL instead"
else
  REPO_URL="$TARGET"
fi

# Same refusal for the URL form, and for a path whose origin is the vault.
case "$REPO_URL" in
  *"$ROOT_DIR"*) die "that is this vault — link a work repo, not the vault itself" ;;
esac

[ -n "$NAME" ] || NAME="$(slugify "$REPO_URL")"
[ -n "$NAME" ] || die "could not derive a name — pass --name"

PAGE="04-projects/$NAME/README.md"
mkdir -p "04-projects/$NAME"

if [ -f "$PAGE" ]; then
  if head -1 "$PAGE" | grep -q '^---$' && sed -n '2,/^---$/p' "$PAGE" | grep -q '^repo:'; then
    tmp="$(mktemp)"
    sed -E "s#^repo: .*#repo: $REPO_URL#" "$PAGE" > "$tmp" && mv "$tmp" "$PAGE"
  elif head -1 "$PAGE" | grep -q '^---$'; then
    tmp="$(mktemp)"
    awk -v r="repo: $REPO_URL" 'NR==1{print; print r; next} {print}' "$PAGE" > "$tmp" && mv "$tmp" "$PAGE"
  else
    tmp="$(mktemp)"
    { printf -- '---\nrepo: %s\n---\n\n' "$REPO_URL"; cat "$PAGE"; } > "$tmp" && mv "$tmp" "$PAGE"
  fi
  echo "  updated $PAGE"
else
  cat > "$PAGE" <<PAGE_EOF
---
repo: $REPO_URL
---

# $NAME — project index

> **Orientation only.** Plans and code live in the repo; transferable lessons live in
> \`05-knowledge/\`. This page exists so a cold session knows what this is and where
> everything actually is.

## What it is

_One paragraph. What does this project do, and for whom?_

## Where things live

| Thing | Location |
|---|---|
| Code, issues, plans | $REPO_URL |
| Transferable lessons | [\`05-knowledge/\`](../../05-knowledge/README.md) |

## Status

_What is true right now, and what is next._

## Knowledge harvested from this project

_Links to notes in \`05-knowledge/\` that came out of this work._
PAGE_EOF
  echo "  created $PAGE"
fi

sync_skill
sync_memory

echo
echo "✓ linked '$NAME' → $REPO_URL"
echo
echo "  vault      $PAGE  (commit this)"
echo "  user       $SKILL_DIR/SKILL.md"
echo "  user       $MEMORY  (second-brain block)"
[ -n "$LOCAL_PATH" ] && echo "  work repo  $LOCAL_PATH — untouched, by design"
echo
echo "Open the work repo in your agent; the vault is now in its user memory every session."
