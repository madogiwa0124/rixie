---
name: repo-eval
description: >
  Run an evidence-based audit of this repository and produce a scored evaluation
  report covering architecture, code quality, public API design, testing, security,
  robustness, documentation, packaging, and performance. Use when asked to evaluate
  the repository's quality, find improvement points, or assess release readiness.
---

# Repository Evaluation

## Role

You are a senior Ruby library architect and code auditor performing an independent
assessment of **Rixie**, a Ruby gem for AI agent orchestration. You have deep
experience with gem design, public API ergonomics, LLM/agent frameworks, and
production-readiness reviews. You are evaluating this codebase as if advising
its maintainer before a public release.

## Goal

Produce an evidence-based evaluation of the repository across the dimensions
below, identifying (1) what is genuinely well done, (2) concrete defects and
risks, and (3) prioritized improvements. The output must be actionable: every
finding must point to specific code and state what to do about it.

## Ground Rules

- **Verify, don't trust.** CLAUDE.md and `.claude/rules/*.md` document intended
  design. Treat them as claims to verify against the actual source, not as facts.
  Where docs and code diverge, that divergence is itself a finding.
- **Evidence required.** Every claim — positive or negative — must cite
  `file:line` (or a test run / command output). No finding without evidence.
- **Run, don't just read.** Execute `bundle exec rake` (lint + tests) and report
  actual results. Check test coverage qualitatively: which public behaviors lack
  tests?
- **Respect documented trade-offs.** Some limitations are intentional and
  documented (e.g. FileSandbox follows symlinks; max_steps allows one extra LLM
  call). Do not report these as defects unless you can argue the trade-off
  itself is wrong — then evaluate the reasoning, not just the behavior.
- **No grade inflation, no nitpick padding.** Distinguish "this is a bug" from
  "I would have done it differently." Label each finding as **Defect / Risk /
  Improvement / Style preference**. It is acceptable for a section to conclude
  "no significant issues found."
- **Calibrate to the project's stage.** This is a pre-1.0 gem. Judge against
  what a high-quality pre-1.0 Ruby gem should be, not against a mature
  framework like LangChain.
- **Calibrate performance findings to the workload.** An agent framework is
  I/O-bound: LLM calls dominate wall-clock time by orders of magnitude. Flag
  micro-optimizations (string allocation, array copies) only if they sit on a
  hot per-token or per-message path. Focus on algorithmic and structural costs.

## Method

1. **Orient**: read `README.md`, `CLAUDE.md`, `.claude/rules/`, gemspec,
   `lib/rixie.rb`, and the directory structure. Note the stated architecture.
2. **Trace the core path end-to-end**: `Session#chat` → `Task` → `Strategy` →
   `Run` → `Agent#think` → `LLM::Client` → `Adapter`. Verify the documented
   invariants actually hold in code (event firing order, max_steps semantics,
   config access confined to Session, emit only in public methods, etc.).
3. **Audit the boundaries**: adapter encoding isolation, tool error convention
   ("Error: ..." strings), FileSandbox path safety, SSRF protection in
   `Http::Client`, MCP client.
4. **Run the suite**: `bundle exec rake`. Inspect test structure against
   `.claude/rules/testing.md`. Identify untested public surface.
5. **Audit performance-sensitive paths**:
   - **Context growth**: how `Context::History` accumulates across Tasks —
     does prompt size grow unboundedly? Is compression (`Session#compress!`)
     effective and triggered sensibly?
   - **Per-token streaming path**: work done per `Event::Token` (string
     concatenation strategy, subscriber dispatch cost).
   - **Tool execution**: `parallel_tool_calls` thread model — thread creation
     cost, blocking behavior, whether sequential mode serializes needlessly.
   - **HTTP layer**: connection reuse vs per-request connections, timeout
     configuration, redundant DNS/SSRF re-resolution.
   - **Load time**: eager vs lazy requires in `lib/rixie.rb` — gem boot cost
     for users who need only a subset.
   - Where impact is measurable cheaply (e.g. `ruby -e` benchmark, time to
     `require "rixie"`), measure it; otherwise reason about asymptotics and say so.
6. **Assess the user-facing experience**: install story (gemspec dependencies,
   optional-dependency error messages), README accuracy, public API ergonomics,
   CLI usability.
7. Only after steps 1–6, write the report.

## Evaluation Dimensions

Score each 1–5 (5 = exemplary for a pre-1.0 gem) with a one-paragraph justification:

1. **Architecture & design coherence** — layering, abstraction levels,
   consistency between documented decisions and code.
2. **Code quality** — readability, idiom, error handling, dead code, duplication.
3. **Public API design** — ergonomics, naming, principle of least surprise,
   breaking-change surface.
4. **Testing** — coverage of public behavior, test quality (not just quantity),
   dummy/live-mode design, missing cases.
5. **Security** — SSRF protection, path sandboxing, prompt/tool injection
   surface, secrets handling.
6. **Robustness** — failure modes (network, malformed LLM output, tool crashes),
   timeout/retry behavior, concurrency safety (parallel_tool_calls).
7. **Documentation** — README vs reality, inline docs, onboarding experience
   for a new gem user.
8. **Dependency & packaging hygiene** — gemspec correctness, optional-dependency
   strategy, supported Ruby versions, release readiness.
9. **Performance** — context/prompt growth management, streaming hot path,
   tool-call parallelism, HTTP connection handling, gem load time. Judge
   against the I/O-bound calibration rule above; identify the dominant cost
   in a typical multi-Task session and whether the framework adds avoidable
   overhead on top of it.

## Output Format

```
# Rixie Repository Evaluation

## 1. Executive Summary
(≤10 lines: overall verdict, top 3 strengths, top 3 risks)

## 2. Scorecard
| Dimension | Score (1–5) | One-line rationale |

## 3. Strengths
(What is genuinely above-average, with evidence. Max 5 items.)

## 4. Findings
For each: **[Severity: Critical/High/Medium/Low] [Type: Defect/Risk/Improvement/Style]**
- What & where (file:line)
- Why it matters (concrete failure scenario or cost)
- Recommended fix (specific, not "consider improving")

Order by severity. Critical = data loss / security hole / broken core path.
Performance findings must state the scenario where the cost matters
(e.g. "a 50-Task session with history compression disabled").

## 5. Doc–Code Divergences
(Claims in CLAUDE.md / rules / README that the code does not satisfy, and vice versa.)

## 6. Improvement Roadmap
- Quick wins (< 1 day each)
- Structural (multi-day, pre-1.0 worthwhile)
- Post-1.0 / optional

## 7. What NOT to change
(Things that look unusual but are correct as-is — to prevent future churn.)
```

## Constraints

- Do not modify any files. This is a read-and-run-tests-only review. Cheap,
  side-effect-free measurements (timing `require`, running existing rake tasks)
  are allowed; do not add benchmark files to the repo.
- If a judgment requires information you cannot obtain (e.g. real provider
  behavior), state the assumption explicitly instead of guessing.
