# Ralph — Token Cost Economy Changes

Cumulative summary of everything shipped since the pre-summer baseline (from `5e85560`, 2026-06-something, up to `576ff05`, today). Focus: per-iteration token cost and per-session wall-clock, without dropping functionality.

## Headline (net effect since June 1)

- **Prompt payload trimmed and language-gated** — only content relevant to the target repo's language reaches the agent. Static prompt is ~13KB for Node/Python, ~23KB for .NET (down from a monolithic ~35KB that shipped every rule to every project).
- **Model routing is tiered and context-aware** — cheap for lightweight work, strong for genuinely complex tasks, auto-upgrade when the estimated runtime context is about to blow past the cheap tier's comfort zone.
- **Test output slashed** — silent-on-pass pattern turns a passing suite into ~1 line of context instead of hundreds; verbose logs go to `.ralph/last-verify.log` where the agent can grep instead of reading.
- **Container cold-start eliminated** — sidecar mode is now the default, persists across sessions, and warms dep caches in the background before the first iteration.
- **Iteration prompt is disciplined** — decision-table error handling, tight commit format, no re-reading edited files, no `ls` of `node_modules`.
- **Telemetry closed the loop** — `cost.jsonl` per-iteration log + `ralph_tuner` skill turn Ralph's own performance into a tunable, data-driven system.

## Grouped changes

### 1. Prompt shape and payload

- **Language-gated blocks** (`e364c49`) — `{{#IF_NODE|PYTHON|DOTNET}}` markers in `prompt.md`; ralph.sh strips blocks for languages not present in the target repo. Verification hints, container examples, and cache-mount guidance become language-specific. A Python project no longer receives .NET NuGet rules; a .NET project no longer receives npm examples.
- **Section extraction** (`e364c49`) — Error Handling table extracted to `ralph-specs/error-handling.md`, Browser Verification to `ralph-specs/browser-verification.md`. Prompt keeps a compact summary + reference; agent reads the full file only when the summary is insufficient. Browser section is referenced only when tasks.json mentions a browser AC (case-insensitive).
- **Conditional cert/NuGet rules** (`00f7ec4`) — CERT_RULES and NUGET_RULES only included when Dockerfiles or a .NET project are detected. Later hardened (`ec0662c`, then `e364c49`) so the rules survive prompt-cache reuse.
- **Static-first prompt restructure** (`00f7ec4`) — static instructions first, dynamic context (task JSON, progress) last. Prompt-cache-friendly ordering for providers that support prefix caching.
- **AGENTS.md removed from the iteration prompt** (`00f7ec4`) — it's meta-runner documentation, not useful to the iteration agent. ~2K tokens/iteration saved.
- **Reject `--host-mode` outright** (`e364c49`) — containers always required. Removed the dead `HOST_MODE_NOTE` substitution and its 14 references.
- **Alpine cert-install template** (`11beb06`) — `Dockerfile.alpine` added alongside the Debian `Dockerfile.template`, same build args, includes the `https:→http:` `/etc/apk/repositories` workaround for corp proxies MITM'ing the Alpine mirror. Enables Alpine base images without repo changes.

### 2. Model tier routing and context sizing

- **Two-tier model routing** (`00f7ec4`) — `--cheap-model`, `--strong-model` flags plus `OPENCODE_MODEL_CHEAP` / `OPENCODE_MODEL_STRONG` env vars. PRD-level `task.tier` field overrides heuristics. Auto-promote to strong on retries.
- **Context-size-aware auto-upgrade** (`4f1df0e`) — when estimated prompt tokens exceed `OPENCODE_MODEL_CHEAP_MAX_CONTEXT` (default 48000), Ralph auto-upgrades to strong for that iteration. Solved observed choking on tasks with large keyFiles or long progress history.
- **Runtime-expansion-aware estimation** (`6c1cb69`) — the prior `chars/4` estimate only measured Ralph's initial prompt. New formula multiplies by an expansion factor (`RALPH_CONTEXT_EXPANSION_BASE` + `keyFiles/2`, capped at 6) to model OpenCode's own system prompt + tool-call responses + reasoning tokens.
- **Tier heuristic re-tuned from real data** (`ffbdb67`) — 46 real iterations showed the old rule ("ACs mention test|verify") fired on ~90% of tasks because stock ACs include "Typecheck passes" / "Tests pass". New rule: strong only when `keyFiles ≥ 6` OR complexity keywords (`refactor`, `migrate`, `redesign`, `algorithm`, `concurrency`, `performance`, `security`, `architecture`) appear. Simulated against the two real PRDs, cheap tier now gets the work it can actually handle (int-labcraft: 8/9 tasks cheap vs. old 20% cheap).

