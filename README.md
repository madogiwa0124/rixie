[![Gem Version](https://img.shields.io/gem/v/rixie)](https://rubygems.org/gems/rixie)
[![CI](https://github.com/madogiwa0124/rixie/actions/workflows/main.yml/badge.svg)](https://github.com/madogiwa0124/rixie/actions/workflows/main.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.4-CC342D)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

# Rixie

AI agent orchestration for Ruby.

## Overview

Rixie is a standalone Ruby gem for orchestrating AI agents — no Rails required.

An **Agent** thinks and acts via an LLM and a set of tools, looping until it reaches a final answer. A **Session** manages the full conversation, accumulating history across multiple chats. A **Strategy** controls how a goal is accomplished: the default `Simple` strategy runs a single agent loop, while `PlanExecute` first builds a step-by-step plan and then executes each step in sequence.

> **Status:** Rixie is in its `0.x` series and pre-1.0 — the public API may still change between minor versions. It runs on Ruby 3.4+ and is exercised in CI on Ruby 3.4 and 4.0 with unit tests, integration tests, and a dependency vulnerability audit (`bundler-audit`).

## Why Rixie?

Say you're building a research assistant. In a single conversation, a user might fire off a quick factual question, then ask for a deep multi-step investigation, then want to see exactly how the agent reasoned through one tricky step. Each of those wants a different execution strategy — a single loop, plan-then-execute, an explicit reasoning trace — yet they're all the same conversation, building on the same accumulated context.

Rixie is built for exactly that: **a small, dependency-light orchestration layer that lets you switch reasoning strategy per call within a single, context-carrying session.** Concretely:

- **A pure-Ruby core.** The only runtime dependency is the standard-library [`logger`](https://github.com/ruby/logger); `openai` / `nokogiri` / `cli-ui` are loaded lazily, only for the features you use. No transitive tree to audit, no version conflicts dragged into your `Gemfile`, and no coupling to Rails.
- **Per-call strategy switching.** Strategy is a `chat` argument, not a pre-wired graph (see [Quick Start](#quick-start)). It lives on the `Task`, not the `Agent`, so the agent stays the same while how it tackles a goal varies turn by turn — with the conversation's context shared automatically.
- **A small architecture you can read in one sitting.** Five layers, linearly stacked (see [Architecture](#architecture)). No hidden global event bus, no DSL, no metaprogramming — extending Rixie means implementing one plain object (a strategy, an adapter, or a `Tool`).

## Installation

Add to your Gemfile:

```ruby
gem "rixie"
```

Rixie keeps its runtime footprint small. The following gems are **optional** — add them only for the features you actually use. Each is loaded lazily and raises `Rixie::ConfigurationError` with an actionable message if missing.

```ruby
gem "openai"     # required for the openai / ollama provider adapter (and any OpenAI-compatible endpoint)
gem "nokogiri"   # required for Rixie::Tool::Fetch and Rixie::Tool::WebSearch (DuckDuckGo HTML parsing)
gem "cli-ui"     # required to run the `rixie` CLI (bin/rixie)
```

## Quick Start

```ruby
require "rixie"

Rixie.configure do |config|
  config.default_provider = "openai"
  config.default_model    = "gpt-4.1-mini"
end

session = Rixie::Session.new(instructions: "You are a helpful assistant.")
puts session.chat("What is the capital of France?")
# => "The capital of France is Paris."
```

Give the agent tools and it decides when to call them, loops until it has an answer, and carries the result into the rest of the conversation. Both tools below are pure Ruby — no extra gems required:

```ruby
session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  tools: [Rixie::Tool::Calculator, Rixie::Tool::CurrentTime]
)

# The agent calls the calculator tool, then answers from its result.
puts session.chat("What is 1234 * 5678?")
# => "1234 × 5678 = 7,006,652."

# The same session still has the previous turn in context.
puts session.chat("And what year is it right now?")
# => "It's 2026."
```

Pick a reasoning strategy per call by passing `strategy:`. The session carries context across them, so you can answer simply, plan a heavier step, or surface an explicit reasoning trace — all in one conversation:

```ruby
# Default: a single agent loop.
session.chat("Outline a blog post about Ruby's Ractor.")

# Plan-then-execute: build a step-by-step plan, then run each step.
session.chat("Now write the full draft.",
             strategy: Rixie::Strategy::PlanExecute.new)

# ReAct: emit a Thought → Action → Observation trace you can inspect.
session.chat("Fact-check the draft's performance claims.",
             strategy: Rixie::Strategy::ReAct.new)
```

## Architecture

```
Session          # manages the full conversation; accumulates history across chats
└── Task         # accomplishes a single goal; owns a Strategy
    └── Run × N  # one LLM loop per step; calls Agent#think
        └── Agent         # thinks and acts: calls the LLM, executes tools, loops until done
```

| Class      | Responsibility                                                                              |
| ---------- | ------------------------------------------------------------------------------------------- |
| `Session`  | Entry point. Resolves config, creates `Agent` and `LLM::Client`, exposes `chat` and `live`. |
| `Task`     | Runs a `Strategy` and accumulates `Run` results. Manages an `EventListener`.                |
| `Run`      | Calls `agent.think` once. Accumulates tool-call steps.                                      |
| `Agent`    | The think-act loop: calls the LLM, executes tools, emits events.                            |
| `Strategy` | Controls how many Runs a Task executes. `Simple` = 1 Run; `PlanExecute` = plan + N Runs.    |

## Features

- **[Configuration](docs/configuration.md)** — Configure providers, models, and persistence. Use OpenAI-compatible endpoints (GitHub Models, Ollama) or plug in a custom LLM adapter.
- **[CLI](docs/cli.md)** — Interactive REPL with slash commands, tab completion, and extensibility via custom commands and tools.
- **[Tools](docs/tools.md)** — Define your own tools and use the built-ins: web (Fetch, WebSearch, WikipediaSearch), filesystem (FileRead, FileList, FileSearch), utilities (CurrentTime, Calculator), and HumanInput for human-in-the-loop flows.
- **[Strategies](docs/strategies.md)** — `Simple` for single-loop tasks, `PlanExecute` for plan-then-execute multi-step tasks, `ReAct` for explicit Thought → Action → Observation reasoning traces.
- **[MCP](docs/mcp.md)** — Connect to any MCP (Model Context Protocol) server over HTTP and import its tools automatically.
- **[Multi-Agent Orchestration](docs/multi-agent.md)** — Compose agents by wrapping a `Session` as a tool, with isolated context per sub-agent.
- **[Subscribers](docs/subscribers.md)** — Observe agent behavior via the event bus — built-in logging, Langfuse and OpenTelemetry tracing, plus pluggable custom subscribers.
- **[Streaming](docs/streaming.md)** — Stream tokens, tool calls, and lifecycle events via `Session#live`.
- **[Context Compression](docs/context-compression.md)** — Summarize accumulated history to control token usage in long sessions.
- **[Store and Session Persistence](docs/store.md)** — Persist and resume conversations with a default store or per-session store overrides.
