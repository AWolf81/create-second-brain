#!/usr/bin/env bash
#
# Install the COG agent framework into this vault.
#
# COG — Cognition + Obsidian + Git — is a separate MIT-licensed project by
# huytieu. It is fetched from upstream rather than vendored here, so you get the
# current release, attribution stays with its authors, and COG's own
# cog-update.sh keeps working afterwards.
#
#   https://github.com/huytieu/COG-second-brain
#
# Usage: ./scripts/add-cog.sh [ref]

set -euo pipefail

REF="${1:-main}"
UPSTREAM="https://github.com/huytieu/COG-second-brain.git"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Directories COG owns. Everything else in this vault is yours.
COG_PATHS=(.claude .agents .gemini .kiro skills integrations docs scripts AGENTS.md WORKFLOW.md cog-update.sh COG-VERSION)

echo "Fetching COG ($REF) …"
git clone --depth 1 --branch "$REF" --filter=blob:none "$UPSTREAM" "$TMP/cog" >/dev/null 2>&1 \
  || git clone --depth 1 --filter=blob:none "$UPSTREAM" "$TMP/cog" >/dev/null 2>&1

installed=0
for p in "${COG_PATHS[@]}"; do
  [ -e "$TMP/cog/$p" ] || continue

  # A directory that already exists here — scripts/ does — is merged file by
  # file rather than skipped wholesale, or COG's own validators would never
  # arrive. Existing files always win: yours are not overwritten.
  if [ -d "$TMP/cog/$p" ] && [ -d "$p" ]; then
    merged=0
    while IFS= read -r f; do
      rel="${f#"$TMP/cog/$p/"}"
      if [ -e "$p/$rel" ]; then
        continue
      fi
      mkdir -p "$p/$(dirname "$rel")"
      cp "$f" "$p/$rel"
      merged=$((merged + 1))
    done < <(find "$TMP/cog/$p" -type f)

    if [ "$merged" -gt 0 ]; then
      echo "  merge $p ($merged file(s))"
      installed=$((installed + 1))
    else
      echo "  skip  $p (nothing new)"
    fi
    continue
  fi

  if [ -e "$p" ]; then
    echo "  skip  $p (already present — run COG's own cog-update.sh to update)"
    continue
  fi

  cp -r "$TMP/cog/$p" "$p"
  echo "  add   $p"
  installed=$((installed + 1))
done

# COG is MIT; keep its licence alongside the files it covers.
if [ -f "$TMP/cog/LICENSE" ] && [ ! -f COG-LICENSE ]; then
  cp "$TMP/cog/LICENSE" COG-LICENSE
  echo "  add  COG-LICENSE"
fi

echo
if [ "$installed" -eq 0 ]; then
  echo "Nothing to do — COG already installed."
else
  echo "Installed $installed COG path(s)."
  echo "Open this folder in your agent and ask it to run onboarding."
  echo
  echo "When you add a skill of your own, list it in local-skills.txt —"
  echo "COG's surface validator counts it as drift otherwise. Check with:"
  echo "  ./scripts/check-agent-surface.sh"
fi

# The site publishes an allowlist, so COG's tree never reaches it. Confirm that
# rather than assuming, because a leaked framework tree swamps the graph.
if grep -q '^\s*\.claude$\|^\s*skills$' site/build-content.sh 2>/dev/null; then
  echo "⚠ site/build-content.sh appears to publish COG paths — check its INCLUDE list." >&2
fi