### 3. Test and verification cost

- **Dedicated Verification Policy** (`30453e3`) — strict ordering: typecheck first, scoped tests next, full suite only as a safety net. Ordering saves both wall-clock (no tests on a broken build) and tokens (no full-suite runs when scoped passed).
- **Silent-on-pass canonical pattern** (`c288844`) — all test output redirected to `.ralph/last-verify.log`; agent sees `PASS <suite>` on success or `tail -50` + log path on failure. Cuts test-output token load 10–100× on passing runs. Language-specific hints (`vitest`/`pytest`/`dotnet test`) gated by `{{#IF_LANG}}`.
- **Full suite only when justified** (`c288844`) — the policy now says full suite runs only when changes touch shared code (utilities, config, base classes, public API). Isolated single-module changes skip full suite entirely.
- **Setup cost guidance** (`c288844`) — dep-cache volumes per language (`node_modules`, `~/.cache/pip`, `~/.nuget/packages`), reuse `docker exec <sidecar>` over `docker run --rm`, skip installs when lockfile unchanged.
- **Verify log truncation per iteration** (`64352af`) — `.ralph/last-verify.log` cleared at start of each iteration so grep only hits the current iteration's output. Prevents stale hits.
- **Fix-loop discipline** (`30453e3`) — max 3 fix attempts before creating a bugfix task; rerun the failing test first, then scoped, then full suite. No jumping straight to full-suite reruns.
- **Skipped verifications** (`30453e3`) — docs-only, config-only, and scaffold tasks bypass tests appropriately.

### 4. Iteration prompt discipline

- **Progress-inject cap** (`64352af`) — `RALPH_PROGRESS_INJECT_MAX_CHARS` (default 2000) prevents verbose progress entries from ballooning subsequent iterations.
- **Preflight injection** (`64352af`) — Step 1 tells the agent the task JSON is already injected below; do NOT re-read `.ralph/tasks.json` unless creating bugfix tasks.
- **Tight commit format** (`64352af`) — `T-XXX: <one-line summary>` max 72 chars, optional body only if needed. Prevents multi-paragraph commit narratives.
- **Error handling as a decision table** (`64352af`, then extracted in `e364c49`) — six situations, one exit each. Reduces reasoning tokens the agent spends deciding.
- **Tool-use discipline** (`64352af`) — no re-reading edited files, no `ls`/`find` in `node_modules`/`dist`/`build`/`.git`/`vendor`/`target`/`bin`/`obj`, prefer `grep` over `read` for symbol lookup, targeted reads for large files.
- **KeyFiles inlining** (`00f7ec4`) — small keyFiles (<8KB by default via `RALPH_MAX_INLINE_BYTES`) are inlined into the prompt to eliminate a tool-call round-trip per iteration.

### 5. Container mandate + private-feed integration

- **Corporate proxy/CA cert guidance** (`5e85560`, `c9a8870`, `e126bfb`) — every Dockerfile in the target project must include the cert-install block; agent retrofits existing Dockerfiles; ordering matters (certs before restore).
- **Concrete NuGet feed pattern** (`b22d3f5`, `094d547`) — agent gets an explicit mount pattern for `nuget.config` plus the `PROGET_DOTNET_TOKEN` / `NUGET_PRIVATE_FEED_URL` env vars.
- **Per-project image + `--user`** (`b52175c`) — Dockerfile.template with build-once-reuse cache guard; `--user "$(id -u):$(id -g)"` prevents root-owned mount files.
- **Private overlay env** (`b52175c`) — `~/.config/ralph-private/org-values.env` sourced at session start; org-specific values (proxy cert URLs, feed tokens) stay out of the public runner.
- **BuildKit secret for ProGet token in `docker build`** (`c391f22`) — cert mounts don't work at image build time; the pattern uses `--secret id=proget_token,env=PROGET_DOTNET_TOKEN` so the token never enters an image layer.
- **Container mandate strengthened** (`1d0c7c8`) — explicit examples, banned host commands (npm/node/npx/python/pip/dotnet), reinforced in Steps and Constraints.

### 6. Sidecar containers

