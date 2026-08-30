#!/usr/bin/env bash
#
# Update this vault's machinery from the create-second-brain template, without
# ever touching a note.
#
# A vault is three kinds of file, and the difference is the whole problem:
#
#   machinery   scripts/, hooks/, site/, Dockerfile, CI config. The template
#               owns these. Overwrite freely.
#   notes       00-inbox … 06-templates. You own these. The updater has no path
#               to them at all — they are absent from the manifest, so there is
#               no code here that could write one even by mistake.
#   seeded      05-knowledge/README.md, WHERE-THINGS-LIVE.md, CLAUDE.md. The
#               template writes a starting point and you then edit it. This is
#               the category that a naive "copy the new files over" destroys.
#
# Telling the third category apart is what .template-manifest is for. It records
# the sha256 of every file as the template wrote it. On update, a file whose
# hash still matches is untouched, so the template still owns it and the new
# version lands. A file whose hash has drifted is yours now: it is skipped and
# reported, never merged and never clobbered. You decide what to take.
#
# The failure this prevents is specific and has happened: a populated routing
# table in 05-knowledge/README.md, replaced by the template's empty placeholder
# during a whole-tree rebuild. Nothing warned, because nothing knew the file had
# ever been edited.
#
# Usage:
#   ./scripts/update-template.sh                  update from the published template
#   ./scripts/update-template.sh --dry-run        report what would change, write nothing
#   ./scripts/update-template.sh --diff [path]    show what the template changed
#   ./scripts/update-template.sh --source <dir>   update from a local checkout
#   ./scripts/update-template.sh --ref <ref>      update from a branch or tag

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST=.template-manifest
UPSTREAM="https://github.com/AWolf81/create-second-brain.git"
REF=main
SOURCE=""
MODE=apply
DIFF_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry ;;
    --diff)    MODE=diff; [ $# -gt 1 ] && [[ "$2" != --* ]] && { DIFF_PATH="$2"; shift; } ;;
    --source)  SOURCE="${2:?--source needs a directory}"; shift ;;
    --ref)     REF="${2:?--ref needs a branch or tag}"; shift ;;
    -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "✗ $1" >&2; exit 1; }

[ -f "$MANIFEST" ] || die "no $MANIFEST here. This vault predates the updater;
  see the migration note in README.md under 'Updating the machinery'."

command -v python3 >/dev/null 2>&1 || die "python3 is required."

# An update rewrites tracked files in place. Without a clean tree there is no
# way to tell what the updater changed from what you were already editing, and
# no cheap way back. git is the undo button, so insist on one being available.
if [ "$MODE" = apply ] && git rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    die "working tree has uncommitted changes. Commit or stash first, so this
  update is reviewable as its own diff."
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$SOURCE" ]; then
  [ -d "$SOURCE/template" ] || die "$SOURCE does not look like a create-second-brain checkout."
  SRC="$(cd "$SOURCE" && pwd)"
else
  echo "Fetching template ($REF) …"
  git clone --depth 1 --branch "$REF" --filter=blob:none "$UPSTREAM" "$TMP/src" >/dev/null 2>&1 \
    || die "could not fetch $UPSTREAM at $REF."
  SRC="$TMP/src"
fi

# Re-scaffold into a throwaway directory using the same target, CI and
# substitutions this vault was created with. Comparing against a real scaffold
# rather than against raw template sources means __APP_NAME__ and friends are
# already resolved, so a file differs only where the template actually changed.
TARGET="$(python3 -c 'import json;print(json.load(open(".template-manifest")).get("target","fly"))')"
CI="$(python3 -c 'import json;print(json.load(open(".template-manifest")).get("ci","github"))')"
APP="$(python3 - <<'PY'
import re, pathlib
# The app name is the one substitution not recoverable from the manifest, and
# fly.toml / quartz.config.yaml are where it ended up.
for p, pat in ((pathlib.Path("fly.toml"), r'^app\s*=\s*"([^"]+)"'),
               (pathlib.Path("site/quartz.config.yaml"), r'^\s*baseUrl:\s*([^.\s]+)')):
    if p.exists():
        m = re.search(pat, p.read_text(), re.M)
        if m:
            print(m.group(1)); break
else:
    print(pathlib.Path.cwd().name)
PY
)"

TITLE="$(python3 - <<'PY'
import re, pathlib
p = pathlib.Path("site/quartz.config.yaml")
m = re.search(r'^\s*pageTitle:\s*"?([^"\n]+)"?', p.read_text(), re.M) if p.exists() else None
print(m.group(1).strip() if m else "Second Brain")
PY
)"

