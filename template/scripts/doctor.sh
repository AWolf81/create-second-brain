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
