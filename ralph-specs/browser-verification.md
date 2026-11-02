# Browser Verification

Applies to tasks with the AC `Verify in browser using dev-browser skill`.

## Handling

- If a `dev-browser` skill is available in the agent tool, use it programmatically (automated screenshot + interaction). Mark passes if successful.
- If no `dev-browser` skill is available, **defer the browser check — do NOT stop the loop**:
  1. Finish and commit all other work for the task. The other ACs (typecheck, tests) still gate the commit.
  2. Append a manual verification block to `.ralph/browser-checks.md` (create the file if missing) using the format below.
  3. Mark the task `passes: true` in `.ralph/tasks.json` and emit `<promise>TASK_COMPLETE</promise>` so the loop continues to the next task.
  4. Do **not** emit `<promise>STOP</promise>` for a browser AC. A missing dev-browser skill is expected, not a blocker — the deferred checks are summarized at the end of the run for the user to perform manually.

## Manual verification block format

Append to `.ralph/browser-checks.md`:

```
## [Task ID] — <task title>
- URL: http://localhost:<port>/<route>
- Steps: 1) …  2) …  3) …
- Expected: <describe visible outcome>
- Committed: <short git sha>
- Status: PENDING
```

Leave `Status: PENDING`. The user flips it to `DONE` after the manual visual check.
