#!/bin/sh
#
# Resolve basic-auth credentials, then hand off to Caddy.
#
# Caddy's basic_auth only accepts a bcrypt hash, and producing one needs a shell
# somewhere. Hashing a plaintext password here instead means the whole deployment
# can be configured from Fly's dashboard on a phone, with no local tooling.
#
# BASIC_AUTH_HASH still wins when both are set, so a hash-based setup keeps
# working unchanged.

set -eu

BCRYPT_COST="${BCRYPT_COST:-12}"

hash_stdin() {
  # Piped rather than passed as --plaintext, so the secret never appears in this
  # container's process list. The trailing newline is required — Caddy reads
  # stdin a line at a time and fails with "Error: EOF" without one — and it is
  # stripped before hashing. A password containing a literal newline would be
  # truncated at the first one; single-line passwords only.
  caddy hash-password --bcrypt-cost "$BCRYPT_COST"
}

if [ -n "${BASIC_AUTH_HASH:-}" ]; then
  echo "entrypoint: using BASIC_AUTH_HASH as provided"
elif [ -n "${BASIC_AUTH_PASSWORD:-}" ]; then
  BASIC_AUTH_HASH="$(printf '%s\n' "$BASIC_AUTH_PASSWORD" | hash_stdin)"
  echo "entrypoint: hashed BASIC_AUTH_PASSWORD at bcrypt cost $BCRYPT_COST"
fi

# Caddy refuses to parse a basic_auth block with an empty username or password,
# so a half-configured app would crash-loop instead of serving. Substitute a
# credential nobody holds: the site answers 401 to everything, stays up, and can
# be fixed by setting the secrets without a redeploy.
if [ -z "${BASIC_AUTH_USER:-}" ] || [ -z "${BASIC_AUTH_HASH:-}" ]; then
  echo "entrypoint: BASIC_AUTH_USER and/or a password/hash are missing." >&2
  echo "entrypoint: locking the site — every request returns 401 until both are set." >&2
  BASIC_AUTH_USER="locked"
  LOCK_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  BASIC_AUTH_HASH="$(printf '%s\n' "$LOCK_SECRET" | hash_stdin || true)"
  unset LOCK_SECRET

  # Belt and braces: if hashing failed for any reason, fall back to a constant
  # whose plaintext was generated randomly and discarded. Anything is better
  # than an empty value here, which would crash-loop the machine.
  if [ -z "$BASIC_AUTH_HASH" ]; then
    BASIC_AUTH_HASH='$2a$12$ZoXMm7VONr4OKISdLR3IouD4kaKzXY0OS9AubiqCBYunPdHo5arTa'
  fi
fi

export BASIC_AUTH_USER BASIC_AUTH_HASH

# Never let the plaintext reach the served process.
unset BASIC_AUTH_PASSWORD

exec "$@"
