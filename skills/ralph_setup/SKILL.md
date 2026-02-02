---
name: ralph_setup
description: "Copy only the required Ralph runner files into the requesting repo (current working directory). Source is always this Ralph repo. Does not install skills. Triggers on: copy ralph files, bootstrap ralph, setup ralph.sh in another repo."
user-invocable: true
---

# Ralph Workspace Bootstrapper

Copy the minimal Ralph runner files into another repository so `ralph.sh` can run there.

---

## The Job

1. Resolve the source path (this Ralph repo only)
2. Set the destination to the user's current working directory (no other destination)
3. Show the exact files/folders that will be copied
4. Ask for explicit confirmation BEFORE copying
5. Copy files into the destination; when creating task files, use zero-padded numbering prefixes (0001, 0002, ...)
6. Report what was added/overwritten
7. Ensure `ralph.sh` remains executable (`chmod +x`) and uses LF line endings (fix if needed)

---

## Files to Copy (Default)

Copy only these repo-root-relative paths from the Ralph source repo:

- `ralph.sh`
- `prompt.md`
- `AGENTS.md`
- `prd.json.example`
- `ralph/context/`
- `ralph/specs/`
Do not copy any other files (no skills, no extras).

---

## Source Repo Resolution

- Always use this Ralph repository as the source (honor `RALPH_SOURCE_DIR` only when set to this repo path).

## Destination

- Always use the user's current working directory as the destination; do not prompt for or write elsewhere.

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
