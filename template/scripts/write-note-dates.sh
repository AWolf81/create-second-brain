#!/usr/bin/env bash
#
# Record each note's real authored dates, from git, into a sidecar file.
#
# build-content.sh stamps `created:`/`modified:` onto the staged copy so Quartz
# does not date the whole vault to the moment it was built. It reads those dates
# straight from git when it can — but on the Fly target it cannot: the image is
# built from `COPY . /src`, and `.dockerignore` excludes `.git` (deliberately,
# since shipping history into an image layer is waste and leak both). Inside the
# build there is no repository to ask.
#
# So the dates are resolved *here*, in CI, where history exists, and written to
# a file that does get copied in. build-content.sh prefers live git and falls
# back to this. Where neither exists it writes no dates at all, rather than
# stamping filesystem mtime — which on a fresh clone is the deploy time for
# every file, the exact wrong answer this all exists to avoid.
#
# Committing the sidecar is not required and not recommended: it is derived
# data, it changes on every commit that touches a note, and it would conflict
# constantly. Generate it in CI.
#
# Usage: ./scripts/write-note-dates.sh [output-path]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT="${1:-.note-dates.tsv}"

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "write-note-dates: not a git repository; nothing to record." >&2
  exit 0
}

if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "write-note-dates: shallow clone — every note would date to the same" >&2
  echo "  commit. Refusing to write misleading dates. Use fetch-depth: 0" >&2
  echo "  (GitHub) or GIT_DEPTH: 0 (GitLab)." >&2
  exit 0
fi

# Only the folders the site publishes; see INCLUDE in build-content.sh.
count=0
: > "$OUT"
while IFS= read -r f; do
  created="$(git log --diff-filter=A --format=%aI -1 -- "$f" 2>/dev/null || true)"
  modified="$(git log --format=%aI -1 -- "$f" 2>/dev/null || true)"
  # A note added but not yet committed has no dates. Skip it rather than
  # inventing one; build-content.sh simply writes no frontmatter for it.
  [ -n "$created" ] && [ -n "$modified" ] || continue
  printf '%s\t%s\t%s\n' "$f" "$created" "$modified" >> "$OUT"
  count=$((count + 1))
done < <(find 04-projects 05-knowledge -name '*.md' -type f 2>/dev/null | sed 's#^\./##' | sort)

echo "write-note-dates: recorded $count note date(s) into $OUT"
