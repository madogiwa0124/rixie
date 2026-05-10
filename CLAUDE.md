# Rixie

A Ruby gem for AI agent orchestration. Provides autonomous execution of AI agents as a standalone gem (no Rails dependency).

## Language Policy

- **Conversation**: Match the user's language.
- **Documents, commit messages, code comments**: Write in English unless the user explicitly requests otherwise.

## Development Commands

```bash
bundle install       # install dependencies
bundle exec rake     # run lint and all tests
bundle exec rake test # run tests
```

## Architecture

### Conceptual Hierarchy

```
llm_call × N → think    # Agent thinks and acts for a single input
think    × N → Run      # Unit that returns a response for a single input
Run      × N → Task     # Unit that accomplishes a single goal
Task     × N → Session  # Entire conversation
```

### Class Responsibilities

**Rixie::Agent** — Core domain object. Owns the think + act loop, LLM communication, and tool execution.

- `think(messages:, listener:)` — public: full loop (llm_call × N). Continues if tool_call is returned, exits on finish.
- `llm_call(messages:)` — private: single LLM call, returns a `Thought`.
- Owns `@tool_executor` internally (synchronous execution).

**Rixie::Agent::Thought** — `Data.define(:type, :content, :tool_calls)`. type is `:tool_call` or `:finish`.

**Rixie::Agent::ToolCall** — Owns wire format conversion knowledge. `build_from_raw` / `to_llm_format`.

**Rixie::Agent::Plan** — Agent subtype for the planning phase. Wraps a `base_agent` and appends planning instructions. Owns `PLAN_DONE_TOOL` (a no-op tool) by default.

**Rixie::Session** — Primary user-facing entry point. Resolves config defaults (`default_provider`, `default_model`, `default_max_steps`, `default_max_tokens`, `default_temperature`, `store`) and constructs `Agent` and `LLM::Client` internally. Accepts a pre-built `agent:` for advanced use cases. Manages the entire conversation and accumulates `Context::History` entries across Tasks. Failed Tasks are excluded from context.

**Rixie::Task** — Unit that accomplishes a single goal. Owns a strategy and manages a collection of Runs. Creates an `EventListener` and passes it to the strategy on execution.

**Rixie::Run** — Unit that returns a response for a single input. Calls `agent.think`. Accumulates steps via `add_step`. Returns `Context::History` via `to_history`.

**Rixie::Context::History** — Conversation history entry. Implements `to_message` returning OpenAI wire format messages (user / assistant / tool / tool_result).

**Rixie::Context::Plan** — Plan information entry. Implements `to_message` returning a system message with the full plan and current step.

**Rixie::Strategy::Simple** — Default strategy. Executes Run × 1.

**Rixie::Strategy::PlanExecute** — Plan & Execute strategy. Runs a planning phase (Run × 1 using `Agent::Plan`) then an execution phase (Run × N, one per step). Extracts the plan from the `plan_done` tool call arguments.

**Rixie::Strategy::PlanExecute::Plan** — `Data.define(:steps)`. steps is an array of `{ title:, description: }`.

**Rixie::PromptBuilder** — Assembles messages for LLM. Calls `context.flat_map(&:to_message)` uniformly regardless of context entry type.

**Rixie::ToolExecutor** — Owned by Agent. Executes tool calls and returns results. Unifies `BuiltinTools` and `MCPTools` via a common `Tool` interface.

**Rixie::EventListener** — Instance-based pub/sub (not global). Scoped to a single Task lifecycle to prevent cross-talk between concurrent sessions.

- Events emitted by Agent: `:step_completed` `{ tool_calls:, tool_results: }`, `:finished` `{ content: }`, `:token` `{ delta: }` (future).

**Rixie::LLM::Client** — HTTP communication. Resolves provider via `Client::Resolver` on initialization.

