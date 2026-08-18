```bash
fly apps create __APP_NAME__

fly secrets set --app __APP_NAME__ \
  BASIC_AUTH_USER='you' \
  BASIC_AUTH_PASSWORD='a-real-password'

fly tokens create deploy -x 8760h    # → GitHub repo secret FLY_API_TOKEN

git init && git add -A && git commit -m "init" && fly deploy
```

The password is plaintext on purpose: the container hashes it with bcrypt at startup, so
setup works from Fly's dashboard on a phone with no tooling. `BASIC_AUTH_HASH` takes
precedence if you would rather Fly stored a hash.

**Do not run `fly launch`.** It is a bootstrapper: it detects a runtime and *generates* a
`fly.toml`, overwriting the one here. `fly apps create` then `fly deploy`.

Missing credentials fail closed and the app stays up — it answers 401 to everything until
the secrets land, then works without a redeploy.
