---
name: commit-message
description: "Generates a structured Git commit message (header + Motivation / Overview / Main Changes / Breaking Changes sections) from staged diffs. Use proactively whenever creating a git commit — do not write commit messages manually. Also use when the user explicitly asks to write or generate a commit message."
argument-hint: "Optionally paste extra context. The skill runs git diff automatically."
---

# Structured Commit Message Generator

## Procedure

1. Run both commands to collect inputs:
   ```sh
   git --no-pager diff --cached --stat
   git --no-pager diff --cached --minimal
   ```
2. From the diff, classify each changed file as add / change / remove / move.
3. Detect breaking changes (see hints below). If any exist, append `!` to the header prefix.
4. Output one commit message using the Style Reference below. Request missing inputs only when necessary.

## Style Reference

```md
feat: summary of diff changes

**Motivation**

why this change is needed.

**Overview**

- key point 1 of the change
- key point 2 of the change

**Main Changes**

- file/path/one.rb (add/change/remove/move): brief explanation of change

**Breaking Changes (Important)**

- description of breaking change 1
```

Omit `**Breaking Changes**` when there are none.

## Output Requirements

- Header: Conventional Commits prefix (`feat:`, `fix:`, `refactor:`, `chore:`, etc.), `!` when breaking, ≤72 chars.
- Include a scope only when clearly implied by the diff.
- Sections in order: Motivation → Overview → Main Changes → (Breaking Changes).
- "Main Changes" must label each file with add / change / remove / move explicitly.

## Breaking Change Hints

Flag as breaking when the diff shows:
- Public interface changes (method signatures, API endpoints, return types)
- Config key additions or renames (default values, env vars)
- DB migrations adding tables or required columns
- Test expectations updated to match changed behaviour
- Operational requirements introduced (HTTPS, new env var required)
