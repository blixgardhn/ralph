# Browser Verification

Applies to tasks with the AC `Verify in browser using dev-browser skill`.

## Handling

- If a `dev-browser` skill is available in the agent tool, use it programmatically (automated screenshot + interaction). Mark passes if successful.
- If no `dev-browser` skill is available:
  1. Add a "Manual Verification Steps" block to `.ralph/progress.md` with concrete instructions (URL, expected UI state, interactions to perform).
  2. Exit the iteration with `<promise>STOP</promise>` explaining the browser AC needs human sign-off.
  3. The user sets `passes: true` after visual check, then restarts the loop.
- Other ACs (typecheck, tests) still gate the commit even when the browser AC is deferred.

## Manual verification block format

```
## Manual Verification Steps — [Task ID]
- URL: http://localhost:<port>/<route>
- Steps: 1) …  2) …  3) …
- Expected: <describe visible outcome>
- Blocked by: no dev-browser skill available in this agent tool
```
