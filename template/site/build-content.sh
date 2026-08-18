#!/usr/bin/env bash
#
# Stage vault content into Quartz's content/ directory.
#
# Two jobs:
#   1. Allowlist which vault folders reach the site.
#   2. Give every staged note a `title:`, derived from its `# H1` when it has
#      none of its own.
#
# Both operate on the *copy*. Vault files are never modified, so no note has to
# carry site-specific frontmatter and nobody has to remember to add it.
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

rm -rf "$DEST"
mkdir -p "$DEST"

for dir in "${INCLUDE[@]}"; do
  if [ -d "$SRC/$dir" ]; then
    cp -r "$SRC/$dir" "$DEST/"
  fi
done

cp "$SRC/site/index.md" "$DEST/index.md"

while IFS= read -r file; do
  apply_title "$file"
done < <(find "$DEST" -name '*.md' -type f)

count=$(find "$DEST" -name '*.md' -type f | wc -l)
echo "build-content: staged $count markdown files into $DEST"

# An empty content tree builds a valid, empty site. That is worse than a failed
# build, because it silently replaces a working deploy with nothing.
if [ "$count" -le 1 ]; then
  echo "build-content: only the index page was staged — refusing to publish an empty site" >&2
  exit 1
fi
