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

### Core Classes

Navigation map only. Read the source for signatures; consult **Key Design Decisions** for non-obvious behavior.

| Class | Role |
|---|---|
| `Session` | User-facing entry point. Resolves config, builds `Agent` / `LLM::Client`, accumulates `Context::History` across Tasks. Failed Tasks are excluded from context. |
| `Task` | Owns a Strategy and runs it. Creates the per-Task `EventListener`. |
| `Run` | Wraps one `Agent#think` call. Unwraps `ThinkResult` into output + thoughts. |
| `Agent` | Think+act loop. Owns `@tool_executor`. Returns `ThinkResult(content:, thoughts:)`. |
| `Agent::{Plan,ReAct}` | Subtypes wrapping a base agent with phase-specific instructions. `ReAct` forces `parallel_tool_calls: false`. |
| `Agent::Thought` | `Data.define(:type, :content, :tool_calls, :tool_results)`. `:tool_call` or `:finish`. |
| `Strategy::{Simple,PlanExecute,ReAct}` | How many Runs a Task executes. Lives on Task, not Agent. |
| `Context::{History,Plan,Summary}` | Conversation entries. Each implements `to_message`. |
| `PromptBuilder` | `context.flat_map(&:to_message)` — uniform per entry type. |
| `LLM::Client` + `Adapter::*` | Provider-agnostic call surface; per-provider encoding lives in the adapter. |
| `LLM::ToolCall` / `LLM::Response` | Provider-agnostic intermediate types. |
| `Tool` / `ToolExecutor` | Single concrete `Tool` class. Executor unifies built-in and MCP tools. |
| `EventListener` / `Event::*` | Per-Task instance-based pub/sub (not a global bus). |
| `Http::Client` | SSRF-protected HTTP. `allow_private:` opts out (used by MCP). `http_client:` for test injection. |
| `Store::{Base,Memory,Null}` | Session persistence adapters. Memory is default. |

Built-in tools and search providers are catalogued in [`.claude/rules/tool.md`](.claude/rules/tool.md).

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
`openai`, `nokogiri`, and `cli-ui` are not runtime dependencies. Each requiring site wraps `require` in `begin / rescue LoadError` and raises `Rixie::ConfigurationError` with an actionable message ("X gem is required for Y. Add `gem 'X'` to your Gemfile.") if the gem is missing.
- `openai` — eager require at the top of `LLM::Adapter::OpenAI`; the adapter file itself is only loaded lazily via `Client::Resolver.adapter_class_for(:openai)`.
- `cli-ui` — eager require at the top of `CLI::Terminal`; loaded only via `bin/rixie`, so a user requiring `rixie/cli` is intentionally opting in.
- `nokogiri` — **lazy** require inside `Tool::Fetch`'s `call:` lambda and `Search::DuckDuckGo#search`, because both files are eagerly loaded from `lib/rixie.rb`. The gem must load without nokogiri; only invocation fails.

Tool-related design decisions (`.with` factory pattern, `FileSandbox` centralization, Calculator parser choice) are documented in [`.claude/rules/tool.md`](.claude/rules/tool.md).

## Error Classes

```ruby
Rixie::Error                      # base
  ├─ Rixie::ConfigurationError
  │    ├─ NoProviderError
  │    └─ UnknownProviderError
  ├─ Rixie::NotImplementedError     # raised by abstract Base classes (Search, Store, Subscriber)
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
  config.default_subscribers = nil                         # nil → [Subscribers::Logger]; [] → no subscribers; swap for [Subscribers::JsonLogger.new(logger:)] for JSON output

  config.register_provider("my_proxy",
    adapter:  :openai,
    base_url: "https://my-llm-proxy.internal/v1",
    api_key:  ENV["MY_PROXY_KEY"]
  )
end
```

Built-in provider: `openai`. OpenAI-compatible endpoints (GitHub Models, Ollama, etc.) can be registered via `config.register_provider`.

## Directory Structure

```
lib/rixie/
  agent.rb, agent/          # Core domain object + Plan / ReAct subtypes, ToolCall
  session.rb                # Primary entry point
  task.rb, run.rb           # Execution units
  context/                  # History, Plan — implement to_message
  strategy/                 # Simple, PlanExecute, ReAct
  llm/                      # Client, Resolver, Adapter (OpenAI, Dummy)
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
