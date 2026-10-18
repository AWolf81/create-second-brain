#!/usr/bin/env bash
#
# Check a code-backup setup against 3-2-1-1, and run the two checks that only
# a real run can prove: a restore, and an integrity read of the stored data.
#
#   check.sh                  the checklist; asks each repository for its latest snapshot
#   check.sh --offline        the checklist from local state only, contacting nothing
#   check.sh --restore-test   restore one file from each repository, compare it, log it
#   check.sh --integrity      restic check --read-data-subset on each repository, log it
#   check.sh --attest KEY     record what only the user can confirm:
#                               password-offsite      the restic password is stored off this machine
#                               immutable-<repo>      no key on this machine can delete <repo>
#
# Each line is PASS, FAIL, WARN or ASK, then the rule and the evidence. ASK
# means only the user can confirm it: ask them, then record it with --attest.
# Exit 1 if anything FAILs.
#
# Reads the layout the code-backup skill writes: ~/.config/code-backup/{settings,
# excludes,password,repos/*.env}. Per-repository flags in its .env:
#   REQUIRE_MOUNT=<dir>   a separate disk; skipped (and failed) when not mounted
#   OFFLINE=1             a disk that is unplugged between backups
#   IMMUTABLE=1           object lock, or an append-only rest-server
#   OFFSITE=1|0           overrides the guess from the repository's address
#   MAX_AGE_HOURS=<n>     how old its newest snapshot may get (settings default: 48)

set -uo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/code-backup"
LOG="$CONF/log"
RESTORE_MAX_DAYS=90
INTEGRITY_MAX_DAYS=35

fails=0
line() { printf '%-5s %-17s %s\n' "$1" "$2" "$3"; }
pass() { line PASS "$1" "$2"; }
fail() { line FAIL "$1" "$2"; fails=$((fails + 1)); }
warn() { line WARN "$1" "$2"; }
ask()  { line ASK  "$1" "$2"; }

now() { date +%s; }
# Newest "<epoch> <key> ok" line for KEY in a log, as an epoch, or nothing.
last_ok() { [ -f "$LOG/$1" ] && awk -v k="$2" '$2 == k && $3 == "ok" { t = $1 } END { if (t) print t }' "$LOG/$1"; }
record() { mkdir -p "$LOG"; echo "$(now) $2 $3 ${4:-}" >> "$LOG/$1"; }
ago() { local h=$(( ($(now) - $1) / 3600 )); [ "$h" -lt 48 ] && echo "${h}h ago" || echo "$((h / 24))d ago"; }

perms() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
device() { df -P "$1" 2>/dev/null | awk 'NR == 2 { print $1 }'; }
is_mounted() {
  if command -v mountpoint >/dev/null; then mountpoint -q "$1"
  else [ "$(device "$1")" != "$(device "$(dirname "$1")")" ]
  fi
}

[ -f "$CONF/settings" ] || { echo "No setup found at $CONF — nothing to check." >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONF/settings"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-48}"
shopt -s nullglob
REPOS=("$CONF"/repos/*.env)

# Run in a subshell per repository, with only that repository's environment.
in_repo() { ( set -a; source "$1"; set +a; shift; "$@" ); }

# Latest snapshot of a repository as "<epoch> <short id>", from restic itself.
latest_snapshot() {
  restic snapshots --latest 1 --tag code --json 2>/dev/null | python3 -c '
import json, re, sys, datetime
s = json.load(sys.stdin) or []
if s:
    t = re.sub(r"\.\d+", "", s[-1]["time"]).replace("Z", "+00:00")
    print(int(datetime.datetime.fromisoformat(t).timestamp()), s[-1]["short_id"])'
}

# --- the two checks that need a real run -------------------------------------

# One file unchanged since the snapshot, so it must restore byte for byte. Skips
# the excludes, or the test would pick a file that was never backed up.
pick_file() {
  local age_min="$1" pat
  local prune=()
  while IFS= read -r pat; do
    [ -z "$pat" ] || [[ "$pat" == \#* ]] || [[ "$pat" == */* ]] && continue
    prune+=(-name "$pat" -prune -o)
  done < "$CONF/excludes"
  find "${SOURCES[@]}" "${prune[@]}" -name .git -prune -o \
    -type f -size +0 -size -1024k -mmin "+$age_min" -print 2>/dev/null \
    | head -2000 | awk -v seed="$RANDOM" 'BEGIN { srand(seed) } { a[NR] = $0 } END { if (NR) print a[int(rand() * NR) + 1] }'
}

