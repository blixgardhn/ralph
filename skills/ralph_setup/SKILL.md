---
name: ralph_setup
description: "Copy the Ralph runner files into another repo. Use to bootstrap ralph.sh, prompt.md, AGENTS.md, and ralph/ context/specs in a target workspace. Triggers on: copy ralph files, bootstrap ralph, setup ralph.sh in another repo."
user-invocable: true
---

# Ralph Workspace Bootstrapper

Copy the minimal Ralph runner files into another repository so `ralph.sh` can run there.

---

## The Job

1. Ask for the target workspace path (absolute path)
2. Resolve the Ralph source path
3. Show the exact files/folders that will be copied
4. Ask for explicit confirmation BEFORE copying
5. Copy files into the target workspace; when creating task files, use zero-padded numbering prefixes (0001, 0002, ...)
6. Report what was added/overwritten
7. Ensure `ralph.sh` remains executable (`chmod +x`) and uses LF line endings (fix if needed)

---

## Files to Copy (Default)

Use repo-root relative paths. Resolve the source repo first, then join these paths:

- `ralph.sh`
- `prompt.md`
- `AGENTS.md`
- `prd.json.example`
- `ralph/context/`
- `ralph/specs/`

If the user asks for additional items, include them (for example `prd.json.example`, `README.md`, or `ralph.webp`).

---

## Source Repo Resolution

- The source is always this Ralph repo (the one containing this skill). Do not ask for or use any other source path or env var.

---

## Safety and Confirmation

- Always ask for confirmation before copying
- If any destination paths already exist, show them and ask whether to overwrite
- If the target path does not exist, ask the user whether to create it
- After copying, re-assert permissions and line endings on scripts (e.g., `ralph.sh` executable, LF endings)

---

## Example Confirmation Prompt

```
I can copy these into /path/to/target:
- ralph.sh
- prompt.md
- AGENTS.md
- prd.json.example
- ralph/context/
- ralph/specs/

This may overwrite existing files. Proceed? (yes/no)
```

---

## Output

Provide a concise summary:

- Target workspace path
- Files added
- Files overwritten (if any)

Do not start running `ralph.sh` unless the user explicitly asks.
