#!/usr/bin/env bash
#
# Check the setup steps a scaffolder cannot perform, and the local mistakes that
# fail silently. Detects the deploy target from the files present.
#
# Run from the repository root: ./scripts/doctor.sh

set -uo pipefail

fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
note() { printf '  \033[33m–\033[0m %s\n' "$1"; }

if [ -f fly.toml ]; then TARGET=fly
elif [ -f .gitlab-ci.yml ]; then TARGET=gitlab
else TARGET=unknown
fi

base="$(sed -nE 's/^ *baseUrl: *(.*)/\1/p' site/quartz.config.yaml | head -1)"

echo "Target: $TARGET"
echo
echo "Vault"

if ./scripts/validate-note-titles.sh >/dev/null 2>&1; then
  ok "every published note has a title source"
else
  bad "some notes have no '# H1' and no frontmatter title — run ./scripts/validate-note-titles.sh"
fi

if [ -d .claude ] || [ -d .agents ]; then
  ok "COG agent skills installed"
  if ./scripts/check-agent-surface.sh >/dev/null 2>&1; then
    ok "agent surface check passes"
  else
    bad "agent surface check failed — run ./scripts/check-agent-surface.sh"
  fi
else
  note "COG not installed — run ./scripts/add-cog.sh if you want the agent skills"
fi

if [ -d .obsidian ]; then ok "Obsidian settings present"; else note "no .obsidian/ — the vault still opens, just unconfigured"; fi

# A link has two halves and only one of them is committed. The failure this catches
# is a fresh clone on a second machine: the vault still lists the repos, so nothing
# looks wrong, while the agent side of the wiring does not exist at all.
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ ! -x scripts/link-repo.sh ]; then
  note "scripts/link-repo.sh missing — cannot link work repos"
else
  linked="$(./scripts/link-repo.sh --list 2>/dev/null | sed -nE 's/^  ([^ ]+) +.*/\1/p')"
  if [ -z "$linked" ]; then
    note "no work repos linked — run ./scripts/link-repo.sh <path-or-url>"
  elif [ ! -f "$CLAUDE_DIR/skills/second-brain/SKILL.md" ] ||
       ! grep -q 'second-brain:begin' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    bad "$(wc -w <<<"$linked") repo(s) linked here but $CLAUDE_DIR has no wiring — re-run ./scripts/link-repo.sh once per repo"
  else
    missing=""
    while read -r name; do
      grep -q "\`$name\`" "$CLAUDE_DIR/CLAUDE.md" || missing="$missing $name"
    done <<<"$linked"
    if [ -n "$missing" ]; then
      bad "linked here but not in $CLAUDE_DIR/CLAUDE.md:$missing — re-run ./scripts/link-repo.sh for each"
    else
      ok "work repos linked and wired into $CLAUDE_DIR ($(wc -w <<<"$linked"))"
    fi
  fi
fi

# The hook is what turns "agents read the vault" from an assertion into a record.
# An unregistered hook is invisible from the inside: the ledger just stays empty,
# which reads identically to nobody having consulted the vault.
if [ -f hooks/vault-read-logger.sh ]; then
  hook="$CLAUDE_DIR/hooks/vault-read-logger.sh"
  if ! command -v jq >/dev/null 2>&1; then
    bad "jq is not installed — the read-logger hook cannot be registered or run"
  elif [ ! -x "$hook" ]; then
    note "read-logger hook not installed — run ./scripts/link-repo.sh to add it"
  elif ! jq -e --arg c "$hook" '[.hooks.PostToolUse[]? | (.hooks // [])[].command] | index($c)' \
         "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
    bad "the hook exists but is not registered in $CLAUDE_DIR/settings.json — re-run ./scripts/link-repo.sh"
  else
    ledger="${VAULT_USAGE_LEDGER:-$CLAUDE_DIR/vault-usage.tsv}"
    if [ -s "$ledger" ]; then
      ok "vault reads are being recorded ($(wc -l <"$ledger" | tr -d " ") so far — ./scripts/vault-usage.sh)"
    else
      note "read-logger installed, nothing recorded yet — expected until an agent opens a note"
    fi
    [ -s "$ledger.err" ] && bad "the read-logger logged errors — see $ledger.err"
  fi
