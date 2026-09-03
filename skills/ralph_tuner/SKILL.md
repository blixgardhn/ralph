---
name: ralph_tuner
description: "Analyze .ralph/cost.jsonl to recommend tuning changes (tier assignments, context thresholds, expansion factor) based on real iteration data. Requires sufficient sample size — refuses to speculate on thin data. Triggers on: tune ralph, analyze ralph cost, optimize ralph settings, review cost.jsonl."
user-invocable: true
---

# Ralph Tuner

Analyze `.ralph/cost.jsonl` from a target repo where Ralph has run at least once and produce actionable tuning recommendations. **Refuses to make recommendations when data is insufficient.**

## Preconditions

- Target repo has a `.ralph/cost.jsonl` file (produced automatically by ralph.sh from commit 230173c onwards).
- `jq` is installed on the host.

## What the log contains

Each line is one iteration:
```json
{
  "ts": "2026-08-13T10:15:23+02:00",
  "iter": 3,
  "task": "T-003",
  "tier": "cheap|strong|unknown",
  "model": "github-copilot/claude-sonnet-5",
  "initial_tokens": 4560,
  "estimated_tokens": 22800,
  "expansion": 5,
  "duration_sec": 247,
  "outcome": "task_complete|continued|stopped|error|complete"
}
```

## Data-sufficiency thresholds

Before generating any recommendation, verify the sample size. If below any threshold, state exactly what is insufficient and produce no recommendations for that dimension.

| Recommendation | Minimum data required |
|---|---|
| Tier assignment for a specific task | 2+ iterations on that task with the same tier |
| Tier max-context tuning | 5+ iterations total per tier being tuned |
| Expansion factor tuning | 10+ iterations total |
| Model swap suggestion | 8+ iterations per model being compared |
| Retry-rate analysis | 5+ tasks that had at least 2 iterations each |

If total iteration count < 5, respond only with: "Insufficient data (N iterations). Run Ralph on more tasks before tuning."

## The Job

### Step 1: Load and validate

```bash
COST_LOG=".ralph/cost.jsonl"

if [ ! -f "$COST_LOG" ]; then
  echo "No cost.jsonl found. Run Ralph first."
  exit 0
fi

TOTAL=$(wc -l < "$COST_LOG")
if [ "$TOTAL" -lt 5 ]; then
  echo "Insufficient data ($TOTAL iterations). Run Ralph on more tasks before tuning."
  exit 0
fi
```

### Step 2: Compute basic aggregates

Use jq to gather the raw numbers. Do not make judgments yet.

```bash
# Iterations per tier
jq -s 'group_by(.tier) | map({
  tier: .[0].tier,
  count: length,
  avg_duration_sec: (map(.duration_sec) | add / length | floor),
  avg_est_tokens: (map(.estimated_tokens) | add / length | floor),
  max_est_tokens: (map(.estimated_tokens) | max),
  outcomes: (map(.outcome) | group_by(.) | map({(.[0]): length}) | add)
})' "$COST_LOG"

# Retries per task (task appearing >1 time)
jq -s 'group_by(.task) | map(select(length > 1)) | map({
  task: .[0].task,
  iterations: length,
  tiers: (map(.tier) | unique),
  outcomes: (map(.outcome) | unique)
})' "$COST_LOG"

# Auto-upgrade fires (expansion > base)
jq -s 'map(select(.expansion > 2 and .tier == "strong")) | length' "$COST_LOG"
```

### Step 3: Generate recommendations only where data supports them

For each potential recommendation, check the sufficiency threshold from Step 1. Structure output as:

```markdown
## Tuning Report

**Data summary:** N total iterations across M tasks (K days of data)

### Recommendations

[Only include sections where minimum data threshold is met.]

**[Recommendation title]**
- **Evidence:** concrete numbers from the log
- **Change:** exact env var / flag / PRD field change to apply
- **Expected impact:** honest estimate; no vague claims

### Skipped analyses (insufficient data)

- **[Analysis name]:** need X samples, have Y. Run more iterations before tuning this.
```

