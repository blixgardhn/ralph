## Ralph Runner Internals

- Core prompts and instructions live here in the runner: see `ralph-specs/prompt.md` and `AGENTS.md` under `$RALPH_ROOT`.
- Code generation rules live in `ralph-specs/code_generation_rules/` under the runner root (`$RALPH_ROOT`).
- Runtime resources (Dockerfiles, nuget.config) are under `ralph/resources/` (runner). Target repos should copy what they need.
- Nothing is written inside `$RALPH_ROOT` at runtime; all iteration artifacts (tasks, progress, suggestions) belong under the target repo at `$TARGET_REPO_ROOT/.ralph/`.

### verify.sh

- `ralph/verify.sh` supports `VERIFY_FAST=true` for minimal checks (per stack) and a full mode by default. It prints step banners and timings. Extend per project to include lint/type/test/format as needed.

### Cache warming

- Use `scripts/warm_caches.sh` to pre-create a Docker volume cache (`CACHE_VOL`) and pre-pull the runtime image (`IMAGE`).
