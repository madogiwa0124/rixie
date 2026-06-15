# Rixie

A Ruby gem for AI agent orchestration. Provides autonomous execution of AI agents as a standalone gem (no Rails dependency).

## Language Policy

- **Conversation**: Match the user's language.
- **Documents, commit messages, code comments**: Write in English unless the user explicitly requests otherwise.

## Development Commands

```bash
bundle install            # install dependencies
bundle exec rake          # run lint and all tests
bundle exec rake test     # run tests
bundle exec rake coverage # run unit + integration tests with coverage (writes coverage/index.html)
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
| `Agent` | Owns the think+act loop (`think`) plus config and LLM calling. `generate` (public) runs one LLM turn and emits the `LlmCall*` events; `think` drives the loop and emits the tool/finish events. Returns `ThinkResult(content:, thoughts:)`. |
| `Agent::{Plan,ReAct}` | Subtypes wrapping a base agent with phase-specific instructions. `ReAct` forces `parallel_tool_calls: false`. |
| `Agent::StructuredOutput` | Pure parser/validator of the agent's `:finish` answer against a JSON Schema. `parse` returns a `Result(value:, error:)`; `correction_message` builds the retry nudge. No LLM/listener/loop — `Agent#think` owns the retry loop. |
| `Agent::Thought` | `Data.define(:type, :content, :tool_calls, :tool_results)`. `:tool_call` or `:finish`. |
| `Strategy::{Simple,PlanExecute,ReAct}` | How many Runs a Task executes. Lives on Task, not Agent. |
| `Context::{History,Plan,Summary}` | Conversation entries. Each implements `to_message`. |
| `PromptBuilder` | `context.flat_map(&:to_message)` — uniform per entry type. |
| `LLM::Client` + `Adapter::*` | Provider-agnostic call surface; per-provider encoding lives in the adapter. |
| `LLM::ToolCall` / `LLM::Response` | Provider-agnostic intermediate types. |
| `Tool` / `ToolExecutor` | Single concrete `Tool` class. Executor unifies built-in and MCP tools. |
| `EventListener` / `Event::*` | Per-Task instance-based pub/sub (not a global bus). |
| `Http::Client` | SSRF-protected HTTP. `allow_private:` opts out (used by MCP). `http_client:` for test injection. |
| `Store::{Base,File,Memory,Null}` | Session persistence adapters. Memory is the `Session` default; the CLI defaults to `File` (`~/.rixie/sessions.json`) so `-r` can resume. `list_sessions` returns `Store::Row` rows. |

Built-in tools and search providers are catalogued in [`.claude/rules/tool.md`](.claude/rules/tool.md).

## Key Design Decisions

**`model` and `provider` are separate arguments in `Session` and `LLM::Client`.**
Some providers (e.g. GitHub Models) serve models whose names contain another provider's name (e.g. `"openai/gpt-4o"`). Conflating provider and model into a single string would break resolution in these cases. `Agent` does not accept `model` or `provider` — it receives a pre-built `llm_client:` from `Session`.

**Strategy lives on Task, not Agent.**
Strategy determines how many Runs to execute for a goal. Placing it on Agent would conflate execution strategy with agent identity, and would clash semantically with `Agent::Plan`.

**Wrapper agents inherit the base agent's execution settings.**
`Agent::Plan`, `Agent::ReAct`, and `Agent::Compressor` build their internal `Agent` with the base agent's `max_steps` and `token_counter`, so a user-configured budget applies to every phase of a strategy instead of silently resetting to defaults. `ReAct` forces `parallel_tool_calls: false` because the ReAct protocol requires exactly one tool call per iteration. `Plan` and `Compressor` run with no tools, so `parallel_tool_calls` is irrelevant and not passed.