echo "Rebuilding a reference vault (target: $TARGET, ci: $CI, app: $APP) …"
node "$SRC/index.js" "$TMP/ref" --target "$TARGET" --ci "$CI" --app "$APP" \
  --title "$TITLE" --no-cog --yes >/dev/null 2>&1 \
  || die "could not scaffold a reference vault from $SRC."

[ -f "$TMP/ref/.template-manifest" ] || die "the template at $REF has no manifest support.
  Update to a newer template, or re-run with --ref main."

if [ "$MODE" = diff ]; then
  python3 - "$TMP/ref" "$DIFF_PATH" <<'PY'
import json, pathlib, subprocess, sys
ref, only = pathlib.Path(sys.argv[1]), sys.argv[2]
old = json.load(open(".template-manifest"))["files"]
new = json.load(open(ref / ".template-manifest"))["files"]
paths = [only] if only else sorted(set(old) | set(new))
shown = 0
for p in paths:
    if old.get(p) == new.get(p) and not only:
        continue
    a, b = pathlib.Path(p), ref / p
    if not b.exists():
        print(f"− {p} — no longer shipped by the template"); shown += 1; continue
    if not a.exists():
        print(f"+ {p} — new in the template"); shown += 1; continue
    d = subprocess.run(["diff", "-u", "--label", f"{p} (yours)",
                        "--label", f"{p} (template)", str(a), str(b)],
                       capture_output=True, text=True).stdout
    if d:
        print(d, end=""); shown += 1
if not shown:
    print("Nothing differs: this vault matches the template.")
PY
  exit 0
fi

# The decision table. Every file the template ships falls into exactly one of
# four states, and only two of them write anything.
python3 - "$TMP/ref" "$MODE" <<'PY'
import hashlib, json, pathlib, shutil, sys

ref, mode = pathlib.Path(sys.argv[1]), sys.argv[2]
dry = mode == "dry"
old = json.load(open(".template-manifest"))["files"]
new_manifest = json.load(open(ref / ".template-manifest"))
new = new_manifest["files"]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

updated, added, kept, gone, same = [], [], [], [], 0

for p in sorted(new):
    dst, src = pathlib.Path(p), ref / p

    if p not in old:
        # The template gained a file this vault has never had. If something is
        # already sitting at that path it is not ours to overwrite.
        (kept if dst.exists() else added).append(p)
        if not dst.exists() and not dry:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        continue

    if not dst.exists():
        # Deleted deliberately, most likely. Re-adding it would be a surprise.
        gone.append(p)
        continue

    current = sha(dst)
    if current == old[p]:
        # Untouched since the template wrote it, so the template still owns it.
        if old[p] != new[p]:
            updated.append(p)
            if not dry:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
        else:
            same += 1
    elif old[p] != new[p]:
        # Edited here *and* changed upstream. The interesting case, and the one
        # that must never be resolved automatically.
        kept.append(p)
    else:
        # Edited here, unchanged upstream. Nothing to do and nothing to say.
        same += 1

for p in updated: print(f"\033[32m✓\033[0m {p}")
for p in added:   print(f"\033[32m+\033[0m {p}  (new)")
for p in gone:    print(f"\033[33m–\033[0m {p}  (template ships this; not here — skipped)")
for p in kept:
    print(f"\033[33m~\033[0m {p}")
    print(f"    yours, and the template's version changed — left alone")
    print(f"    see it with: ./scripts/update-template.sh --diff {p}")

print()
n = len(updated) + len(added)
if dry:
    print(f"Dry run: {n} file(s) would change, {len(kept)} left to you, {same} already current.")
    print("Re-run without --dry-run to apply.")
else:
    print(f"{n} file(s) updated, {len(kept)} left to you, {same} already current.")

# The manifest is the record of what the template last wrote, so it may only be
# rewritten for files that actually took the new version. A path the vault owns
# keeps its old hash: overwriting it would silently transfer ownership back and
# make the next update clobber the very edits this one protected.
if not dry:
    merged = dict(old)
    for p in updated + added:
        merged[p] = new[p]
    new_manifest["files"] = dict(sorted(merged.items()))
    pathlib.Path(".template-manifest").write_text(json.dumps(new_manifest, indent=2) + "\n")

if kept:
    print()
    print("Nothing above marked ~ was changed. Notes were never considered:")
    print("00-inbox … 06-templates are not in the manifest, so this script")
    print("cannot write to them.")
PY

echo
echo "Next: review with 'git diff', then ./scripts/doctor.sh"
