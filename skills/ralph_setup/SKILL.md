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
2. Show the exact files/folders that will be copied
3. Ask for explicit confirmation BEFORE copying
4. Copy files into the target workspace
5. Report what was added/overwritten

---

## Files to Copy (Default)

- `../ralph/ralph.sh`
- `../ralph/prompt.md`
- `../ralph/AGENTS.md`
- `../ralph/prd.json.example`
- `../ralph/ralph/context/`
- `../ralph/ralph/specs/`

If the user asks for additional items, include them (for example `prd.json.example`, `README.md`, or `ralph.webp`).

---

## Safety and Confirmation

- Always ask for confirmation before copying
- If any destination paths already exist, show them and ask whether to overwrite
- If the target path does not exist, ask the user whether to create it

---

## Example Confirmation Prompt

```
I can copy these into /path/to/target:
- ../ralph/ralph.sh
- ../ralph/prompt.md
- ../ralph/AGENTS.md
- ../ralph/prd.json.example
- ../ralph/ralph/context/
- ../ralph/ralph/specs/

This may overwrite existing files. Proceed? (yes/no)
```

---

## Output

Provide a concise summary:

- Target workspace path
- Files added
- Files overwritten (if any)

Do not start running `ralph.sh` unless the user explicitly asks.