restore_one() {
  local name="$1" snap t id f tmp
  if [ -n "${REQUIRE_MOUNT:-}" ] && ! is_mounted "$REQUIRE_MOUNT"; then
    echo "skip  $name: $REQUIRE_MOUNT is not mounted"; return 0
  fi
  snap="$(latest_snapshot)"; [ -n "$snap" ] || { echo "FAIL  $name: no snapshot"; record restore-test "$name" fail; return 1; }
  read -r t id <<<"$snap"
  f="$(pick_file $(( ($(now) - t) / 60 + 1 )))"
  [ -n "$f" ] || { echo "FAIL  $name: no file old enough to compare"; return 1; }
  tmp="$(mktemp -d)"
  restic restore "$id" --target "$tmp" --include "$f" >/dev/null 2>&1
  if cmp -s "$f" "$tmp$f"; then
    echo "PASS  $name: restored $f from $id, identical"; record restore-test "$name" ok "$f"
  else
    echo "FAIL  $name: $f from $id did not restore identically"; record restore-test "$name" fail "$f"
  fi
  rm -rf "$tmp"
}

integrity_one() {
  local name="$1"
  if [ -n "${REQUIRE_MOUNT:-}" ] && ! is_mounted "$REQUIRE_MOUNT"; then
    echo "skip  $name: $REQUIRE_MOUNT is not mounted"; return 0
  fi
  if restic check --read-data-subset "${CHECK_SUBSET:-5%}" >/dev/null 2>&1; then
    echo "PASS  $name: check --read-data-subset ${CHECK_SUBSET:-5%}"; record integrity "$name" ok
  else
    echo "FAIL  $name: restic check failed — run it by hand to see why"; record integrity "$name" fail
  fi
}

case "${1:-}" in
  --restore-test|--integrity)
    fn=restore_one; [ "$1" = --integrity ] && fn=integrity_one
    rc=0
    for env in "${REPOS[@]}"; do in_repo "$env" "$fn" "$(basename "$env" .env)" || rc=1; done
    exit "$rc" ;;
  --attest)
    key="${2:?--attest needs a key: password-offsite or immutable-<repo>}"
    case "$key" in password-offsite|immutable-*) ;; *) echo "unknown key: $key" >&2; exit 2 ;; esac
    record attest "$key" ok; echo "recorded: $key"; exit 0 ;;
  --offline|"") OFFLINE_MODE="${1:+1}" ;;
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

# --- the checklist -----------------------------------------------------------

# Classify each repository once: where it lives, and whether it is fresh.
# (No associative arrays: macOS still ships bash 3.2.)
offsite=() offline=() immutable=()
src_devs=" "
for s in "${SOURCES[@]}"; do src_devs+="$(device "$s") "; done
media="$src_devs"
add_medium() { [[ "$media" == *" $1 "* ]] || media+="$1 "; }

