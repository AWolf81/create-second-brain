#!/usr/bin/env bash
#
# Record that an agent actually opened the vault.
#
# The bridge skill *asserts* that agents read the vault before answering. Nothing
# anywhere checked whether that happens, which is the same shape as a metric whose
# numerator is structurally zero: the claim looks like coverage while being
# unfalsifiable. This makes it observable — the harness reports the read, not the
# model.
#
# Installed by link-repo.sh as a PostToolUse hook on Read|Grep|Glob. Receives the
# hook payload as JSON on stdin.
#
# What it records: a timestamp, the session, the tool, and the vault-relative path.
# Not the content, not the question, not anything from outside the vault. The ledger
# is machine-local (next to this script, under the user config dir) and never
# committed.

set -uo pipefail

VAULT="__VAULT_PATH__"
LEDGER="${VAULT_USAGE_LEDGER:-__LEDGER_PATH__}"
ERRLOG="$LEDGER.err"

# A hook must never break the session it observes. Every path below exits 0; real
# problems go to the sidecar log, which doctor.sh surfaces. Failing silently and
# failing loudly are both wrong — this fails quietly *and leaves evidence*.
note_error() {
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$ERRLOG" 2>/dev/null
  exit 0
}

command -v jq >/dev/null 2>&1 || note_error "jq not installed — vault reads are not being recorded"

payload="$(cat)"
[ -n "$payload" ] || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)" || note_error "unparseable payload"
session="$(jq -r '.session_id // "unknown"' <<<"$payload" 2>/dev/null)"

# Read carries file_path; Grep and Glob carry the directory they searched. A grep
# across the vault is a consult even when no single note is opened.
target="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<<"$payload" 2>/dev/null)"
[ -n "$target" ] || exit 0

# Resolve before comparing: a relative path or a symlinked home would otherwise
# read as "not the vault" and undercount every hit.
abs="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")" || exit 0
vault_abs="$(cd "$VAULT" 2>/dev/null && pwd -P)" || note_error "vault path $VAULT does not resolve"

case "$abs" in
  "$vault_abs"/*) rel="${abs#"$vault_abs"/}" ;;
  "$vault_abs")   rel="." ;;
  *)              exit 0 ;;
esac

mkdir -p "$(dirname "$LEDGER")" 2>/dev/null
printf '%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$session" "$tool" "$rel" >> "$LEDGER" 2>/dev/null ||
  note_error "cannot write ledger at $LEDGER"

exit 0
