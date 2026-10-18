---
name: code-backup
description: Set up, change, verify or restore automatic restic backups of the user's code projects — working trees including uncommitted and unpushed work — designed to the 3-2-1-1 rule (3 copies, 2 media, 1 offsite, 1 offline or immutable) across a local folder, a disk or NAS, and offsite storage (Fly Tigris, Backblaze B2, Cloudflare R2, Hetzner Storage Box, Google Drive via rclone), on a schedule with a failure alert. Ships check.sh, a checklist that verifies the setup and runs restore and integrity tests. Use when the user asks to back up their code, set up restic, asks whether their backups are OK or complete, mentions 3-2-1, adds a backup destination, changes the schedule or retention, finds a backup failed, or needs to restore. Setup happens as a conversation; nothing is written into the vault or a work repository.
---

# Code backup

Git only protects what was committed **and pushed**. Syncthing, Obsidian Sync and Dropbox
replicate a deletion as faithfully as an edit. Neither is a backup. The gap is the working
trees: uncommitted changes, unpushed branches, stashes, the `.env` that never went
anywhere. This skill closes it with [restic](https://restic.net): encrypted on this machine
before upload, deduplicated, incremental, and with any number of destinations.

The vault ships this as a skill, not a script, on purpose. Backup setups differ in every
direction (OS, disks, provider, budget), and a fixed script would suit nobody. So set it up
by **talking it through with the user**, then write the result to *this machine*.

## Strategy: 3-2-1-1

Design every setup to this rule, and say plainly which parts a setup does not meet yet.
The rule is the long-standing 3-2-1 plus one more copy kept offline. Daniel Wells'
[write-up](https://www.danielwells.me/posts/restic-deduplication-vs-git/) is a good
worked example with restic.

| Rule | Means | Protects against |
|---|---|---|
| **3** copies | the original plus two backups | one backup turning out unreadable just when you need it |
| **2** media | not all on one disk: internal disk, external disk, cloud | a dead disk taking the original and its backup together |
| **1** offsite | outside the building | fire, flood, burglary |
| **1** offline | not reachable from this machine | ransomware, a stolen laptop, a leaked key, `restic forget` run in the wrong terminal |

The last row is the one people skip, and it is the one that matters against an
attacker. Any repository this machine can write to, it can also delete. That includes
the cloud bucket: the backup key needs delete rights for `prune`. So the extra copy is
one of these:

- **Offline**: a USB disk that is plugged in for a backup and then put away (`OFFLINE=1`).
  It is cheap and certain, and depends on a habit; `check.sh` fails when the copy gets
  too old.
- **Immutable**: storage that refuses deletes from this machine's credentials. Examples
  are restic's `rest-server --append-only` (on a NAS, say) and S3 Object Lock (AWS,
  Backblaze B2). `forget`/`prune` then runs with a different credential, or not at all.
  Check what the provider actually offers rather than assuming; the `IMMUTABLE=1` flag
  stays ASK until the user confirms it.

Also settle the **recovery goal**: how long the user could live without the code
(an hour? two days?). It decides whether the fast local copy is essential or optional.

## Rules

- **Nothing lands in the vault or in a work repo.** Config goes under `~/.config/code-backup/`,
  the runner under `~/.local/bin/`, the schedule under the user's service manager. The only
  vault edit you may offer is the row described in [Record it](#record-it), which holds no
  secrets.
- **Secrets never pass through the chat.** Write env files with placeholders and `chmod 600`,
  then let the user paste keys in with their editor. Never `cat` a file that holds a key, and
  never echo one back.
- **The restic password is the backup.** Generate it locally, and have the user store it in
  a password manager *before* the first backup. Without it every snapshot is unrecoverable,
  and a password that exists only on the machine being backed up dies with that machine.
- **Ask before** installing packages, running `restic init`, enabling the timer, or running
  any `forget`/`prune` outside the scheduled job.
- **Diagnose read-only.** `snapshots`, `ls`, `stats`, `check`, `diff` and `restore` into an
  empty directory cannot lose anything. Run `forget`, `prune`, `key remove`,
  `unlock --remove-all` and deleting a repository only when the user asked for that exact
  command. An agent that can delete backups is one more way to lose them.

## The conversation

Take one topic at a time and offer the default, so the user can just say "yes". If they
already described their setup (as in the [worked example](#worked-example)), confirm it
instead of asking again.

1. **What.** Default `~/code`. Ask about other roots, and include the vault itself if it
   lives elsewhere. Show the default excludes (below) and ask what they build into, since
   `build/` or `target/` is source in some projects.
2. **Where.** Build toward [3-2-1-1](#strategy-3-2-1-1): a fast local copy, an offsite
   one, and an offline or immutable one. The offline copy can be the local disk itself if
   it gets unplugged between backups. Use the [destinations](#destinations) table. If the
   user wants less, set up what they choose and say which rows it leaves open. For a
   local folder, ask **whether it is on a different physical disk**. If it is on the same
   disk, say so plainly: it protects against `rm -rf` and a bad rebase, not against disk
   failure. A NAS in the same house is on-site, however separate it feels.
3. **When.** Default daily at 02:00. Hourly suits people who leave work uncommitted for days.
   A machine that is off or asleep at that time catches up at next boot or resume
   (`Persistent=true`), so ask only whether it is usually on.
4. **How long to keep it.** Daily default: `--keep-daily 14 --keep-weekly 8 --keep-monthly 12`.
   Hourly: add `--keep-hourly 24`.
5. **Failure alert.** A backup that fails silently is worse than none, because the user
   believes they have one. Default: a desktop notification. Better, and offer it: a
   heartbeat URL (healthchecks.io or similar) that alerts when the job **didn't run at
   all**, which a local notification can never report.
6. **Platform.** Detect it (`uname`, `systemctl --user` available?). Linux with systemd is
   the reference below. For macOS and cron, see [Other schedulers](#other-schedulers).

Then **read the whole plan back** (sources, excludes, destinations, schedule, retention,
alert, files you will write) and wait for a yes before writing anything.

## Destinations

All of these encrypt the same way: the provider only ever sees opaque blobs. Each
destination is its own restic repository with its own env file.

| Destination | `RESTIC_REPOSITORY` | Notes |
|---|---|---|
| **Fly Tigris** | `s3:https://t3.storage.dev/<bucket>/code` | `t3.storage.dev` from outside Fly; `fly.storage.tigris.dev` only from inside a Fly machine. `AWS_DEFAULT_REGION=auto`, since Tigris routes the request itself. `fly storage create` makes the bucket and prints a key pair **once**. For backups, prefer a key scoped to that one bucket. |
| Backblaze B2 | `s3:https://s3.<region>.backblazeb2.com/<bucket>` | S3-style, same shape as Tigris with a B2 application key. |
| Cloudflare R2 | `s3:https://<account-id>.r2.cloudflarestorage.com/<bucket>` | S3-style, region `auto`. No egress fees, so restores are free. |
| Hetzner Storage Box | `sftp:storagebox:/restic-code` | Cheap, hosted in Germany, native SFTP with no rclone. **SSH listens on port 23**: add a `Host storagebox` entry to `~/.ssh/config` with `Port 23` and a key, because an unattended job cannot answer a password prompt. |
| Google Drive | `rclone:gdrive:restic-backups` | Through rclone: `rclone config` creates the `gdrive` remote, with OAuth in the browser. Slower and quirkier than S3: rate limits make the first backup and big prunes slow. **The OAuth token can expire or be revoked**, which breaks unattended runs, so the failure alert is not optional here. 15 GB free, shared with Gmail and Photos. |
| Local folder, USB disk, NAS | `/path/to/restic-code` | The fast copy, and the one restores come from. On removable or network storage, set `REQUIRE_MOUNT`. Otherwise an unmounted disk makes restic write into the empty mount point on the system disk, and it looks like success. |
| Rotated offline disk | `/media/vault-usb/restic-code` | The offline **1**. `REQUIRE_MOUNT` plus `OFFLINE=1`: a nightly run skips it quietly while it is unplugged and backs it up when it is connected at 02:00 or when the user runs `code-backup`. Set `MAX_AGE_HOURS` to the rotation interval, for example 840 for five weeks, so `check.sh` fails when the habit lapses. |
| Append-only rest-server | `rest:https://user:pass@nas.local:8000/code` | Immutable against this machine: `rest-server --append-only` accepts new snapshots and refuses deletes. Pruning runs on the server itself. On the home network it is on-site, so it covers the offline **1**, not the offsite one. Set `IMMUTABLE=1`. |

## What to write

```
~/.config/code-backup/
  settings          SOURCES, FORGET_ARGS, MAX_AGE_HOURS
  excludes          one pattern per line
  password          restic password, chmod 600
  repos/<name>.env  one per destination, chmod 600
  log/              written by the runner and check.sh, read by check.sh
~/.local/bin/code-backup
~/.local/bin/code-backup-check   a copy of this skill's check.sh
~/.config/systemd/user/code-backup.service
~/.config/systemd/user/code-backup.timer
~/.config/systemd/user/code-backup-failed.service
```

One password file for all destinations keeps it to one secret for the user to store. Use
separate files only if they ask.

`settings`:

```bash
SOURCES=("$HOME/code")
FORGET_ARGS=(--keep-daily 14 --keep-weekly 8 --keep-monthly 12)
MAX_AGE_HOURS=48   # check.sh fails a repository whose newest snapshot is older
# HEARTBEAT_URL=https://hc-ping.com/<uuid>
```

`excludes`. A pattern without a slash matches at any depth, so check it with the dry run:

```
node_modules
.venv
__pycache__
target
dist
build
.next
.quartz-cache
```

`.git` stays **in**: it holds the unpushed branches and stashes, which are half the point.
`--exclude-caches` also skips any directory tagged with `CACHEDIR.TAG`. Project `.env`
files are backed up too; they are encrypted, but offer to exclude them if the user would
rather they never leave the machine.

`repos/tigris.env`, for example:

```bash
export RESTIC_REPOSITORY=s3:https://t3.storage.dev/<bucket>/code
export RESTIC_PASSWORD_FILE="$HOME/.config/code-backup/password"
export AWS_ACCESS_KEY_ID=tid_PASTE_HERE
export AWS_SECRET_ACCESS_KEY=tsec_PASTE_HERE
export AWS_DEFAULT_REGION=auto
```

`repos/local.env`:

```bash
export RESTIC_REPOSITORY=/media/backup/restic-code
export RESTIC_PASSWORD_FILE="$HOME/.config/code-backup/password"
export REQUIRE_MOUNT=/media/backup   # only when it is a separate or removable disk
```

Flags `check.sh` reads from a repository's env file, beyond the restic variables:

| Flag | Meaning |
|---|---|
| `REQUIRE_MOUNT=<dir>` | lives on a separate disk; never written when that disk is not mounted |
| `OFFLINE=1` | unplugged between backups: being absent is expected, not a failure |
| `IMMUTABLE=1` | this machine cannot delete from it (append-only, object lock) |
| `OFFSITE=1` / `OFFSITE=0` | overrides the guess from the address, e.g. a disk kept at the office |
| `MAX_AGE_HOURS=<n>` | overrides the freshness limit from `settings` |

`~/.local/bin/code-backup`. Each destination runs in its own subshell, so one failing (the
disk is unplugged, the token expired) never stops the other. That is why there are two
copies.

```bash
#!/usr/bin/env bash
# Back up SOURCES to every restic repository in ~/.config/code-backup/repos/.
set -uo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/code-backup"
source "$CONF/settings"

# 0 = backed up, 2 = an offline disk that is away (expected), anything else = failed.
run() {
  source "$1"
  if [ -n "${REQUIRE_MOUNT:-}" ] && ! mountpoint -q "$REQUIRE_MOUNT"; then
    # A rotated offline disk is meant to be away. check.sh notices when it has
    # been away for too long.
    [ "${OFFLINE:-0}" = 1 ] && { echo "offline copy not connected — skipped"; return 2; }
    echo "$REQUIRE_MOUNT is not mounted" >&2
    return 1
  fi
  restic backup "${SOURCES[@]}" --tag code --exclude-caches --exclude-file "$CONF/excludes"
  rc=$?
  # 3 = snapshot written, but some files could not be read. Worth a look, not a retry.
  [ "$rc" -eq 3 ] && echo "some files were unreadable; the snapshot was still written" >&2
  [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || return 1
  restic forget --tag code "${FORGET_ARGS[@]}" --prune
}

failed=0
mkdir -p "$CONF/log"
for env in "$CONF"/repos/*.env; do
  name="$(basename "$env" .env)"
  echo "── $name"
  ( run "$env" ); rc=$?
  case "$rc" in
    0) echo "$(date +%s) $name ok" >> "$CONF/log/backups" ;;   # check.sh reads this
    2) ;;
    *) echo "✗ $name failed" >&2; failed=1 ;;
  esac
done

if [ -n "${HEARTBEAT_URL:-}" ]; then
  curl -fsS -m 10 --retry 3 "$HEARTBEAT_URL$([ "$failed" -eq 0 ] || echo /fail)" >/dev/null || true
fi
exit "$failed"
```

Do not "simplify" `run` with `set -e`. Bash ignores errexit inside a subshell whose status is
tested by `||`, so a failed backup would fall through to `forget` and report success.

`code-backup.service`:

```ini
[Unit]
Description=restic backup of code projects
OnFailure=code-backup-failed.service

[Service]
Type=oneshot
ExecStart=%h/.local/bin/code-backup
Nice=10
IOSchedulingClass=idle
```

A user service gets a minimal `PATH`. If `restic` or `rclone` is not in `/usr/bin`, add
`Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin`.

`code-backup.timer`:

```ini
[Unit]
Description=Daily code backup

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
```

Use `OnCalendar=hourly` for hourly runs.

`code-backup-failed.service`:

```ini
[Unit]
Description=Notify that the code backup failed

[Service]
Type=oneshot
ExecStart=/usr/bin/notify-send -u critical "Code backup failed" "journalctl --user -u code-backup -e"
```

User timers only run while the user's service manager is up. For runs while logged out,
`loginctl enable-linger "$USER"`, after asking.

## First run: do not skip any of these

1. `restic init` once per destination: `( source ~/.config/code-backup/repos/<name>.env && restic init )`.
2. Dry run against one destination, and read the list with the user:
   `restic backup --dry-run -vv … | less`. Check that the excludes catch the heavy
   directories and nothing that matters, and that the size is plausible.
3. `systemctl --user daemon-reload && systemctl --user start code-backup.service`, then
   `journalctl --user -u code-backup -e`. The first offsite run can take hours on a slow
   uplink; later ones take minutes.
4. `restic snapshots` on **each** destination.
5. `cp <this skill>/check.sh ~/.local/bin/code-backup-check && chmod +x` it, then
   `code-backup-check --restore-test`. It restores one file from each repository, compares
   it byte for byte, and logs the result. A backup that has never been restored is a hope,
   not a backup.
6. `code-backup-check --integrity` reads back a sample of the stored data.
7. `systemctl --user enable --now code-backup.timer` and `systemctl --user list-timers code-backup.timer`.
   The next run should show the expected time.
8. Trigger the alert once, for example with a deliberately wrong `RESTIC_REPOSITORY`, and
   watch it fire. Then put the value back.
9. Run the [checklist](#checklist) and walk the user through every line that is not PASS.

## Checklist

`code-backup-check` (this skill's `check.sh`) is the answer to "are my backups OK?".
Run it rather than reasoning about the config, and report its lines as they are.

| Line | Verified by | PASS when |
|---|---|---|
| `fresh` | restic's latest snapshot (`--offline`: the runner's log) | each repository has a snapshot newer than `MAX_AGE_HOURS` |
| `3 copies` | the `repos/*.env` count | the original plus at least 2 repositories |
| `2 media` | the device under each source and local repository; remote counts as one medium | at least 2 distinct, with no backup on the source's own disk |
| `1 offsite` | the repository address: public host, rclone, or `OFFSITE=1` | at least one; a `.local` or private-IP host is on-site |
| `1 offline` | `OFFLINE=1`, or `IMMUTABLE=1` plus an attestation | at least one |
| `restore tested` | the log of `--restore-test` | each repository restored within 90 days |
| `integrity` | the log of `--integrity` | each repository checked within 35 days (else WARN) |
| `password` | the file exists and is mode 600, plus an attestation | stored off this machine |
| `secrets` | file modes | every env file and the password are 600 |
| `retention` | `FORGET_ARGS` | a policy is set (else WARN) |
| `scheduled` | systemd, launchd or crontab | a job runs `code-backup`; linger is on for systemd |
| `alert` | `OnFailure=` or `HEARTBEAT_URL` | something reports a failed run; a heartbeat also catches one that never started |

**ASK** lines are the ones a script cannot see: whether the password really is in a
password manager, and whether an "immutable" repository really refuses this machine's
deletes. Ask the user. Record their answer with
`code-backup-check --attest password-offsite` or `--attest immutable-<repo>`, never on
your own assumption.

Offer to make it routine: a monthly reminder in the user's tracker, or a second systemd
timer running `code-backup-check --integrity && code-backup-check --restore-test`. The
monthly check reads back a 5% sample. Once a year, read back everything with
`CHECK_SUBSET=100% code-backup-check --integrity`. Read-back costs egress on some
providers (not R2), so mention that for large repositories.

## Other schedulers

- **macOS**: a LaunchAgent in `~/Library/LaunchAgents/` with `StartCalendarInterval`
  (`Hour` 2, `Minute` 0) that runs the same script. launchd runs a missed interval once on
  wake. It has no `OnFailure`, so the heartbeat URL is the alert. Grant the restic binary
  Full Disk Access, or it silently skips protected folders.
- **cron**: `0 2 * * * ~/.local/bin/code-backup`. cron has no catch-up after downtime (use
  anacron for that) and no failure hook, so use `MAILTO` or the heartbeat.

## Changing, checking, restoring

- **Add or remove a destination**: add or remove a `repos/*.env`, then `restic init` the
  new one. The runner picks it up.
- **Why did last night fail?**: `journalctl --user -u code-backup --since yesterday`.
  Usual causes: the disk was not mounted, the cloud key was rotated, or a stale lock from a
  run that was killed (`restic unlock`, only once nothing else is running).
- **Restore**: `restic snapshots`, then `restic restore <id> --target <empty dir>`. Never
  restore over the live tree. For a few files, `restic mount ~/mnt/backup` lets the user
  browse the snapshots as folders.

## Record it

Offer one row for `WHERE-THINGS-LIVE.md`, so the next agent knows backups exist and where
to look, without opening this machine's config:

```
| Code backups | restic on <machine>: <local path>, <provider> bucket <name> | `systemctl --user status code-backup` | anywhere with keys |
```

Never put the password, a key or a bucket credential in the vault.

## Worked example

The setup the template author runs, which also makes a sensible default:

- **What:** `~/code`, default excludes
- **Where:** a local backup folder on a separate disk (`REQUIRE_MOUNT` set), plus a Fly
  Tigris bucket via `t3.storage.dev`
- **When:** daily at 02:00, `Persistent=true`
- **Keep:** 14 daily, 8 weekly, 12 monthly
- **Alert:** desktop notification on failure

Against [3-2-1-1](#strategy-3-2-1-1) that is **3-2-1**: three copies (the original, the
local disk, Tigris) on three media, with Tigris offsite. The offline **1** is open. The
local disk stays mounted, and the Tigris key can delete, so ransomware on this machine
could reach both. The checklist reports it as a FAIL. Close it with either:

- a second USB disk, plugged in for a backup now and then and stored elsewhere
  (`OFFLINE=1`, `MAX_AGE_HOURS=840`), or
- an append-only rest-server on the home NAS (`IMMUTABLE=1`), which runs on its own and
  needs no habit.
