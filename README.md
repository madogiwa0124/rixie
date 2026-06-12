# Rixie

AI agent orchestration for Ruby.

## Overview

Rixie is a standalone Ruby gem for orchestrating AI agents — no Rails required.

An **Agent** thinks and acts via an LLM and a set of tools, looping until it reaches a final answer. A **Session** manages the full conversation, accumulating history across multiple chats. A **Strategy** controls how a goal is accomplished: the default `Simple` strategy runs a single agent loop, while `PlanExecute` first builds a step-by-step plan and then executes each step in sequence.

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

## Architecture

```
Session          # manages the full conversation; accumulates history across chats
└── Task         # accomplishes a single goal; owns a Strategy
    └── Run × N  # one LLM loop per step; calls Agent#think
        └── Agent         # thinks and acts: calls the LLM, executes tools, loops until done
```

| Class | Responsibility |
| --- | --- |
| `Session` | Entry point. Resolves config, creates `Agent` and `LLM::Client`, exposes `chat` and `live`. |
| `Task` | Runs a `Strategy` and accumulates `Run` results. Manages an `EventListener`. |
| `Run` | Calls `agent.think` once. Accumulates tool-call steps. |
| `Agent` | The think-act loop: calls the LLM, executes tools, emits events. |
| `Strategy` | Controls how many Runs a Task executes. `Simple` = 1 Run; `PlanExecute` = plan + N Runs. |

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
