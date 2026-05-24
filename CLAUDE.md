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

- `think(messages:, listener:)` — public: full loop (llm_call × N). Continues if tool_call is returned, exits on finish. Returns `ThinkResult(content:, thoughts:)`.
- `llm_call(messages:)` — private: single LLM call, returns a `Thought` with `tool_results: nil` (filled in by the loop after tool execution).
- Owns `@tool_executor` internally (synchronous execution).
- `max_steps` is enforced as a precondition on the `:tool_call` branch, checked **before** incrementing the counter or executing the tools. Counts only `:tool_call` thoughts.

**Rixie::Agent::Thought** — `Data.define(:type, :content, :tool_calls, :tool_results)`. type is `:tool_call` or `:finish`. For `:tool_call` thoughts, `tool_results` is filled in after tool execution (via `Thought#with`). For `:finish` thoughts, `tool_results` is `nil`. Provides `tool_call?` / `finish?` predicates.

**Rixie::Agent::ThinkResult** — `Data.define(:content, :thoughts)`. Return value of `Agent#think`. `content` is `String | nil` — a string for the `:finish` exit path, `nil` for the `return_direct` exit path. `thoughts` is the full per-iteration record.

**Rixie::LLM::ToolCall** — Provider-agnostic tool call (`id`, `name`, `arguments`). `from_openai_wire` parses OpenAI wire format (used in `LLM::Response.from_openai_wire`). `to_openai_wire` serializes to OpenAI wire format (used internally in `Adapter::OpenAI#encode_message`).

**Rixie::Agent::Plan** — Agent subtype for the planning phase. Wraps a `base_agent` and appends planning instructions. Owns `PLAN_DONE_TOOL` (a no-op tool) by default.

**Rixie::Agent::ReAct** — Agent subtype for ReAct (Reasoning + Acting) mode. Wraps a `base_agent` and appends ReAct instructions that require the LLM to emit a `Thought:` reasoning trace in `content` before each tool call, and to make exactly one tool call per step. Internal agent is constructed with `parallel_tool_calls: false`. `tools` pass through unchanged.

**Rixie::Session** — Primary user-facing entry point. Resolves config defaults (`default_provider`, `default_model`, `default_max_steps`, `default_max_tokens`, `default_temperature`, `store`) and constructs `Agent` and `LLM::Client` internally. Accepts a pre-built `agent:` for advanced use cases. Manages the entire conversation and accumulates `Context::History` entries across Tasks. Failed Tasks are excluded from context.

**Rixie::Task** — Unit that accomplishes a single goal. Owns a strategy and manages a collection of Runs. Creates an `EventListener` and passes it to the strategy on execution.

**Rixie::Run** — Unit that returns a response for a single input. Calls `agent.think` and unwraps `ThinkResult` into `@output` (string) and `@thoughts` (`Array<Thought>`). `find_tool_call(name)` scans across thoughts. Returns `Context::History` via `to_history`.

**Rixie::Context::History** — Conversation history entry. Implements `to_message` returning OpenAI wire format messages (user / assistant / tool / tool_result).

**Rixie::Context::Plan** — Plan information entry. Implements `to_message` returning a system message with the full plan and current step.

**Rixie::Strategy::Simple** — Default strategy. Executes Run × 1.

**Rixie::Strategy::PlanExecute** — Plan & Execute strategy. Runs a planning phase (Run × 1 using `Agent::Plan`) then an execution phase (Run × N, one per step). Extracts the plan from the `plan_done` tool call arguments.

**Rixie::Strategy::ReAct** — ReAct strategy. Wraps `task.agent` with `Agent::ReAct` and runs Run × 1. The existing tool loop in `Agent#think` produces the Thought → Action → Observation cycle, with the ReAct system prompt forcing the LLM to verbalize reasoning into `content` on each tool-call iteration.

**Rixie::Strategy::PlanExecute::Plan** — `Data.define(:steps)`. steps is an array of `{ title:, description: }`.

**Rixie::PromptBuilder** — Assembles messages for LLM. Calls `context.flat_map(&:to_message)` uniformly regardless of context entry type.

**Rixie::ToolExecutor** — Owned by Agent. Executes tool calls and returns results. Unifies `BuiltinTools` and `MCPTools` via a common `Tool` interface.

