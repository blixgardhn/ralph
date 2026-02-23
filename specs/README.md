## Ralph Runner Internals

- Core prompts and instructions live here: see `ralph/prompt.md` and `ralph/AGENTS.md`.
- Code generation rules live in `ralph/code_generation_rules/`.
- Runtime resources (Dockerfiles, nuget.config) are under `ralph/resources/`.

### verify.sh

- `ralph/verify.sh` supports `VERIFY_FAST=true` for minimal checks (per stack) and a full mode by default. It prints step banners and timings. Extend per project to include lint/type/test/format as needed.

### Cache warming

- Use `scripts/warm_caches.sh` to pre-create a Docker volume cache (`CACHE_VOL`) and pre-pull the runtime image (`IMAGE`).
