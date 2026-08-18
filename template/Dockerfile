# Build the Quartz site from the vault, then serve it behind HTTP basic auth.
#
# Lives at the repo root because Fly's launch flow scans the root for a
# Dockerfile before reading fly.toml. Build context is the repo root:
#   docker build -t vault-site .

# Quartz is cloned rather than vendored, so the vault repo stays a vault repo.
# Pinned to a commit — Quartz has no stable release channel and its config schema
# changes between versions. Bumping this is a deliberate act; rerun a local build
# before pushing a new ref.
ARG QUARTZ_REF=075afd3f712da0088a07f5284a7b3aba37dd61b6

FROM node:22-slim AS build
ARG QUARTZ_REF

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --filter=blob:none https://github.com/jackyzha0/quartz.git quartz \
 && git -C quartz checkout --detach "${QUARTZ_REF}"

WORKDIR /opt/quartz
RUN npm ci --no-audit --no-fund

COPY site/quartz.config.yaml ./quartz.config.yaml

COPY . /src
RUN bash /src/site/build-content.sh /src /opt/quartz/content \
 && npx quartz build

FROM caddy:2.10-alpine
COPY --from=build /opt/quartz/public /srv
COPY site/Caddyfile /etc/caddy/Caddyfile
COPY site/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 8080

# The entrypoint turns BASIC_AUTH_PASSWORD into the bcrypt hash Caddy needs, so
# the app can be configured entirely from Fly's dashboard.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
