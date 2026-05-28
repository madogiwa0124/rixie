# Subscribers

Rixie uses a subscriber pattern for observability. By default, a `Subscribers::Logger` is attached to every session, which logs events (task start/end, LLM calls, tool calls, etc.) via the configured `logger`.

## Built-in subscribers

| Subscriber | Output |
| --- | --- |
| `Subscribers::Logger` | Human-readable text — `[Task] started: "..."` style. Default. |
| `Subscribers::JsonLogger` | One JSON object per line. Suitable for shipping to log aggregators. |

Both wrap a `::Logger` instance and emit each event at a severity determined by `Subscribers::EventSeverity` — see [Log severity](#log-severity) below.

```ruby
Rixie.configure do |config|
  config.default_subscribers = [
    Rixie::Subscribers::JsonLogger.new(logger: Logger.new($stdout))
  ]
end
```

Each JSON record has the shape:

```json
{
  "type": "tool_call_start",
  "occurred_at": "2026-05-28T12:34:56+09:00",
  "session_id": "...",
  "task_id": "...",
  "run_id": "...",
  "seq": 7,
  "event_id": "...",
  "payload": { "tool_call": { "id": "c1", "name": "get_weather", "arguments": {"city": "Tokyo"} } }
}
```

## Log severity

`Subscribers::EventSeverity.for(event)` maps each event to a `::Logger` severity. Both built-in subscribers route through it, so the mapping cannot drift between them.

| Severity | Events |
| --- | --- |
| `:debug` | `LlmCallStart`, `ToolCallStart`, `ToolCallEnd` (success) |
| `:info`  | `TaskStart`, `TaskEnd`, `RunStart`, `RunEnd`, `Finished`, `CompressionStart`, `CompressionEnd` (completed) |
| `:warn`  | `ToolCallEnd` (when `result.error?`), `CompressionEnd` (failed) |

With the default `log_level = :info`, per-iteration noise (LLM calls, individual tool invocations) is silenced. Set `config.log_level = :debug` to see them, or `:warn` to surface only failures.

## Disabling the default logger

```ruby
Rixie.configure do |config|
  config.default_subscribers = []  # opt out of all default subscribers
end
```

## Adding custom subscribers

Implement `Rixie::Subscriber` and pass instances to `Session`. Here's an example that creates [OpenTelemetry](https://opentelemetry.io/) spans for each task and tool call:

```ruby
require "json"
require "opentelemetry/sdk"

class OpenTelemetrySubscriber < Rixie::Subscriber
  def initialize(tracer: OpenTelemetry.tracer_provider.tracer("rixie"))
    @tracer = tracer
  end

  def subscribe(listener)
    task_spans = {}
    tool_spans = {}

    listener.on(Rixie::Event::TaskStart) do |envelope|
      span = @tracer.start_span("rixie.task", attributes: {
        "rixie.session_id"    => envelope.session_id,
        "rixie.task_id"       => envelope.task_id,
        "rixie.task.input"    => envelope.event.user_input,
        "rixie.task.strategy" => envelope.event.strategy.class.name
      })
      ctx = OpenTelemetry::Trace.context_with_span(span)
      task_spans[envelope.task_id] = {span: span, ctx: ctx}
    end

    listener.on(Rixie::Event::TaskEnd) do |envelope|
      entry = task_spans.delete(envelope.task_id)
      next unless entry

      span = entry[:span]
      if envelope.event.status == "failed"
        span.status = OpenTelemetry::Trace::Status.error("task failed")
      end
      span.set_attribute("rixie.task.status", envelope.event.status)
      span.finish
    end

    listener.on(Rixie::Event::ToolCallStart) do |envelope|
      tc      = envelope.event.tool_call
      task_ctx = task_spans[envelope.task_id]&.fetch(:ctx)
      span = @tracer.start_span("rixie.tool_call",
        with_parent: task_ctx,
        attributes: {
          "rixie.tool.name"      => tc.name,
          "rixie.tool.arguments" => tc.arguments.to_json
        }
      )
      tool_spans[tc.id] = span
    end

    listener.on(Rixie::Event::ToolCallEnd) do |envelope|
      tc     = envelope.event.tool_call
      result = envelope.event.result
      span   = tool_spans.delete(tc.id)
      span&.set_attribute("rixie.tool.result", result.content)
      if result.error?
        span&.status = OpenTelemetry::Trace::Status.error(result.error.message)
      end
      span&.finish
    end
  end
end

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  subscribers:  [OpenTelemetrySubscriber.new]
)
```

Each event is delivered as an `Event::Envelope` that includes the domain event plus metadata:

| Field | Description |
| --- | --- |
| `envelope.event` | The domain event object (e.g. `Event::ToolCallStart`) |
| `envelope.occurred_at` | `Time` when the event was emitted |
| `envelope.session_id` | UUID of the session |
| `envelope.task_id` | UUID of the current task |
| `envelope.run_id` | UUID of the current run |
| `envelope.sequence_number` | Monotonically increasing per-listener counter |
| `envelope.event_id` | Unique UUID for this event emission |

## Subscribable events

All events below are delivered to subscribers via `listener.on(EventClass) { |envelope| ... }`. They are grouped by lifecycle level.

### Task lifecycle

| Event | Fields | Emitted when |
| --- | --- | --- |
| `Event::TaskStart` | `user_input: String`, `strategy: Strategy` | A task begins (one per `Session#chat` or `Session#live` call) |
| `Event::TaskEnd` | `output: String \| nil`, `status: String` | A task ends. `status` is `"completed"` or `"failed"`. |

### Run lifecycle

| Event | Fields | Emitted when |
| --- | --- | --- |
| `Event::RunStart` | `user_input: String` | A run begins (one per `Agent#think` invocation; `Strategy::Simple` fires 1×, `Strategy::PlanExecute` fires 1 + N×) |
| `Event::RunEnd` | `output: String \| nil`, `status: String` | A run ends. `status` is `"completed"` or `"failed"`. |

### Agent loop

| Event | Fields | Emitted when |
| --- | --- | --- |
| `Event::LlmCallStart` | `step_count: Integer` | Before each LLM call inside the think loop |
| `Event::ThoughtCompleted` | `thought: Agent::Thought` | The LLM returned a `:finish` response — not emitted for tool-call iterations |
| `Event::Finished` | `content: String \| nil` | Exactly once per `Agent#think` return. `nil` on the `return_direct` exit path. |

### Tool execution

| Event | Fields | Emitted when |
| --- | --- | --- |
| `Event::ToolCallStart` | `tool_call: LLM::ToolCall` | Once per tool call, before any execution in that iteration |
| `Event::ToolCallEnd` | `tool_call: LLM::ToolCall`, `result: ToolExecutor::Result` | Once per tool call, after execution. `result.error?` is true if the tool raised; the error message is returned to the LLM and the loop continues. Fires in `tool_calls` order — not completion order — even when `parallel_tool_calls: true`. |
| `Event::ToolCallsCompleted` | `tool_calls: Array<LLM::ToolCall>`, `tool_results: Array<ToolExecutor::Result>` | After all tool calls in one `:tool_call` iteration have completed |

### Streaming

| Event | Fields | Emitted when |
| --- | --- | --- |
| `Event::Token` | `delta: String` | A text chunk arrives from the LLM (streaming only; not emitted from `Session#chat`) |

### Context compression

| Event | Fields | Emitted when |
| --- | --- | --- |
| `Event::CompressionStart` | `entry_count: Integer`, `keep_recent: Integer` | Before `Session#compress!` summarizes history |
| `Event::CompressionEnd` | `status: String`, `entry_count: Integer` | After compression completes or fails. `status` is `"completed"` or `"failed"`. |

### Firing order

Within a single `:tool_call` iteration of the agent loop:

```
LlmCallStart
  → ToolCallStart × N   (sequential, all before any execution)
  → tool execution      (parallel or sequential)
  → ToolCallEnd × N     (sequential, in tool_calls order)
  → ToolCallsCompleted
```

`Finished` is always the last event for a Run. `ThoughtCompleted` fires only on the `:finish` exit path, immediately before `Finished`.
