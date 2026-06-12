# Documentation Update Policy

## Core Rule

**A change to observable behavior ships with its documentation in the same commit.** Code-complete means docs-complete — do not leave CHANGELOG or docs updates for a follow-up.

## Update Checklist by Change Type

| Change | Required updates |
|---|---|
| New / changed / removed public API (class, method, option) | `CHANGELOG.md` `[Unreleased]` + the relevant `docs/*.md` |
| New CLI option or slash command | `docs/cli.md` (options / commands table) + `CHANGELOG.md` |
| New built-in tool or search provider | `.claude/rules/tool.md` catalog + `docs/tools.md` + `CHANGELOG.md` |
| New store / adapter / subscriber / strategy | `CLAUDE.md` Core Classes table + relevant `docs/*.md` + `CHANGELOG.md` |
| New class listed in a directory whose `CLAUDE.md` Directory Structure entry names classes | Update that entry |
| New or changed config attribute | `CLAUDE.md` Configuration example + `docs/configuration.md` + `CHANGELOG.md` |
| Layer boundary / design rule change (incl. new exceptions) | The corresponding `.claude/rules/*.md` |
| Internal refactor with no observable behavior change | No CHANGELOG entry (Keep a Changelog: notable changes only); update rules/docs only if they describe the old structure |

When a task is done, grep docs for the names of anything you renamed or removed — stale identifiers in `docs/`, `CLAUDE.md`, `.claude/rules/`, and `README.md` are update leaks.

## CHANGELOG Conventions

- Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add entries under `## [Unreleased]` in the matching subsection (`Added` / `Changed` / `Fixed` / `Removed`).
- Write in English. Describe user-visible behavior and name the classes/options involved (e.g. `` `Rixie::Store::File` — JSON file persistence store ``).
- One entry per user-facing capability, not per file or per refactor step.

## Code Examples in Docs Must Run

Every code example in `docs/` and `CLAUDE.md` must be executable as written against the current API. When changing an interface, search docs for usage examples of it and fix them — a doc example that passes the wrong type (e.g. a class where an instance is required) is a bug, not a style issue.

## What NOT to Do

```text
# Bad — feature committed, docs "later"
feat: add Store::File          # CHANGELOG.md / docs/store.md untouched

# Bad — renamed a class but only updated lib/ and test/
SessionListRow → Row           # docs/store.md still shows SessionListRow

# Bad — changelog entry for an internal-only refactor
- Extracted preview_from into Store::Base   # not user-visible; omit
```
