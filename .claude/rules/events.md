# Event Emission Policy

## Core Rules

**`listener.emit` must only be written in public methods.**

**`Rixie.logger` must not be called from internal classes.** All logging goes through `Rixie::Subscribers::Logger` via events. This keeps the observable behavior centralized and lets subscribers react to every notification.

This ensures that all event emission points are visible by reading the public interface — no need to trace through private methods to understand when events fire.

## How to Apply

If a private method needs to trigger emission, pass a callback (lambda or block) from the public method instead of passing `listener` directly.

```ruby
# Good — emit is written in the public method (think), passed as a block/lambda
thought = llm_call(messages:) { |event| listener.emit(event) }

results = call_thought_tools(
  on_start: ->(tc) { listener.emit(Event::ToolCallStart.new(tool_call: tc)) },
  thought: thought,
  on_end: ->(tc, result) { listener.emit(Event::ToolCallEnd.new(tool_call: tc, result: result)) },
  parallel: @parallel_tool_calls
)

# Bad — emit is hidden inside a private method
def llm_call(messages:, listener:)
  @llm_client.call(messages) { |event| listener.emit(event) }  # ❌ emit in private
end
```

## Private Method Signature

Private methods that need to trigger events receive a block or named lambda — never `listener:` directly.

```ruby
# Good
def llm_call(messages:, &on_event)
  @llm_client.call(messages) { |event| on_event.call(event) }
end

def call_thought_tools(on_start:, thought:, on_end:, parallel:)
  thought.tool_calls.each { |tc| on_start.call(tc) }
  # ...
end

# Bad
def llm_call(messages:, listener:)   # ❌ listener leaks into private
def call_thought_tools(thought:, listener:, parallel:)  # ❌
```

## Why

- **Readability**: the full sequence of events for a Run is visible by reading `Agent#think` alone.
- **Traceability**: no need to grep private methods to find where events fire.
- **Consistency**: event emission is a public concern (observable behavior), not an implementation detail.

## Events Emitted by Agent

| Event | Payload | When |
|---|---|---|
| `Event::CompressionStart` | `{ entry_count:, keep_recent: }` | Before context compression in `Session#compress!` |
| `Event::CompressionEnd` | `{ status:, entry_count: }` | After context compression completes or fails |
| `Event::LlmCallStart` | `{ step_count: }` | Before each LLM call |
| `Event::ToolCallStart` | `{ tool_call: }` | Once per tool call, before any execution |
| `Event::ToolCallEnd` | `{ tool_call:, result: ToolExecutor::Result }` | Once per tool call, after execution (in `tool_calls` order). `result.error?` is true if the tool raised. |
| `Event::ToolCallsCompleted` | `{ tool_calls:, tool_results: }` | After all tool calls in a single `:tool_call` iteration |
| `Event::ThoughtCompleted` | `{ thought: }` | Only on `:finish` path, immediately before `Finished` |
| `Event::Finished` | `{ content: String \| nil }` | Always exactly once when `Agent#think` returns |
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