- **Sidecar mode introduced** (`00f7ec4`) — long-lived containers via `--sidecar` for reuse across iterations. Health checks + resource limits + orphan restart. Opt-in.
- **Sidecar defaults overhaul** (`9248b52`) — auto-enable when Docker is reachable; deterministic names (`ralph-sidecar-<lang>-<repo-hash>`) so repeat sessions on the same repo reuse the still-running container; persist across sessions by default (opt out via `--stop-sidecars-on-exit`); parallel startup via backgrounded subshells + `wait`; background dep-cache warming (`npm ci` / `pip install -r requirements.txt` / `dotnet restore`) into named Docker volumes so warming survives container recreation. Later hotfix (`576ff05`) guards optional `RALPH_SIDECAR_*` vars under `set -u`.
- **Nested-file detection fix** (`00f7ec4`) — replaced broken `compgen -G '**/*'` with `find -maxdepth 4` so mono-repos and nested `.csproj` are detected.
- **Preflight tool check** (`00f7ec4`) — validate OpenCode reachability + permissions before starting the loop; fail fast instead of after the first slow iteration.
- **Per-iteration sidecar liveness check** (`00f7ec4`) — dead sidecar auto-restart between iterations.

### 7. Telemetry and evidence-based tuning

- **Per-iteration cost log** (`230173c`) — every iteration appends one JSON line to `.ralph/cost.jsonl` with tier, model, initial + estimated tokens, expansion, duration, outcome. Silent-skipped on write failure.
- **`ralph_tuner` skill** (`b26ac29`) — analyzes `cost.jsonl` and generates tuning recommendations for tier assignments, context thresholds, expansion factor, and model comparisons. Explicit sample-size thresholds; refuses to speculate when data is thin. Skipped-analyses section calls out what it couldn't tune due to insufficient data.
- **Corrected outcome accounting** (`ffbdb67`) — `passes:true` on disk (without an explicit `TASK_COMPLETE` promise tag) now counts as `task_complete` in `cost.jsonl`. Agents sometimes finish the work but forget the tag; this gives accurate telemetry without changing loop behavior (task selection already skipped `passes:true` tasks).

## Measured effect

**Static prompt payload after gating (bytes):**

| Target repo type | Bytes | Cross-language leaks |
|---|---|---|
| Python-only | 12,994 | none |
| Node-only | 12,469 | none |
| .NET-only | 22,717 | none (NuGet/Cert rules kept — required for .NET) |

**Per-iteration savings, aggregate estimate from the commit bodies:**

- Progress cap: 500–3000 tokens on verbose iterations.
- Verify output redirect: ~1000–3000 tokens per passing suite.
- Full-suite skip when scoped passed: ~500–1500 tokens.
- Tighter commits: 200–500 tokens.
- Decision-table error handling: 100–300 tokens.
- No re-reading edited files: 500–2000 tokens on multi-edit tasks.
- AGENTS.md removed from iteration prompt: ~2000 tokens.

**Base per-iteration cost is ~30–40% lower than the pre-summer baseline** (commit body of `64352af`), with sidecar-mode wall-clock savings on top (see below).

**Wall-clock savings from sidecar defaults (`9248b52`):**

- ~5–30s eliminated per command that would have paid `docker run --rm` cold-start.
- First-iteration dep installs (~30s–3min) moved off the critical path.
- Repeat sessions on the same repo start warm — reused container + reused named volume.

## What you should notice on your next run

1. `[Ralph][sidecar] Sidecar mode auto-enabled (Docker available)` at start.
2. Sidecars reused from a previous session — no fresh `docker run` for them.
3. Faster typecheck / test steps because `dotnet restore` / `npm ci` / `pip install` already ran in the background.
4. `[Ralph][tier]` logs promoting to strong only for genuinely complex tasks.
5. `cost.jsonl` outcomes labeled `task_complete` more accurately.
6. Test steps that pass return `PASS <suite>` and nothing else; failures return the log tail + path.

## Levers you still control

- `--no-sidecar` — disable sidecars for the session.
- `--stop-sidecars-on-exit` — remove sidecars when the loop finishes.
- `--cheap-model` / `--strong-model` — override tier models.
- `--cheap-max-context` / `--strong-max-context` — override auto-upgrade thresholds.
- `OPENCODE_MODEL_CHEAP` / `OPENCODE_MODEL_STRONG` env vars — same but persistent per session.
- `RALPH_CONTEXT_EXPANSION_BASE` — override the runtime-expansion factor.
- `RALPH_PROGRESS_INJECT_MAX_CHARS` — override the progress-injection cap.
- `RALPH_MAX_INLINE_BYTES` — override the keyFiles inline threshold.
- `task.tier: "strong"` in `tasks.json` — force a specific task to strong regardless of heuristic.

## How to evaluate whether it worked

After ~30+ iterations on a real project, run the `ralph_tuner` skill against that project's `.ralph/cost.jsonl`. It will point to concrete tier / threshold / expansion adjustments with sample-size guardrails.