for env in "${REPOS[@]}"; do
  name="$(basename "$env" .env)"
  unset REQUIRE_MOUNT OFFLINE IMMUTABLE OFFSITE RESTIC_REPOSITORY
  REPO_MAX_AGE="$MAX_AGE_HOURS"
  # shellcheck source=/dev/null
  eval "$(set -a; source "$env"; printf 'RESTIC_REPOSITORY=%q REQUIRE_MOUNT=%q OFFLINE=%q IMMUTABLE=%q OFFSITE=%q REPO_MAX_AGE=%q' \
    "${RESTIC_REPOSITORY:-}" "${REQUIRE_MOUNT:-}" "${OFFLINE:-0}" "${IMMUTABLE:-0}" "${OFFSITE:-}" "${MAX_AGE_HOURS:-$REPO_MAX_AGE}")"
  repo="$RESTIC_REPOSITORY"

  case "$repo" in
    /*|local:*)
      path="${repo#local:}"
      if [ -n "$REQUIRE_MOUNT" ] && ! is_mounted "$REQUIRE_MOUNT"; then
        add_medium "disk:$name"   # declared a separate disk, not connected right now
      else
        dev="$(device "$path")"; add_medium "$dev"
        [[ "$src_devs" == *" $dev "* ]] && warn "media" "$name is on the same disk as the source ($dev): it survives rm -rf, not a dead disk"
      fi
      [ "$OFFSITE" = 1 ] && offsite+=("$name (declared)") ;;
    *)
      add_medium network
      host="$(sed -E 's#^[a-z0-9]+:(https?://)?([^@/]*@)?([^/:]+).*#\3#' <<<"$repo")"
      if [ "$OFFSITE" = 0 ]; then :
      elif [ "$OFFSITE" = 1 ] || [[ "$repo" == rclone:* ]]; then offsite+=("$name")
      # A NAS in the same house is a network copy, not an offsite one: the fire
      # or burglary that takes the machine takes it too.
      elif [[ "$host" == *.local ]] || python3 -c 'import ipaddress, socket, sys
sys.exit(0 if ipaddress.ip_address(socket.gethostbyname(sys.argv[1])).is_private else 1)' "$host" 2>/dev/null; then
        warn "offsite" "$name ($host) is on your local network — on-site, not offsite"
      else offsite+=("$name")
      fi ;;
  esac
  [ "$OFFLINE" = 1 ] && offline+=("$name")
  [ "$IMMUTABLE" = 1 ] && immutable+=("$name")

  # Freshness: from restic when we may contact it, else from the runner's log.
  t=""
  if [ -z "${OFFLINE_MODE:-}" ] && ! { [ -n "$REQUIRE_MOUNT" ] && ! is_mounted "$REQUIRE_MOUNT"; }; then
    t="$(in_repo "$env" latest_snapshot | cut -d' ' -f1)"; via=restic
  fi
  [ -n "$t" ] || { t="$(last_ok backups "$name")"; via=log; }
  if [ -z "$t" ]; then
    fail "fresh" "$name: no successful backup on record"
  elif [ $(( ($(now) - t) / 3600 )) -gt "$REPO_MAX_AGE" ]; then
    fail "fresh" "$name: newest snapshot $(ago "$t"), allowed ${REPO_MAX_AGE}h ($via)"
  else
    pass "fresh" "$name: newest snapshot $(ago "$t") ($via)"
  fi

  if [ "$OFFLINE" = 1 ] && [ -n "$REQUIRE_MOUNT" ] && is_mounted "$REQUIRE_MOUNT"; then
    warn "offline" "$name is connected right now — fine during a backup, otherwise unplug it"
  fi
  [ "$(perms "$env")" = 600 ] || [ "$(perms "$env")" = 400 ] || fail "secrets" "$env is mode $(perms "$env"), want 600"
done

# 3 copies: the original plus at least two backups.
n=${#REPOS[@]}
if [ "$n" -ge 2 ]; then pass "3 copies" "the original + $n backup repositories"
else fail "3 copies" "the original + $n backup repositories; 3-2-1-1 needs at least 2"
fi

# 2 media: a backup on the source's own disk does not count as a second medium.
# Distinct devices stand in for distinct media; two partitions of one physical
# disk would pass, so the skill asks about that rather than trusting this.
n_media=$(wc -w <<<"$media" | tr -d ' ')
if [ "$n_media" -ge 2 ]; then pass "2 media" "$n_media distinct: $(xargs <<<"$media")"
else fail "2 media" "every copy is on one medium: $(xargs <<<"$media")"
fi

# 1 offsite
if [ ${#offsite[@]} -ge 1 ]; then pass "1 offsite" "${offsite[*]}"
else fail "1 offsite" "no copy outside this building: a fire or a burglary takes every one"
fi

# 1 offline (or immutable): the copy ransomware with this machine's keys cannot reach.
if [ ${#offline[@]} -ge 1 ]; then
  pass "1 offline" "${offline[*]} (unplugged between backups)"
elif [ ${#immutable[@]} -ge 1 ]; then
  unconfirmed=()
  for name in "${immutable[@]}"; do [ -n "$(last_ok attest "immutable-$name")" ] || unconfirmed+=("$name"); done
  if [ ${#unconfirmed[@]} -eq 0 ]; then pass "1 offline" "${immutable[*]} immutable (confirmed)"
  else ask "1 offline" "${unconfirmed[*]} declared immutable — confirm no key on this machine can delete it, then --attest immutable-<repo>"
  fi
else
  fail "1 offline" "every copy is reachable with this machine's keys: ransomware or a stolen laptop can delete them all"
fi

# Restorable, and readable.
for env in "${REPOS[@]}"; do
  name="$(basename "$env" .env)"
  t="$(last_ok restore-test "$name")"
  if [ -z "$t" ]; then fail "restore tested" "$name: never restored — run --restore-test"
  elif [ $(( ($(now) - t) / 86400 )) -gt $RESTORE_MAX_DAYS ]; then warn "restore tested" "$name: last restore $(ago "$t") — run --restore-test"
  else pass "restore tested" "$name: $(ago "$t")"
  fi
  t="$(last_ok integrity "$name")"
  if [ -z "$t" ]; then warn "integrity" "$name: never checked — run --integrity"
  elif [ $(( ($(now) - t) / 86400 )) -gt $INTEGRITY_MAX_DAYS ]; then warn "integrity" "$name: last check $(ago "$t")"
  else pass "integrity" "$name: $(ago "$t")"
  fi
done

# The password: the one secret without which every copy is noise.
pw="${RESTIC_PASSWORD_FILE:-$CONF/password}"
if [ ! -s "$pw" ]; then fail "password" "no password file at $pw"
else
  case "$(perms "$pw")" in 600|400) ;; *) fail "secrets" "$pw is mode $(perms "$pw"), want 600" ;; esac
  t="$(last_ok attest password-offsite)"
  if [ -n "$t" ]; then pass "password" "stored off this machine (confirmed $(ago "$t"))"
  else ask "password" "is it in a password manager or on paper, off this machine? then --attest password-offsite"
  fi
fi

# Retention
if [ "${#FORGET_ARGS[@]}" -gt 0 ]; then pass "retention" "${FORGET_ARGS[*]}"
else warn "retention" "no FORGET_ARGS: snapshots accumulate forever"
fi

# Schedule and alert: a backup nobody runs, or whose failure nobody hears of.
if command -v systemctl >/dev/null && systemctl --user cat code-backup.timer >/dev/null 2>&1; then
  if systemctl --user is-enabled code-backup.timer >/dev/null 2>&1 && systemctl --user is-active code-backup.timer >/dev/null 2>&1; then
    pass "scheduled" "$(systemctl --user show code-backup.timer -p TimersCalendar --value | sed -E 's/.*OnCalendar=([^;]*).*/\1/' | xargs)"
  else fail "scheduled" "code-backup.timer exists but is not enabled and active"
  fi
  if [ -n "$(systemctl --user show code-backup.service -p OnFailure --value)" ] || [ -n "${HEARTBEAT_URL:-}" ]; then
    pass "alert" "${HEARTBEAT_URL:+heartbeat }$(systemctl --user show code-backup.service -p OnFailure --value)"
  else fail "alert" "nothing reports a failed run"
  fi
  [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" = yes ] \
    || warn "scheduled" "linger is off: the timer only runs while you are logged in"
elif launchctl list 2>/dev/null | grep -q code-backup; then
  pass "scheduled" "launchd"
  [ -n "${HEARTBEAT_URL:-}" ] && pass "alert" "heartbeat" || fail "alert" "launchd has no failure hook — set HEARTBEAT_URL"
elif crontab -l 2>/dev/null | grep -q code-backup; then
  pass "scheduled" "cron"
  [ -n "${HEARTBEAT_URL:-}" ] && pass "alert" "heartbeat" || warn "alert" "cron reports only by MAILTO — set HEARTBEAT_URL"
else
  fail "scheduled" "no timer, LaunchAgent or crontab entry runs code-backup"
fi
[ -n "${HEARTBEAT_URL:-}" ] || warn "alert" "no HEARTBEAT_URL: a run that never starts goes unnoticed"

echo
if [ "$fails" -eq 0 ]; then echo "3-2-1-1: in place."; else echo "3-2-1-1: $fails item(s) failing."; fi
[ "$fails" -eq 0 ]
