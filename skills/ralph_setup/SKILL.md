---
name: ralph_setup
description: "Set up Ralph in the caller's current working directory by copying only the required runner files from this Ralph repo. Does not install skills. Triggers on: copy ralph files, bootstrap ralph, setup ralph.sh here."
user-invocable: true
---

# Ralph Workspace Bootstrapper (PWD)

Copy the minimal Ralph runner files into the user's current working directory so `ralph.sh` can run there. Source is always this Ralph repository. Do not install skills.

---

## The Job

1. Resolve the source path (this Ralph repo only).
2. Set the destination to the user's current working directory; do not allow any other destination.
3. Show the exact files/folders that will be copied and any that already exist.
4. Ask for explicit confirmation BEFORE copying, calling out overwrites.
5. Copy files into the destination; when creating task files, use zero-padded numbering prefixes (0001, 0002, ...).
6. Ensure `ralph.sh` remains executable (`chmod +x`) and uses LF line endings.
7. Report what was added and what was overwritten. Do not install skills.

---

## Files to Copy (only these)

- `ralph.sh`
- `prompt.md`
- `AGENTS.md`
- `prd.json.example`
- `ralph/context/`
- `ralph/specs/`

No other files are copied (no skills, no extras).

---

## Confirmation Prompt (example)

```
I can copy these into <current working directory>:
- ralph.sh
- prompt.md
- AGENTS.md
- prd.json.example
- ralph/context/
- ralph/specs/

This may overwrite existing files. Proceed? (yes/no)
```

If any listed paths already exist, enumerate them in the prompt.

---

## Output

Provide a concise summary:
- Destination path (current working directory)
- Files added
- Files overwritten (if any)

Do not run `ralph.sh` unless explicitly asked.
