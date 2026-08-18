#!/usr/bin/env bash
#
# Every published note must have a title source, or it falls back to its
# filename on the site — which is how three separate notes ended up labelled
# "README" in the graph.
#
# A note passes if it has either:
#   - `title:` in its frontmatter (an explicit override), or
#   - a `# H1` (site/build-content.sh derives the title from it)
#
# Run from the repository root. Called by .github/workflows/deploy-site.yml,
# so a note without a title source fails the deploy rather than quietly
# regressing a label.

set -euo pipefail

# Keep in step with INCLUDE in site/build-content.sh.
DIRS=(04-projects 05-knowledge)

offenders=()
checked=0

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || continue
  while IFS= read -r file; do
    checked=$((checked + 1))

    if head -1 "$file" | grep -q '^---$' &&
       sed -n '2,/^---$/p' "$file" | grep -qE '^title:'; then
      continue
    fi

    grep -qm1 '^# ' "$file" && continue

    offenders+=("$file")
  done < <(find "$dir" -name '*.md' -type f)
done

if [ ${#offenders[@]} -gt 0 ]; then
  echo "✗ ${#offenders[@]} note(s) have no title source (no frontmatter title, no '# H1'):" >&2
  printf '    %s\n' "${offenders[@]}" >&2
  echo >&2
  echo "  Add a '# Heading' to the note, or a 'title:' frontmatter key to override it." >&2
  exit 1
fi

echo "✓ all $checked published notes have a title source"