### Step 4: Common recommendation patterns

Use these only when the data supports them.

**Pattern A: Cheap tier struggling (data threshold: 5+ cheap iterations)**

Evidence: cheap tier's avg_duration_sec > 2× strong tier's avg_duration_sec on comparable estimated_tokens.

Change: lower `--cheap-max-context` so more iterations auto-upgrade to strong. Or: reassign heavy tasks to `tier: "strong"` in tasks.json.

**Pattern B: Expansion factor mismatch (threshold: 10+ iterations)**

Evidence: distribution of (actual_context_used / estimated_tokens) ratio consistently >1.5 or <0.5. Since we don't measure actual context, use duration as proxy: if strong-tier iterations with estimated < 40K still take >8min, expansion is likely under-estimating.

Change: raise `RALPH_CONTEXT_EXPANSION_BASE` from 2 to 3.

**Pattern C: Retry hotspot (threshold: 5+ tasks with retries)**

Evidence: specific task IDs appear 3+ times in the log with outcome != task_complete. Compare their `tier` and `keyFiles` count vs successfully-passing tasks.

Change: promote those specific tasks to `tier: "strong"` in the PRD, or split them into smaller tasks.

**Pattern D: Wasted strong-tier assignments (threshold: 8+ strong iterations)**

Evidence: strong-tier iterations where duration < 60s (fast completion) — the strong model was overkill.

Change: reassign those task types to `tier: "cheap"` next PRD.

**Pattern E: Model comparison (threshold: 8+ iterations per model)**

Evidence: two different models used across sessions, compare avg duration + outcome success rate.

Change: switch default model. Only recommend if p-value would be meaningful — with 8 samples per side you can only detect big differences (>30% improvement); explicitly state confidence is low.

### Step 5: Anti-patterns (do NOT do)

- **Do not** recommend changes based on a single iteration.
- **Do not** invent explanations for outliers without evidence.
- **Do not** claim savings percentages you can't verify.
- **Do not** suggest tier changes to specific tasks unless you can point to that task's own history.
- **Do not** aggregate across multiple projects unless the user explicitly asked to.
- **Do not** compare durations across different models without noting network/API variance.

## Output template

```markdown
# Ralph Tuning Report — <target_repo>

**Data:** N iterations across M tasks, spanning T days.

## Aggregate observations

- Tier split: X cheap, Y strong, Z unknown
- Avg iteration duration: cheap Xs, strong Ys
- Retry rate: R% of tasks needed >1 iteration
- Auto-upgrades fired: N times

## Actionable recommendations

### 1. [Title]

**Evidence:** [specific numbers]

**Change:**
```bash
# example
export RALPH_CONTEXT_EXPANSION_BASE=3
```

Or in target repo `.env`:
```
OPENCODE_MODEL_CHEAP_MAX_CONTEXT=32000
```

**Expected impact:** [honest, quantified where possible]

## Skipped (insufficient data)

- **Model comparison:** only one model used across all N iterations
- **Expansion tuning:** need 10+ iterations, have N
- **Task-level tier reassignment:** no task appeared >1 time with the same tier

## Do not act on these

- [Optional: patterns that looked interesting but hit sample-size wall]
```

## When to run this skill

- After a full Ralph loop completes on a real project (30+ iterations ideal).
- After noticing cheap-tier iterations feel slow.
- Before committing to a `.env` for a specific project type (game, backend, docs site).

## When NOT to run this skill

- After a single iteration.
- After a stuck-task halt (data is dominated by failure signal, not tier performance).
- Across multiple different projects unless explicitly comparing them.

## Post-completion

Print the report to stdout. Do not modify tasks.json, .env, or opencode.json — recommendations are advisory. The user applies changes manually so they can review.

**Your job is done.** Do not restart Ralph, do not apply recommendations automatically.
