### Corporate proxy / CA certificates — ALWAYS REQUIRED

**Every Dockerfile in the target project must include the cert-install block. Every container build must pass the cert build args. No exceptions.** This is non-negotiable — skipping it costs an entire rebuild cycle when the container can't reach NuGet, npm, apt, or external APIs.

This applies to:

- Dockerfiles you create as part of an iteration — include the block from the start.
- **Existing Dockerfiles in the target project** — retrofit them with the cert-install ARG/RUN block if missing. Do not touch Dockerfiles in other repos or in `$RALPH_ROOT`.

The block is safe in any environment: if the cert URL env vars are empty, the `if [ -n "$PROXY_CERT_URL" ]` guard skips installation and the build works on machines without a corporate proxy. There is no downside to including it.

```dockerfile
ARG PROXY_CERT_URL=""
ARG ISSUING_CA_CERT_URL=""
ARG ROOT_CA_CERT_URL=""

RUN set -e; \
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    if [ -n "$PROXY_CERT_URL" ]; then \
      cd /usr/local/share/ca-certificates; \
      curl -O "$PROXY_CERT_URL" && mv "$(basename "$PROXY_CERT_URL")" proxy.crt; \
      [ -n "$ISSUING_CA_CERT_URL" ] && curl -O "$ISSUING_CA_CERT_URL" && mv "$(basename "$ISSUING_CA_CERT_URL")" issuing-ca.crt || true; \
      [ -n "$ROOT_CA_CERT_URL" ] && curl -O "$ROOT_CA_CERT_URL" && mv "$(basename "$ROOT_CA_CERT_URL")" root-ca.crt || true; \
      update-ca-certificates; \
    fi && \
    rm -rf /var/lib/apt/lists/*
```

**Always pass the build args** — both for ad-hoc `docker build` and via `docker-compose.yml`:

```bash
docker build \
  --build-arg PROXY_CERT_URL="${PROXY_CERT_URL:-}" \
  --build-arg ISSUING_CA_CERT_URL="${ISSUING_CA_CERT_URL:-}" \
  --build-arg ROOT_CA_CERT_URL="${ROOT_CA_CERT_URL:-}" \
  -t <tag> .
```

```yaml
build:
  args:
    PROXY_CERT_URL: ${PROXY_CERT_URL:-}
    ISSUING_CA_CERT_URL: ${ISSUING_CA_CERT_URL:-}
    ROOT_CA_CERT_URL: ${ROOT_CA_CERT_URL:-}
```

**Rules:**

- The cert-install block must appear **before** any RUN that requires network access (NuGet restore, `npm install`, `apt-get install` of remote packages, `pip install`, etc.). If you retrofit an existing Dockerfile, move/insert the block accordingly.
- `docker-compose.yml` must include the three args under `build.args` so `docker compose build` picks them up from the environment.
- If a build fails with TLS/SSL errors (e.g. `unable to get local issuer certificate`, `SSL_ERROR_SYSCALL`, NuGet `404`/`401` from a known-good feed), it is almost always a missing cert. Verify the block is present and the build args are being passed before doing anything else.
