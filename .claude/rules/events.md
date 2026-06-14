# Event Emission Policy

## Core Rules

**`listener.emit` must only be written in public methods.** In `Agent` the public emitters are `think` (the loop: `ToolCall*`, `ToolCallsCompleted`, `ThoughtCompleted`, `Finished`) and `generate` (one LLM turn: `LlmCallStart`/`LlmCallEnd` + streamed `Token`s). `Session#compress!` emits the compression events. Reading those public methods reveals the full event sequence — no need to trace private helpers.

**Internal value objects and pure collaborators must not hold the `listener` or emit.** `Agent::StructuredOutput` (pure parser), `Tool`, `Message::*`, `LLM::*`, etc. carry no listener and fire no events. A collaborator that needs to surface something observable returns a value (or yields), and the emitting public method emits.

**`Rixie.logger` must not be called from internal classes.** All logging goes through `Rixie::Subscribers::Logger` (or `Subscribers::JsonLogger`) via events. This keeps the observable behavior centralized and lets subscribers react to every notification.

**Per-event log severity lives in `Subscribers::EventSeverity`.** Both built-in subscribers (`Logger`, `JsonLogger`) dispatch through `EventSeverity.for(event)` rather than calling a fixed `@logger.info`. Adding a new event with a non-`:info` severity (e.g. a new failure event that should be `:warn`) means updating `EventSeverity` once — never duplicate the mapping inside individual subscribers.

## How to Apply

`Agent#generate` is **public** specifically so it can emit the `LlmCall*` lifecycle directly (satisfying "emit in public methods") without threading emit callbacks down to a private helper. It is self-contained — it needs no externally-supplied step number; subscribers correlate `LlmCallStart`/`LlmCallEnd` by `run_id` (they strictly alternate per run), and the envelope already carries a `sequence_number` for ordering/display.

```ruby
# Good — generate is public and emits the LlmCall* lifecycle + streamed tokens directly.
def generate(messages:, listener:, schema: nil)
  listener.emit(Event::LlmCallStart.new(model: @llm_client.model, provider: @llm_client.provider))
  response = @llm_client.call(messages, tools:, schema:) { |event| listener.emit(event) }
  # ...
  listener.emit(Event::LlmCallEnd.new(usage:, finish_reason: response.finish_reason))
  response   # returns the LLM::Response; `think` builds the Thought records
end
```

When a private helper needs an LLM turn, it calls the public `generate` (which emits) rather than emitting itself:

```ruby
# Good — the retry loop (private) re-calls the public generate; emit stays in generate.
content = generate(messages: conversation, listener:, schema:).content

# Bad — a pure collaborator holding the listener and emitting.
StructuredOutput.new(schema:, listener:)   # ❌ StructuredOutput must stay listener-free
```

## Why

- **Readability**: the full sequence of events for a Run is visible by reading the public methods (`Agent#think`, `Agent#generate`) — no need to grep private methods.
- **No callback threading**: making `generate` public lets it emit directly, avoiding `on_start` / `on_end` / `on_event` lambdas threaded into private helpers.
- **Consistency**: event emission is a public concern (observable behavior), not an implementation detail.

## Emitted Events

| Event | Payload | When |
|---|---|---|
| `Event::TaskStart` | `{ user_input:, strategy: }` | At the start of `Task#execute` |
| `Event::TaskEnd` | `{ output:, status: }` | When `Task#execute` completes (`"completed"`) or fails (`"failed"`) |
| `Event::RunStart` | `{ user_input: }` | At the start of `Run#execute` |
| `Event::RunEnd` | `{ output:, status: }` | When `Run#execute` completes or fails |
| `Event::CompressionStart` | `{ entry_count:, keep_recent: }` | Before context compression in `Session#compress!` |
| `Event::CompressionEnd` | `{ status:, entry_count: }` | After context compression completes or fails |
| `Event::LlmCallStart` | `{ model:, provider: }` | Before each LLM call. Correlate with `LlmCallEnd` by `envelope.run_id` (they strictly alternate per run); use `envelope.sequence_number` for ordering |
| `Event::LlmCallEnd` | `{ usage:, finish_reason: }` | After each LLM call returns. `usage` is `{input_tokens:, output_tokens:}` (provider-reported, or token_counter approximation) |
| `Event::ToolCallStart` | `{ tool_call: }` | Once per tool call, before any execution |
| `Event::ToolCallEnd` | `{ tool_call:, result: ToolExecutor::Result }` | Once per tool call, after execution (in `tool_calls` order). `result.error?` is true if the tool raised. |
| `Event::ToolCallsCompleted` | `{ tool_calls:, tool_results: }` | After all tool calls in a single `:tool_call` iteration |
| `Event::ThoughtCompleted` | `{ thought: }` | Only on `:finish` path, immediately before `Finished` |
| `Event::Finished` | `{ content: String \| Hash \| nil }` | Always exactly once when `Agent#think` returns. `Hash` when `schema:` (structured output) was supplied; `nil` on the `return_direct` path |
| `Event::Token` | `{ delta: }` | During streaming, once per token |

## Firing Order Invariant

Within a `:tool_call` iteration:

```
ToolCallStart × N  (sequential, all before any execution)
  → tool execution  (parallel or sequential)
  → ToolCallEnd × N  (sequential, in tool_calls order)
  → ToolCallsCompleted
```

Across the whole Run:
- `Finished` is always the last event
- On the `return_direct` exit path, `content` is `nil`
- `ThoughtCompleted` fires only on the `:finish` path, immediately before `Finished`

## Exception: ToolNotFoundError does not fire ToolCallEnd

`ToolNotFoundError` (calling a tool not registered in the Agent) propagates as an exception and skips `ToolCallEnd`/`ToolCallsCompleted`. This is intentional: it indicates a configuration bug, not a tool runtime failure. Runtime errors from a tool's `call` implementation are caught by `ToolExecutor#execute` and returned as `result.error? == true`, preserving the event invariant.
