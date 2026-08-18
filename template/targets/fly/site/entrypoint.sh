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

if [ -n "${BASIC_AUTH_HASH:-}" ]; then
  echo "entrypoint: using BASIC_AUTH_HASH as provided"
elif [ -n "${BASIC_AUTH_PASSWORD:-}" ]; then
  # Piped rather than passed as --plaintext, so the password never appears in
  # this container's process list. The trailing newline is required — Caddy reads
  # stdin a line at a time and fails with "Error: EOF" without one — and it is
  # stripped before hashing. A password containing a literal newline would be
  # truncated at the first one; single-line passwords only.
  BASIC_AUTH_HASH="$(printf '%s\n' "$BASIC_AUTH_PASSWORD" | caddy hash-password --bcrypt-cost "$BCRYPT_COST")"
  export BASIC_AUTH_HASH
  echo "entrypoint: hashed BASIC_AUTH_PASSWORD at bcrypt cost $BCRYPT_COST"
else
  echo "entrypoint: neither BASIC_AUTH_PASSWORD nor BASIC_AUTH_HASH is set." >&2
  echo "entrypoint: every request will return 401 until one is configured." >&2
  BASIC_AUTH_HASH=""
  export BASIC_AUTH_HASH
fi

if [ -z "${BASIC_AUTH_USER:-}" ]; then
  echo "entrypoint: BASIC_AUTH_USER is not set; no credential can match." >&2
  BASIC_AUTH_USER=""
  export BASIC_AUTH_USER
fi

# Never let the plaintext reach the served process.
unset BASIC_AUTH_PASSWORD

exec "$@"
