#!/usr/bin/env bash
#
# Publish what Syncthing brought in: commit it, take what other machines pushed,
# push. The push is what triggers the site deploy.
#
# Run this on the hub only — the one machine in the Syncthing cluster that has a
# git clone. Every other synced device carries notes and never .git (.stignore
# keeps it out of the sync), so each working tree has exactly one git writer.
# Syncing .git between machines is how repositories get corrupted.
#
# Machines that use git directly keep committing and pushing as before. Each
# pass also takes their commits, and Syncthing hands those on to the phone.
#
# One-shot by design: a scheduler runs it every few minutes, and a pass that
# finds the vault still settling just exits and waits for the next one.
#
# Usage:
#   ./scripts/autopublish.sh               one pass
#   ./scripts/autopublish.sh --dry-run     what a pass would do, changing nothing
#   ./scripts/autopublish.sh --install     Linux: a systemd user timer, every 5 min
#   ./scripts/autopublish.sh --uninstall   remove that timer
#
# Synology NAS: Control Panel → Task Scheduler → Create → Scheduled Task →
# User-defined script, as the user that owns the clone, repeating every 5
# minutes:
#   bash /volume1/<share>/<vault>/scripts/autopublish.sh
# Tick "send run details only when the script terminates abnormally" — that is
# the failure alert.
#
# cron: */5 * * * * bash /path/to/vault/scripts/autopublish.sh
#
# Exit 0: published, or nothing to do yet. Exit 1: needs a person.
#
# Environment:
#   AUTOPUBLISH_QUIET_MIN     minutes without a change before publishing (3)
#   AUTOPUBLISH_MAX_DELETES   refuse a pass deleting more files than this (20)
#   AUTOPUBLISH_REMOTE        remote to sync with (origin)

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

QUIET_MIN="${AUTOPUBLISH_QUIET_MIN:-3}"
MAX_DELETES="${AUTOPUBLISH_MAX_DELETES:-20}"
REMOTE="${AUTOPUBLISH_REMOTE:-origin}"
UNIT=vault-autopublish
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

die() { printf '✗ %b\n' "$1" >&2; exit 1; }

install_timer() {
  command -v systemctl >/dev/null || die "no systemctl — use cron or your NAS's task scheduler (see the header of this script)"
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/$UNIT.service" <<EOF
[Unit]
Description=Publish synced vault changes ($ROOT_DIR)

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "$ROOT_DIR/scripts/autopublish.sh"
EOF
  cat > "$UNIT_DIR/$UNIT.timer" <<EOF
[Unit]
Description=Publish synced vault changes every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT.timer"
  echo "✓ $UNIT.timer installed. Logs: journalctl --user -u $UNIT"
  echo "  The push runs unattended, so its SSH key must not need a passphrase prompt."
  echo "  To run while logged out: loginctl enable-linger \"\$USER\""
  exit 0
}

uninstall_timer() {
  systemctl --user disable --now "$UNIT.timer" 2>/dev/null || true
  rm -f "$UNIT_DIR/$UNIT.service" "$UNIT_DIR/$UNIT.timer"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "✓ $UNIT.timer removed"
  exit 0
}

MODE=run
case "${1:-}" in
  "")          ;;
  --dry-run)   MODE=dry ;;
  --install)   install_timer ;;
  --uninstall) uninstall_timer ;;
  -h|--help)   sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)           die "unknown argument: $1" ;;
esac

# Everything in the vault except .git, which belongs to this script alone.
in_tree() { find . -path ./.git -prune -o "$@" -print; }

[ -d .git ] || die "no .git here — run this on the hub, the one synced machine with a clone"
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)" || die "HEAD is detached — check out the branch to publish"
[ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] && die "a rebase is in progress — finish or abort it first"

# One pass at a time, so a slow push never overlaps the next tick. A lock left
# by a killed pass would otherwise skip every pass after it, silently.
LOCK=.git/autopublish.lock
[ -n "$(find .git -maxdepth 1 -name autopublish.lock -mmin +30 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
mkdir "$LOCK" 2>/dev/null || { echo "another pass is running"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# A conflict copy means two devices edited the same note and Syncthing kept
# both. Committing would publish the duplicate, and choosing the winner is not a
# script's call.
conflicts="$(in_tree -name '*.sync-conflict-*' | head -5)"
[ -z "$conflicts" ] || die "Syncthing conflict copies — merge each into its original, then delete the copy:\n$conflicts"

# Still arriving: a temp file is a transfer in flight, and a file changed in the
# last few minutes may be one save of several. Wait rather than commit half.
if [ -n "$(in_tree \( -name '.syncthing.*.tmp' -o -type f -mmin "-$QUIET_MIN" \) | head -1)" ]; then
  echo "still settling — next pass"
  exit 0
fi

# A device whose folder was wiped syncs that as deletions, and a push would
# then empty the published site. History keeps it recoverable, but the site
# would already be gone.
deletes="$(git ls-files --deleted | wc -l | tr -d ' ')"
[ "$deletes" -le "$MAX_DELETES" ] || die "$deletes files deleted at once, more than $MAX_DELETES — if that is intended, rerun with AUTOPUBLISH_MAX_DELETES=$deletes"

if [ "$MODE" = dry ]; then
  git status --short
  git fetch -q "$REMOTE" "$BRANCH" && git status -sb | head -1
  exit 0
fi

git add -A
if ! git diff --cached --quiet; then
  n="$(git diff --cached --name-only | wc -l | tr -d ' ')"
  git commit -q -m "sync: $n file(s) from synced devices" || die "commit failed"
  echo "committed $n file(s)"
fi

git fetch -q "$REMOTE" "$BRANCH" || die "fetch from $REMOTE failed"
UPSTREAM="$REMOTE/$BRANCH"

# Behind or diverged: a git machine pushed. Replay ours on top of theirs.
if ! git merge-base --is-ancestor "$UPSTREAM" HEAD; then
  # Syncthing delivered more since the commit above. Rebasing over it is how an
  # edit gets lost, so leave it to the next pass.
  if ! git diff --quiet; then
    echo "changes arrived mid-pass — next pass"
    exit 0
  fi
  if ! git rebase -q "$UPSTREAM"; then
    git rebase --abort
    die "a synced edit and a pushed commit changed the same lines — resolve on this machine with: git pull --rebase"
  fi
  echo "took the commits from $UPSTREAM"
fi

if [ -n "$(git rev-list "$UPSTREAM..HEAD")" ]; then
  git push -q "$REMOTE" "HEAD:$BRANCH" || die "push to $REMOTE failed"
  echo "pushed to $UPSTREAM"
fi
