#!/usr/bin/env bash
#
# Run COG's agent-surface validator and reconcile the difference a vault of your
# own creates: local skills that are deliberately not in COG's redistributable
# plugin manifests (see local-skills.txt).
#
# Does nothing until COG is installed.
#
# Why a wrapper rather than a patch: validate-agent-surface.sh is a COG
# framework file and cog-update.sh replaces it. This script and local-skills.txt
# are mine, so the reconciliation survives an update.
#
# The point is that a surface check should be expected to pass. A validator with
# a permanently red result is one nobody reads, which is how a real regression
# gets missed.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UPSTREAM=scripts/validate-agent-surface.sh
DECLARED=local-skills.txt

if [ ! -x "$UPSTREAM" ]; then
  echo "– COG is not installed, so there is no agent surface to check."
  echo "  Run ./scripts/add-cog.sh if you want the agent skills."
  exit 0
fi

# add-cog.sh installs COG's skills, not its plugin manifests — those describe
# COG's redistributable plugin, which your vault is not. Without them there is
# no declared surface to drift from, so there is nothing to reconcile.
#
# This check only becomes meaningful if you fork COG rather than install it, or
# publish a plugin manifest of your own.
if [ ! -f .claude-plugin/plugin.json ]; then
  echo "– COG is installed but its plugin manifests are not, so there is no"
  echo "  declared surface to check against. Nothing to reconcile."
  exit 0
fi

# What is on disk but not in the manifest, and what did we declare?
mapfile -t undeclared < <(python3 - <<'PY'
import json, pathlib
try:
    manifest = json.load(open('.claude-plugin/plugin.json'))
except Exception:
    raise SystemExit(0)
names = {s['name'] if isinstance(s, dict) else s for s in manifest.get('skills', [])}
disk = {p.parent.name for p in pathlib.Path('.claude/skills').glob('*/SKILL.md')}
declared = set()
try:
    for line in open('local-skills.txt'):
        line = line.split('#', 1)[0].strip()
        if line:
            declared.add(line)
except FileNotFoundError:
    pass
for name in sorted((disk - names) - declared):
    print(f"undeclared\t{name}")
for name in sorted(declared - disk):
    print(f"stale\t{name}")
PY
)

status=0

for entry in "${undeclared[@]}"; do
  [ -z "$entry" ] && continue
  kind="${entry%%	*}"; name="${entry##*	}"
  if [ "$kind" = "undeclared" ]; then
    echo "✗ skill '$name' is on disk but in neither the manifest nor $DECLARED" >&2
    status=1
  else
    echo "✗ $DECLARED lists '$name' but no such skill exists — stale entry" >&2
    status=1
  fi
done

output="$("$UPSTREAM" 2>&1)"
upstream_status=$?

# The count mismatch is explained exactly when every disk skill is either in the
# manifest or declared local. Any other failure passes straight through.
mismatch=$(grep -c 'Plugin manifest declares .* skills but' <<<"$output" || true)
# Take the error count from the validator's own summary rather than counting ✗
# lines — the summary line carries one too, which would double-count.
total=$(sed -nE 's/.*Validation failed with ([0-9]+) error.*/\1/p' <<<"$output" | head -1)
total="${total:-0}"

if [ "$upstream_status" -eq 0 ]; then
  echo "$output"
elif [ "$mismatch" -eq 1 ] && [ "$total" -eq 1 ] && [ "$status" -eq 0 ]; then
  grep -v 'Plugin manifest declares .* skills but' <<<"$output" \
    | grep -v 'Validation failed with'
  echo "✓ manifest/disk delta is exactly the $(grep -cvE '^\s*(#|$)' "$DECLARED") declared local skill(s) — reconciled"
  echo "✓ agent surface OK"
else
  echo "$output"
  status=1
fi

exit "$status"
