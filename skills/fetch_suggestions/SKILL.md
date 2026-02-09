name: fetch_suggestions
description: "List suggested improvements from sibling repos' .ralph/suggested_improvements.md relative to the Ralph runner."
user-invocable: true
---

title: Fetch Suggested Improvements
summary: Collects and prints suggested improvements from sibling repositories' .ralph/suggested_improvements.md files (read-only)
usage: "Run from the Ralph runner; scans sibling repos next to it"


# Fetch Suggested Improvements

Purpose: From the Ralph runner repo, collect and display suggested improvements from `.ralph/suggested_improvements.md` in sibling repositories that share the same parent directory as the runner. Each target repo now stores its own suggestions in its `.ralph/` directory.

## Behavior

- Discover sibling directories next to the runner repo (same parent as the current `./ralph` runner). For each sibling that contains `.ralph/suggested_improvements.md`, read and summarize or print the contents.
- Never modify target repos; read-only.
- Skip the runner repo itself.
- If none are found, say so concisely.

## Steps

1. Identify runner root: the directory containing this skill (assume invoked from the runner repo).
2. Set parent dir = `dirname(runner_root)`; list immediate subdirectories (sibling repos).
3. For each sibling (excluding the runner), check for `.ralph/suggested_improvements.md`.
4. If present, read and output the path and contents. Keep output compact.
5. If multiple files are found, separate outputs clearly.

## Output Format

- For each found file: show path and its content (or a brief summary if long). Keep it readable for CLI copy/paste.
- If none found: "No suggested improvements found in sibling repos."

## Notes

- Do not traverse recursively beyond one level of siblings.
- Read-only; do not write or mutate any files.
