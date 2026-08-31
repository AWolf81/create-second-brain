#!/usr/bin/env bash
#
# Stage vault content into Quartz's content/ directory.
#
# Three jobs:
#   1. Allowlist which vault folders reach the site.
#   2. Give every staged note a `title:`, derived from its `# H1` when it has
#      none of its own.
#   3. Give every staged note `created:` and `modified:`, derived from git.
#
# All three operate on the *copy*. Vault files are never modified, so no note
# has to carry site-specific frontmatter and nobody has to remember to add it.
#
# Why dates need doing at all: Quartz falls back to filesystem mtime, and mtime
# is meaningless for a vault. A fresh clone stamps every file with the clone
# time, so a CI build dates the whole vault to the deploy — twelve notes written
# over six weeks all claiming the same afternoon. git is the only place the real
# dates survive, and content/ is a copy with no history of its own, so the dates
# are read here from the source repo and written into the copy as frontmatter.
#
# Usage: build-content.sh <vault-root> <content-dir>

set -euo pipefail

SRC="${1:?usage: build-content.sh <vault-root> <content-dir>}"
DEST="${2:?usage: build-content.sh <vault-root> <content-dir>}"

# Published directories. This is an allowlist, so a folder that is not named
# here never reaches the site — a new folder is private by default rather than
# published by accident. Add folders deliberately.
INCLUDE=(
  04-projects
  05-knowledge
)

# Longest label kept intact. Beyond this a title is cut at a word boundary,
# because graph labels do not wrap and long ones overlap their neighbours.
TITLE_MAX="${TITLE_MAX:-32}"

# Does the file already declare its own title? Frontmatter always wins — it is
# the escape hatch for anything the heuristic gets wrong.
has_frontmatter_title() {
  head -1 "$1" | grep -q '^---$' &&
    sed -n '2,/^---$/p' "$1" | grep -qE '^title:'
}

has_frontmatter() {
  head -1 "$1" | grep -q '^---$'
}

# Turn a heading into a label that reads well in a graph node.
#
# Headings in this vault are shaped "Topic — qualifier" or "Topic, aspect, and
# aspect", where everything before the first separator is the actual subject.
# Cutting there is what turns "Metrics, activation, and instrumentation" into
# "Metrics" rather than truncating it mid-word.
shorten_title() {
  local t="$1"

  # Cut at the first strong separator: em dash, en dash, colon, or comma.
  t="$(printf '%s' "$t" | sed -E 's/ (—|–) .*//; s/: .*//; s/, .*//')"

  # Anything still too long loses whole trailing words rather than characters.
  if [ "${#t}" -gt "$TITLE_MAX" ]; then
    t="$(printf '%s' "$t" | cut -c "1-$TITLE_MAX" | sed -E 's/[[:space:]]+[^[:space:]]*$//')…"
  fi

  printf '%s' "$t"
}

yaml_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Give one staged file a title, if it does not already have one.
apply_title() {
  local file="$1" h1 title escaped tmp

  has_frontmatter_title "$file" && return 0

  h1="$(grep -m1 '^# ' "$file" | sed -E 's/^# +//' || true)"
  [ -n "$h1" ] || return 0

  title="$(shorten_title "$h1")"
  escaped="$(yaml_escape "$title")"
  tmp="$file.tmp"

  if has_frontmatter "$file"; then
    # Insert into the existing block rather than opening a second one.
    awk -v t="title: \"$escaped\"" 'NR==1{print; print t; next} {print}' "$file" > "$tmp"
  else
    { printf -- '---\ntitle: "%s"\n---\n\n' "$escaped"; cat "$file"; } > "$tmp"
  fi

  mv "$tmp" "$file"
}

# Is there real history to read? A shallow clone — actions/checkout's default —
# has exactly one commit, so every note's "first commit" is that commit and the
# dates would be uniformly wrong in a new way. Better to write nothing and let
# Quartz fall back than to stamp a confident lie on every page.
HAVE_GIT_DATES=0
DATE_SIDECAR="$SRC/.note-dates.tsv"