**Rixie::EventListener** — Instance-based pub/sub (not global). Scoped to a single Task lifecycle to prevent cross-talk between concurrent sessions. Used for external observability (e.g. streaming, logging) — internal state flows through return values, not events.


**Rixie::LLM::Client** — HTTP communication. Resolves provider via `Client::Resolver` on initialization.

**Rixie::LLM::Client::Resolver** — Maps `provider` string to an adapter instance. Raises `NoProviderError` if `provider` is nil (resolution of `Rixie.config.default_provider` is Session's responsibility). Also merges `Rixie.config.custom_providers` into the provider registry.

**Rixie::LLM::Adapter::OpenAI** — Wraps `ruby-openai` gem (optional dependency). Supports any OpenAI-compatible endpoint via `base_url` override.

**Rixie::Store::Base** — Interface definition for storage adapters.

**Rixie::Store::Memory** — In-memory store (default).

**Rixie::Store::Null** — No-op store for testing.

**Rixie::Http::Client** — Shared HTTP client. Enforces SSRF protection (blocks requests to private/internal addresses), decodes gzip/deflate responses, and supports timeout configuration. Accepts `http_client:` for test injection. Returns `{ status:, headers:, body: }`.

Built-in tools (`Tool::Fetch`, `WebSearch`, `WikipediaSearch`, `CurrentTime`, `Calculator`, `FileRead/List/Search`, `FileSandbox`) and search providers (`Search::Base`, `DuckDuckGo`, `Wikipedia`) are catalogued in [`.claude/rules/tool.md`](.claude/rules/tool.md).

## Key Design Decisions

**`model` and `provider` are separate arguments in `Session` and `LLM::Client`.**
Some providers (e.g. GitHub Models) serve models whose names contain another provider's name (e.g. `"openai/gpt-4o"`). Conflating provider and model into a single string would break resolution in these cases. `Agent` does not accept `model` or `provider` — it receives a pre-built `llm_client:` from `Session`.

**Strategy lives on Task, not Agent.**
Strategy determines how many Runs to execute for a goal. Placing it on Agent would conflate execution strategy with agent identity, and would clash semantically with `Agent::Plan`.

**`Agent#think` owns the loop; `Agent::Loop` does not exist as a separate class.**
Tool calling is a basic protocol of any tool-capable agent, not a strategy. The loop is absorbed into `Agent#think` directly.

**Thought unifies per-iteration LLM decision + execution record.**
Each iteration of the think loop produces one `Thought`. For `:tool_call` iterations, `tool_results` is filled in after the executor runs (via `Thought#with(tool_results: ...)`). For `:finish` iterations, `tool_results` stays `nil`. This eliminates the prior split between "Thought (pre-execution)" and "Step (post-execution)", and lets `Agent#think` return the full per-iteration history via `ThinkResult.thoughts`. `Run` simply unwraps the result — no event-driven step accumulation needed.

**`Event::Finished` is the Run-terminal singleton.**
`Finished` fires exactly once per `Agent#think` call, on every exit path. On the normal `:finish` path it carries the LLM's final content (`content: String`). On the `return_direct` path (a tool was marked `return_direct: true`), it carries `content: nil`. Subscribers can rely on "see `Finished` → the Run is done", without caring about which path was taken. `Token` and `ThoughtCompleted` are interior events; `Finished` is always last.

**`max_steps` caps `:tool_call` iterations; checked as a precondition of the tool_call branch.**
The check happens after `llm_call` returns but **before** incrementing the counter and executing tools. This gives:
- `max_steps=0` ⇒ "no tool calls allowed". The LLM is called once. `:finish` → success; `:tool_call` → `MaxStepsExceededError` (without executing the tool).
- `max_steps=N` ⇒ N tool executions are allowed. The (N+1)-th `:tool_call` raises *before* executing. If the (N+1)-th LLM response is `:finish` instead, the agent terminates gracefully — the LLM is allowed to wind down at the boundary.

This trades one potentially-wasted LLM call (when the LLM keeps requesting tools past the budget) for clean `max_steps=0` semantics and graceful boundary termination.

**`Context` entries implement `to_message`.**
`PromptBuilder` calls `context.flat_map(&:to_message)` without needing to know the type of each entry. New context types (e.g. `Context::Memory`, `Context::RAG`) can be added by implementing `to_message`.

**`EventListener` is instance-based, not a global bus.**
Scoping the listener to each Task prevents event cross-talk when multiple Sessions run concurrently. The listener is created in `Task#execute` and passed down through `Strategy → Run → Agent#think`.

**`plan_done` is a no-op built-in tool owned by `Agent::Plan`.**
Using a tool call to signal plan completion avoids fragile text parsing, reuses the existing tool call loop, and sidesteps issues with combining `structured_output` and `tools` in the same request.

**ReAct's reasoning trace lives in `Thought#content`, not a dedicated field.**
The existing tool loop in `Agent#think` is already iterative; what classic ReAct adds is an explicit `Thought:` reasoning trace emitted alongside each tool call. Modern function-calling models can fill `content` even on tool-call iterations when prompted to do so, so `Agent::ReAct` simply instructs the LLM via the system prompt and reuses the existing `Thought#content` field. Adding a separate `reasoning` field would be `nil` for all non-ReAct strategies and create dead fields on `Thought`. Provider-side structured reasoning channels (Claude Extended Thinking, OpenAI o-series) are a different concept and should be modeled separately if introduced.

**Optional dependencies with descriptive errors.**
`ruby-openai` is not a runtime dependency. The adapter attempts `require` at load time and raises `Rixie::ConfigurationError` with an actionable message if the gem is missing.

Tool-related design decisions (`.with` factory pattern, `FileSandbox` centralization, Calculator parser choice) are documented in [`.claude/rules/tool.md`](.claude/rules/tool.md).

## Error Classes

```ruby
Rixie::Error                      # base
  ├─ Rixie::ConfigurationError
  │    ├─ NoProviderError
  │    └─ UnknownProviderError
  ├─ Rixie::AgentError
  │    ├─ MaxStepsExceededError
  │    └─ ToolNotFoundError
  ├─ Rixie::LLM::Error
  │    └─ ResponseTruncatedError
  ├─ Rixie::Http::Error
  │    ├─ TimeoutError
  │    ├─ ConnectionError
  │    └─ SSRFError
  └─ Rixie::MCP::Error
       ├─ TimeoutError
       ├─ ProtocolError
       └─ RequestError
```

## Configuration

```ruby
Rixie.configure do |config|
  config.default_provider    = "openai"           # RIXIE_DEFAULT_PROVIDER
  config.default_model       = "gpt-4.1-mini"
  config.default_max_tokens  = nil
  config.default_temperature = nil
  config.store               = Rixie::Store::Memory
  config.logger              = Logger.new($stdout)
  config.log_level           = :info                       # RIXIE_LOG_LEVEL
  config.default_subscribers = nil                         # nil → [Subscribers::Logger]; [] → no subscribers

  config.register_provider("my_proxy",
    adapter:  :openai,
    base_url: "https://my-llm-proxy.internal/v1",
    api_key:  ENV["MY_PROXY_KEY"]
  )
end
```

Built-in provider: `openai`. OpenAI-compatible endpoints (GitHub Models, Ollama, etc.) can be registered via `config.register_provider`.

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
  agent.rb, agent/          # Core domain object + Plan / ReAct subtypes, ToolCall
  session.rb                # Primary entry point
  task.rb, run.rb           # Execution units
  context/                  # History, Plan — implement to_message
  strategy/                 # Simple, PlanExecute, ReAct
  llm/                      # Client, Resolver, Adapter (OpenAI, Anthropic)
  store/                    # Base, Memory, Null
  http/                     # Shared HTTP client with SSRF protection
  search/                   # Search providers (Base, DuckDuckGo, Wikipedia)
  tool/                     # Built-in tools (HumanInput, Fetch, WebSearch, WikipediaSearch,
                            #                  CurrentTime, Calculator, FileRead/List/Search + FileSandbox)
  mcp/                      # MCP HTTP client
test/support/dummy_adapter.rb  # Inject fake LLM responses in tests
```

## Design Rules

@.claude/rules/configuration.md
@.claude/rules/testing.md
@.claude/rules/adapter.md
@.claude/rules/cli.md
@.claude/rules/events.md
@.claude/rules/tool.md
