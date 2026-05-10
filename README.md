# Rixie

AI agent orchestration for Ruby.

## Overview

Rixie is a standalone Ruby gem for orchestrating AI agents — no Rails required.

An **Agent** thinks and acts via an LLM and a set of tools, looping until it reaches a final answer. A **Session** manages the full conversation, accumulating history across multiple chats. A **Strategy** controls how a goal is accomplished: the default `Simple` strategy runs a single agent loop, while `PlanExecute` first builds a step-by-step plan and then executes each step in sequence.

## Installation

Add to your Gemfile:

```ruby
gem "rixie"

# Also add the provider gem you need:
gem "ruby-openai"  # for OpenAI, GitHub Models, Ollama, and other OpenAI-compatible endpoints
gem "anthropic"    # for Anthropic
```

## Configuration

```ruby
Rixie.configure do |config|
  config.default_provider  = "openai"
  config.default_model     = "gpt-4.1-mini"
  config.default_max_steps = 10
  config.store             = Rixie::Store::Memory.new
  config.logger            = Logger.new($stdout)
  config.log_level         = :info
end
```

### Built-in providers

Rixie has two built-in providers. API keys are read from environment variables.

| Provider    | env var             |
| ----------- | ------------------- |
| `openai`    | `OPENAI_API_KEY`    |
| `anthropic` | `ANTHROPIC_API_KEY` |

### OpenAI-compatible endpoints

GitHub Models, Ollama, and other OpenAI-compatible endpoints use the `:openai` adapter. Register them as a custom provider with a `base_url`:

```ruby
Rixie.configure do |config|
  # GitHub Models
  config.register_provider("github",
    adapter:  :openai,
    base_url: "https://models.github.ai/inference",
    api_key:  ENV["GITHUB_TOKEN"]
  )

  # Ollama (local)
  config.register_provider("ollama",
    adapter:  :openai,
    base_url: "http://localhost:11434/v1",
    api_key:  "ollama"
  )
end
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

## Agents and Tools

Define a tool using `Rixie::Tool`:

```ruby
weather_tool = Rixie::Tool.new(
  name:         "get_weather",
  description:  "Returns the current weather for a given city.",
  input_schema: {
    type: "object",
    properties: {
      city: { type: "string", description: "City name" }
    },
    required: ["city"]
  },
  call: ->(args) { "Sunny, 24°C in #{args["city"]}" }
)

session = Rixie::Session.new(
  instructions: "You are a weather assistant.",
  tools: [weather_tool]
)
puts session.chat("What's the weather in Tokyo?")
```

The `call` callable receives a hash of arguments and must return a string (or a value that responds to `to_s`).

## Strategies

### Strategy::Simple (default)

Runs a single agent loop until the LLM returns a final answer. Suitable for most tasks.

```ruby
session.chat("Summarize this document.", strategy: Rixie::Strategy::Simple.new)
# Strategy::Simple is the default — the strategy argument can be omitted.
```

### Strategy::PlanExecute

First asks the agent to produce a step-by-step plan, then executes each step as a separate run. Suitable for complex multi-step tasks where explicit planning improves results.

```ruby
session.chat("Research and write a report on Ruby 3.x features.",
             strategy: Rixie::Strategy::PlanExecute.new)
```

## Providers

`provider` and `model` are always specified separately. This is intentional — some providers (e.g. GitHub Models) serve models whose names contain another provider's name (`"openai/gpt-4.1"`), and a combined string would be ambiguous.

```ruby
# OpenAI
session = Rixie::Session.new(instructions: "...", provider: "openai",    model: "gpt-4.1")

# Anthropic
session = Rixie::Session.new(instructions: "...", provider: "anthropic", model: "claude-opus-4-5")

# GitHub Models (registered as custom provider)
session = Rixie::Session.new(instructions: "...", provider: "github",    model: "openai/gpt-4.1-mini")

# Ollama (registered as custom provider)
session = Rixie::Session.new(instructions: "...", provider: "ollama",    model: "llama3")
```

### Persisting sessions across requests

Use a store to save and restore conversation history:

```ruby
store = Rixie::Store::Memory.new

# First request
session = Rixie::Session.new(instructions: "You are a helpful assistant.", store: store)
session.chat("Hello, my name is Alice.")
session_id = session.session_id

# Later request — restore history and continue
context = store.load(session_id)
session = Rixie::Session.new(
  instructions:    "You are a helpful assistant.",
  store:           store,
  initial_context: context
)
puts session.chat("What's my name?")
# => "Your name is Alice."
```

`Store::Memory` keeps history in memory. Implement `Rixie::Store::Base` (`#save`, `#load`) to persist to a database or cache.