**`Agent#think` owns the loop; `Agent::Loop` does not exist as a separate class.**
Tool calling is a basic protocol of any tool-capable agent, not a strategy. The loop is absorbed into `Agent#think` directly, with the per-call state (`conversation`, `thoughts`, the tool-call counter) as method locals — so `think` is reentrant and `Agent` carries no per-call mutable state. One LLM turn is factored into the **public** `Agent#generate`, which emits the `LlmCall*` events itself (see [events.md](.claude/rules/events.md)): making it public is what lets the emission live in a public method without threading emit callbacks into a private helper. `generate` is self-contained — it needs no step counter, because subscribers correlate `LlmCallStart`/`LlmCallEnd` by `run_id` and the envelope already carries a `sequence_number`.

**Thought unifies per-iteration LLM decision + execution record.**
Each iteration of the think loop produces one `Thought`. `Agent#generate` returns the raw `LLM::Response`; `think` interprets it and builds the `Thought`. For `:tool_call` iterations, `think` constructs the Thought **after** the executor runs, with `tool_results` filled in. For `:finish` iterations, `tool_results` stays `nil`. This eliminates the prior split between "Thought (pre-execution)" and "Step (post-execution)", and lets `Agent#think` return the full per-iteration history via `ThinkResult.thoughts`. `Run` simply unwraps the result — no event-driven step accumulation needed.

**`Event::Finished` is the Run-terminal singleton.**
`Finished` fires exactly once per `Agent#think` call, on every exit path. On the normal `:finish` path it carries the LLM's final content (`content: String`, or a parsed `Hash` when `schema:` was supplied). On the `return_direct` path (a tool was marked `return_direct: true`), it carries `content: nil`. Subscribers can rely on "see `Finished` → the Run is done", without caring about which path was taken. `Token` and `ThoughtCompleted` are interior events; `Finished` is always last.

**Structured output is parsed at finish time, not modeled as a tool.**
Structured output is the *shape of the final answer*, not an action, so it deliberately does **not** reuse the tool-calling abstraction. `schema:` threads `Session#chat → Task → Strategy → Run → Agent#think`. The loop runs **unconstrained** — tool-calling iterations never carry the schema, so tool flows and providers that cannot combine tools + structured output are unaffected. Only on the `:finish` branch (when `schema:` is present) does `Agent#think` delegate to the private `generate_structured_output`, which parses the answer via `Agent::StructuredOutput#parse` and, on failure, appends `StructuredOutput#correction_message` and re-generates **only the finish answer** (another `generate` call with `schema:`, tools dropped), then parses again — tool calls are never re-run, avoiding duplicate side effects. Exceeding `StructuredOutput::DEFAULT_MAX_RETRIES` raises `Rixie::SchemaValidationError`.

`StructuredOutput` is a **pure** parser/validator — no `llm_client`, no `listener`, no loop. The retry loop lives in `Agent`, not injected into `StructuredOutput` as a callback: `Agent` already owns LLM calling (`generate`) and the conversation buffer, so the loop re-calls `generate` directly — no inverted control flow. The corrective messages are appended to the per-call `conversation` buffer but never enter `ThinkResult.thoughts`, so a failed/corrected attempt is **not** persisted to Session context — only the original input and the final structured output are recorded via `Run#to_history`. For `PlanExecute`, the schema constrains only the **final** step; the plan phase and intermediate steps run unconstrained. `Session#live` rejects `schema:` with `ArgumentError` — streaming requires the complete response to validate and is fundamentally incompatible with structured output.

**`max_steps` caps `:tool_call` iterations; checked as a precondition of the tool_call branch.**
The check happens after `llm_call` returns but **before** incrementing the counter and executing tools. This gives:
- `max_steps=0` ⇒ "no tool calls allowed". The LLM is called once. `:finish` → success; `:tool_call` → `MaxStepsExceededError` (without executing the tool).
- `max_steps=N` ⇒ N tool executions are allowed. The (N+1)-th `:tool_call` raises *before* executing. If the (N+1)-th LLM response is `:finish` instead, the agent terminates gracefully — the LLM is allowed to wind down at the boundary.