**Rixie::LLM::Client::Resolver** — Maps `provider` string to an adapter instance. Raises `NoProviderError` if `provider` is nil (resolution of `Rixie.config.default_provider` is Session's responsibility). Also merges `Rixie.config.custom_providers` into the provider registry.

**Rixie::LLM::Adapter::OpenAI** — Wraps `ruby-openai` gem (optional dependency). Supports any OpenAI-compatible endpoint via `base_url` override.

**Rixie::LLM::Adapter::Anthropic** — Wraps `anthropic` gem (optional dependency).

**Rixie::Store::Base** — Interface definition for storage adapters.

**Rixie::Store::Memory** — In-memory store (default).

**Rixie::Store::Null** — No-op store for testing.

## Key Design Decisions

**`model` and `provider` are separate arguments in `Session` and `LLM::Client`.**
Some providers (e.g. GitHub Models) serve models whose names contain another provider's name (e.g. `"openai/gpt-4o"`). Conflating provider and model into a single string would break resolution in these cases. `Agent` does not accept `model` or `provider` — it receives a pre-built `llm_client:` from `Session`.

**Strategy lives on Task, not Agent.**
Strategy determines how many Runs to execute for a goal. Placing it on Agent would conflate execution strategy with agent identity, and would clash semantically with `Agent::Plan`.

**`Agent#think` owns the loop; `Agent::Loop` does not exist as a separate class.**
Tool calling is a basic protocol of any tool-capable agent, not a strategy. The loop is absorbed into `Agent#think` directly.

**`Context` entries implement `to_message`.**
`PromptBuilder` calls `context.flat_map(&:to_message)` without needing to know the type of each entry. New context types (e.g. `Context::Memory`, `Context::RAG`) can be added by implementing `to_message`.

**`EventListener` is instance-based, not a global bus.**
Scoping the listener to each Task prevents event cross-talk when multiple Sessions run concurrently. The listener is created in `Task#execute` and passed down through `Strategy → Run → Agent#think`.

**`plan_done` is a no-op built-in tool owned by `Agent::Plan`.**
Using a tool call to signal plan completion avoids fragile text parsing, reuses the existing tool call loop, and sidesteps issues with combining `structured_output` and `tools` in the same request.

**Optional dependencies with descriptive errors.**
`ruby-openai` and `anthropic` are not runtime dependencies. Each adapter attempts `require` at load time and raises `Rixie::ConfigurationError` with an actionable message if the gem is missing.

## Error Classes

```ruby
Rixie::Error                      # base
  ├─ Rixie::ConfigurationError
  │    ├─ NoProviderError
  │    └─ UnknownProviderError
  ├─ Rixie::AgentError
  │    └─ MaxStepsExceededError
  └─ Rixie::LLM::Error
```

## Configuration

```ruby
Rixie.configure do |config|
  config.default_provider    = "anthropic"        # RIXIE_DEFAULT_PROVIDER
  config.default_model       = "claude-opus-4-5"
  config.default_max_tokens  = nil
  config.default_temperature = nil
  config.store     = Rixie::Store::Memory
  config.logger    = Logger.new($stdout)
  config.log_level = :info                       # RIXIE_LOG_LEVEL

  config.register_provider("my_proxy",
    adapter:  :openai,
    base_url: "https://my-llm-proxy.internal/v1",
    api_key:  ENV["MY_PROXY_KEY"]
  )
end
```

Built-in providers: `openai`, `anthropic`. OpenAI-compatible endpoints (GitHub Models, Ollama, etc.) can be registered via `config.register_provider`.

## Testing Approach

LLM responses are injected via `DummyAdapter` — no real HTTP requests are made in tests.

```ruby
# test/support/dummy_adapter.rb
class DummyAdapter
  def initialize(responses)
    @responses = responses.dup
  end

  def chat(messages, tools:)
    @responses.shift
  end
end
```

`Strategy::PlanExecute` tests enqueue a `plan_done` tool call response followed by per-step responses in order.

## Directory Structure

```
lib/rixie/
  agent.rb, agent/          # Core domain object + Plan subtype, ToolCall
  session.rb                # Primary entry point
  task.rb, run.rb           # Execution units
  context/                  # History, Plan — implement to_message
  strategy/                 # Simple, PlanExecute
  llm/                      # Client, Resolver, Adapter (OpenAI, Anthropic)
  store/                    # Base, Memory, Null
test/support/dummy_adapter.rb  # Inject fake LLM responses in tests
```

## Design Rules

@.claude/rules/configuration.md