if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 &&
   [ "$(git -C "$SRC" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]; then
  HAVE_GIT_DATES=1
elif [ -s "$DATE_SIDECAR" ]; then
  # No usable history here — the Fly image is built with .git excluded — so use
  # the sidecar CI resolved before the build. See scripts/write-note-dates.sh.
  echo "build-content: using dates from $(basename "$DATE_SIDECAR")." >&2
else
  echo "build-content: no git history and no .note-dates.tsv — dates omitted," >&2
  echo "  so Quartz will fall back to filesystem mtime (the build time). Run" >&2
  echo "  ./scripts/write-note-dates.sh in CI before building." >&2
fi

# Stamp a staged note with the dates its source file actually has in git.
#
# created  = the commit that first introduced the path
# modified = the commit that last touched it
#
# Both are read from SRC, where history lives, and written into DEST, which has
# none. Frontmatter already present always wins, same rule as the title.
apply_dates() {
  local file="$1" rel created modified tmp row

  rel="${file#"$DEST"/}"
  # index.md is generated, not a vault note, so it has no source to date.
  [ -f "$SRC/$rel" ] || return 0

  if [ "$HAVE_GIT_DATES" = 1 ]; then
    # --diff-filter=A finds the commit that added the path. A file that was
    # renamed reports its rename as the creation; --follow would trace further,
    # but it cannot be combined with a reliable date-only format across git
    # versions, and a rename is a defensible "created here" for a note.
    created="$(git -C "$SRC" log --diff-filter=A --format=%aI -1 -- "$rel" 2>/dev/null)"
    modified="$(git -C "$SRC" log --format=%aI -1 -- "$rel" 2>/dev/null)"
  elif [ -s "$DATE_SIDECAR" ]; then
    row="$(awk -F'\t' -v p="$rel" '$1 == p { print; exit }' "$DATE_SIDECAR")"
    created="$(printf '%s' "$row" | cut -f2)"
    modified="$(printf '%s' "$row" | cut -f3)"
  else
    return 0
  fi

  # Untracked or never-committed: no dates rather than invented ones.
  [ -n "$created" ] && [ -n "$modified" ] || return 0

  tmp="$file.tmp"
  if has_frontmatter "$file"; then
    awk -v c="created: $created" -v m="modified: $modified" '
      NR==1 { print; next }
      # Only inside the opening block, and never clobbering an existing key.
      !done && /^---$/ { if (!seen_c) print c; if (!seen_m) print m; done=1; print; next }
      !done && /^created:/  { seen_c=1 }
      !done && /^modified:/ { seen_m=1 }
      { print }
    ' "$file" > "$tmp"
  else
    { printf -- '---\ncreated: %s\nmodified: %s\n---\n\n' "$created" "$modified"; cat "$file"; } > "$tmp"
  fi
  mv "$tmp" "$file"
}

rm -rf "$DEST"
mkdir -p "$DEST"

for dir in "${INCLUDE[@]}"; do
  if [ -d "$SRC/$dir" ]; then
    cp -r "$SRC/$dir" "$DEST/"
  fi
done

cp "$SRC/site/index.md" "$DEST/index.md"

while IFS= read -r file; do
  # Title first: it may open the frontmatter block that apply_dates then writes
  # into, which keeps every staged note to a single block.
  apply_title "$file"
  apply_dates "$file"
done < <(find "$DEST" -name '*.md' -type f)

count=$(find "$DEST" -name '*.md' -type f | wc -l)
echo "build-content: staged $count markdown files into $DEST"

# An empty content tree builds a valid, empty site. That is worse than a failed
# build, because it silently replaces a working deploy with nothing.
if [ "$count" -le 1 ]; then
  echo "build-content: only the index page was staged — refusing to publish an empty site" >&2
  exit 1
fi
