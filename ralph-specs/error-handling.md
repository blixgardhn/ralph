# Error Handling

Decision tree — pick exactly one exit path per iteration.

| Situation | Action | Promise tag |
|---|---|---|
| Task done, others remain | Commit, mark `passes: true`, log briefly | `<promise>TASK_COMPLETE</promise>` |
| All tasks now pass | Commit, mark `passes: true`, log briefly | `<promise>COMPLETE</promise>` |
| Fixable failure (verify/test) | Fix inline; max 3 attempts | (retry, no promise until done) |
| Blocker needs new task | Create bugfix task via PRD skill, set `dependsOn` | (exit silently, no promise) |
| Environment broken (perms, missing creds, tool refuses) | Describe fix in output | `<promise>ERROR</promise>` |
| Gave up after real attempts | List what you tried | `<promise>STOP</promise>` |

## Rules

- Use `dependsOn` sparingly — only for true ordering dependencies.
- Never emit `exit`. Never switch tasks mid-iteration.
- After 3 failed fix attempts, stop retrying and create a bugfix task instead.
- When creating a bugfix task, set `dependsOn` to the current task ID so it runs after the current work.
