#!/usr/bin/env bash
#
# Check the setup steps a scaffolder cannot do for you, plus the one local
# mistake that fails silently.
#
# Run from the repository root: ./scripts/doctor.sh

set -uo pipefail

fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
skip() { printf '  \033[33m–\033[0m %s\n' "$1"; }

app="$(sed -nE 's/^app *= *"(.*)"/\1/p' fly.toml | head -1)"
base="$(sed -nE 's/^ *baseUrl: *(.*)/\1/p' site/quartz.config.yaml | head -1)"

echo "Local configuration"

# These two drift apart easily and the symptom is invisible: self-hosted fonts
# are emitted as absolute https://<baseUrl>/... URLs and simply 404.
if [ -z "$app" ]; then
  bad "fly.toml has no app name"
elif [ "$base" = "$app.fly.dev" ]; then
  ok "fly.toml app ($app) matches quartz baseUrl"
else
  bad "fly.toml app is '$app' but quartz baseUrl is '$base' — fonts will 404"
fi

[ -x site/entrypoint.sh ] && ok "site/entrypoint.sh is executable" \
  || bad "site/entrypoint.sh is not executable (chmod +x)"

if ./scripts/validate-note-titles.sh >/dev/null 2>&1; then
  ok "every published note has a title source"
else
  bad "some notes have no '# H1' and no frontmatter title — run ./scripts/validate-note-titles.sh"
fi

echo
echo "Fly"

if ! command -v fly >/dev/null 2>&1 && ! command -v flyctl >/dev/null 2>&1; then
  skip "flyctl not installed — cannot check the app or its secrets"
else
  FLY="$(command -v fly || command -v flyctl)"
  if "$FLY" status --app "$app" >/dev/null 2>&1; then
    ok "app '$app' exists"
    secrets="$("$FLY" secrets list --app "$app" 2>/dev/null || true)"
    grep -q 'BASIC_AUTH_USER' <<<"$secrets" && ok "BASIC_AUTH_USER is set" \
      || bad "BASIC_AUTH_USER is not set — the site will 401 for everyone"
    if grep -qE 'BASIC_AUTH_PASSWORD|BASIC_AUTH_HASH' <<<"$secrets"; then
      ok "a password or hash is set"
    else
      bad "neither BASIC_AUTH_PASSWORD nor BASIC_AUTH_HASH is set — the site will 401 for everyone"
    fi
  else
    bad "app '$app' not found — run: fly apps create $app"
  fi
fi

echo
echo "GitHub"

if ! command -v gh >/dev/null 2>&1; then
  skip "gh not installed — cannot check the FLY_API_TOKEN secret"
elif gh secret list 2>/dev/null | grep -q FLY_API_TOKEN; then
  ok "FLY_API_TOKEN repository secret is set"
else
  bad "FLY_API_TOKEN is not set — the deploy workflow cannot authenticate"
fi

echo
[ "$fail" -eq 0 ] && echo "All checks passed." || echo "Some checks failed — see above."
exit "$fail"