This trades one potentially-wasted LLM call (when the LLM keeps requesting tools past the budget) for clean `max_steps=0` semantics and graceful boundary termination.

**`Context` entries implement `to_message`.**
`PromptBuilder` calls `context.flat_map(&:to_message)` without needing to know the type of each entry. New context types (e.g. `Context::Memory`, `Context::RAG`) can be added by implementing `to_message`.

**`EventListener` is instance-based, not a global bus.**
Scoping the listener to each Task prevents event cross-talk when multiple Sessions run concurrently. The listener is created in `Task#execute` and passed down through `Strategy → Run → Agent#think` (and into `Agent#generate`, which emits the `LlmCall*` events).

**The planning phase produces the plan as structured output, not a tool call.**
`Agent::Plan` runs with **no tools** and forces `schema: Agent::Plan::PLAN_SCHEMA`, so the plan comes back as a Hash (`{"steps" => [{title, description}, …]}`) via the structured-output path. `Strategy::PlanExecute#extract_plan` reads `run.output` (the Hash). This replaced an earlier `plan_done` tool-call approach: making the model signal the plan via a tool proved fragile on weaker models — they would either *execute* the task during planning (calling the real tools) or just reply in prose, never calling `plan_done`. Two properties make structured output the better fit: (1) the plan phase exposes no tools, so the model cannot start executing; (2) structured output's corrective retry coerces a schema-conforming plan even when the model first answers in prose. The execution tools are described to the planner in the prompt (`available_tools_note`) so it can plan steps around them (e.g. a "get the current date" step using `current_time`) — safe to name because the forced schema means the model emits the steps JSON, not tool calls. The execute phase runs on the base agent, which has the real tools.

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
  │    ├─ ToolNotFoundError
  │    └─ SchemaValidationError
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
  config.default_provider    = "openai"
  config.default_model       = "gpt-4.1-mini"
  config.default_temperature = nil
  config.store               = Rixie::Store::Memory.new
  config.logger              = Logger.new($stdout)
  config.log_level           = :info
  config.log_format          = :text                       # :text (default Subscribers::Logger) | :json (Subscribers::JsonLogger). Both receive config.logger automatically.
  config.default_subscribers = nil                         # nil → [default subscriber chosen by log_format]; [] → no subscribers; pass an array to override entirely

  config.register_provider("my_proxy",
    adapter:  :openai,
    base_url: "https://my-llm-proxy.internal/v1",
    api_key:  ENV["MY_PROXY_KEY"]
  )
end
```

Built-in providers: `openai`, `ollama`. Other OpenAI-compatible endpoints (GitHub Models, etc.) can be registered via `config.register_provider`.

## Directory Structure

```
lib/rixie/
  agent.rb, agent/          # Agent (think+act loop) + Plan / ReAct / Compressor / StructuredOutput
  session.rb                # Primary entry point
  task.rb, run.rb           # Execution units
  context/                  # History, Plan — implement to_message
  strategy/                 # Simple, PlanExecute, ReAct
  llm/                      # Client, Resolver, Adapter (OpenAI, Dummy)
  store/                    # Row, Base, File, Memory, Null
  http/                     # Shared HTTP client with SSRF protection
  search/                   # Search providers (Base, DuckDuckGo, Wikipedia)
  tool/                     # Built-in tools (HumanInput, Fetch, WebSearch, WikipediaSearch,
                            #                  CurrentTime, Calculator, FileRead/List/Search + FileSandbox)
  mcp/                      # MCP HTTP client
test/support/fake_gems/     # Minimal `openai` stub to satisfy require without the real gem
```

Fake LLM responses are injected via `Rixie::LLM::Adapter::Dummy` (`lib/rixie/llm/adapter/dummy.rb`).

## Design Rules

@.claude/rules/configuration.md
@.claude/rules/testing.md
@.claude/rules/adapter.md
@.claude/rules/cli.md
@.claude/rules/events.md
@.claude/rules/tool.md
@.claude/rules/documentation.md