fi

# Conventions an agent cannot read are decoration. Check the wiring, not the wording:
# a dropped import is indistinguishable from having no conventions at all.
if [ ! -f WHERE-THINGS-LIVE.md ]; then
  bad "WHERE-THINGS-LIVE.md is missing — agents have no routing rules to follow"
elif [ ! -f CLAUDE.md ]; then
  bad "CLAUDE.md is missing — WHERE-THINGS-LIVE.md exists but nothing loads it"
elif ! grep -q '@WHERE-THINGS-LIVE.md' CLAUDE.md; then
  bad "CLAUDE.md no longer imports WHERE-THINGS-LIVE.md — re-add the '@WHERE-THINGS-LIVE.md' line"
else
  ok "agent conventions wired (CLAUDE.md imports WHERE-THINGS-LIVE.md)"
  if grep -q '<your tracker>\|<your product repo>' WHERE-THINGS-LIVE.md; then
    note "WHERE-THINGS-LIVE.md still has <placeholders> — fill in your own tools"
  fi
fi

echo
echo "Site"

case "$TARGET" in
  fly)
    app="$(sed -nE 's/^app *= *"(.*)"/\1/p' fly.toml | head -1)"
    # These two drift apart easily and the symptom is invisible: self-hosted
    # fonts are emitted as absolute https://<baseUrl>/... URLs and simply 404.
    if [ -z "$app" ]; then
      bad "fly.toml has no app name"
    elif [ "$base" = "$app.fly.dev" ]; then
      ok "fly.toml app ($app) matches quartz baseUrl"
    else
      bad "fly.toml app is '$app' but quartz baseUrl is '$base' — fonts will 404"
    fi

    [ -x site/entrypoint.sh ] && ok "site/entrypoint.sh is executable" \
      || bad "site/entrypoint.sh is not executable (chmod +x)"

    FLY="$(command -v fly || command -v flyctl || true)"
    if [ -z "$FLY" ]; then
      note "flyctl not installed — cannot check the app or its secrets"
    elif "$FLY" status --app "$app" >/dev/null 2>&1; then
      ok "app '$app' exists"
      secrets="$("$FLY" secrets list --app "$app" 2>/dev/null || true)"
      grep -q 'BASIC_AUTH_USER' <<<"$secrets" && ok "BASIC_AUTH_USER is set" \
        || bad "BASIC_AUTH_USER is not set — the site will 401 for everyone"
      grep -qE 'BASIC_AUTH_PASSWORD|BASIC_AUTH_HASH' <<<"$secrets" && ok "a password or hash is set" \
        || bad "no password or hash set — the site will 401 for everyone"
    else
      bad "app '$app' not found — run: fly apps create $app"
    fi

    if command -v gh >/dev/null 2>&1 && gh secret list 2>/dev/null | grep -q FLY_API_TOKEN; then
      ok "FLY_API_TOKEN repository secret is set"
    elif command -v gh >/dev/null 2>&1; then
      bad "FLY_API_TOKEN is not set — the deploy workflow cannot authenticate"
    else
      note "gh not installed — cannot check the FLY_API_TOKEN secret"
    fi
    ;;

  gitlab)
    [ -f .gitlab-ci.yml ] && ok ".gitlab-ci.yml present"
    case "$base" in
      *"<your-namespace>"*|"")
        bad "quartz baseUrl is still a placeholder ('$base') — set it to <namespace>.gitlab.io/<project>, or fonts will 404" ;;
      *) ok "quartz baseUrl is set ($base)" ;;
    esac
    # Access control is a project setting; there is no way to read it from here.
    note "confirm Pages access control is ON: Settings → General → Visibility,"
    note "project features, permissions → Pages. Without it the site is PUBLIC."
    ;;

  *)
    bad "no fly.toml and no .gitlab-ci.yml — no deploy target configured"
    ;;
esac

echo
[ "$fail" -eq 0 ] && echo "All checks passed." || echo "Some checks failed — see above."
exit "$fail"
