#!/usr/bin/env bash
#
# What the agents actually read.
#
# Reports the ledger written by the vault-read-logger hook. Three questions:
#
#   Is the vault being consulted at all?   — an empty ledger is the answer that matters
#   Which notes carry the weight?          — reads per note
#   Which notes has nothing ever opened?   — the dead weight, and the more useful half
#
# Never-read notes are not automatically bad. A note nothing has opened in months is
# either a question that stopped being asked, or one the router fails to route — and
# those need opposite fixes. The report names them; deciding which is yours.
#
# Usage: ./scripts/vault-usage.sh [--since YYYY-MM-DD]

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LEDGER="${VAULT_USAGE_LEDGER:-$CLAUDE_DIR/vault-usage.tsv}"
SINCE=""

[ "${1:-}" = "--since" ] && SINCE="${2:?--since needs a date, e.g. 2026-08-01}"

if [ ! -s "$LEDGER" ]; then
  echo "No evidence the vault has ever been read."
  echo
  if [ ! -f "$LEDGER" ]; then
    echo "  There is no ledger at $LEDGER."
    echo "  Either no agent session has opened a note yet, or the hook is not installed."
    echo "  Run ./scripts/doctor.sh — it checks the hook registration."
  else
    echo "  The ledger exists but is empty: the hook is installed and has never matched."
  fi
  exit 0
fi

rows="$(cat "$LEDGER")"
[ -n "$SINCE" ] && rows="$(awk -v s="$SINCE" '$1 >= s' <<<"$rows")"

if [ -z "$rows" ]; then
  echo "No vault reads recorded since $SINCE."
  exit 0
fi

total="$(wc -l <<<"$rows" | tr -d ' ')"
sessions="$(cut -f2 <<<"$rows" | sort -u | wc -l | tr -d ' ')"
first="$(cut -f1 <<<"$rows" | sort | head -1)"
last="$(cut -f1 <<<"$rows" | sort | tail -1)"

plural() { [ "$1" -eq 1 ] && printf '%s %s' "$1" "$2" || printf '%s %ss' "$1" "$2"; }

echo "Vault reads${SINCE:+ since $SINCE}"
echo "  $(plural "$total" read) across $(plural "$sessions" session)"
echo "  first $first"
echo "  last  $last"
echo
echo "Most read"
cut -f4 <<<"$rows" | sort | uniq -c | sort -rn | head -15 |
  while read -r n p; do printf '  %5s  %s\n' "$n" "$p"; done

# The universe is what a reader could have opened: the knowledge notes and the
# project pages. Anything outside those is machinery, not knowledge.
echo
echo "Never read"
readset="$(cut -f4 <<<"$rows" | sort -u)"
unread=0
while IFS= read -r f; do
  grep -qxF "$f" <<<"$readset" || { printf '  %s\n' "$f"; unread=$((unread + 1)); }
done < <(find 05-knowledge 04-projects -name '*.md' -type f 2>/dev/null | sed 's#^\./##' | sort)
[ "$unread" -eq 0 ] && echo "  (nothing — every note has been opened at least once)"

if [ -s "$LEDGER.err" ]; then
  echo
  echo "Hook errors — reads may be undercounted"
  tail -5 "$LEDGER.err" | sed 's/^/  /'
fi
