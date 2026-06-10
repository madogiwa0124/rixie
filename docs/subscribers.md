# Subscribers

Rixie uses a subscriber pattern for observability. By default, a `Subscribers::Logger` is attached to every session, which logs events (task start/end, LLM calls, tool calls, etc.) via the configured `logger`.

## Built-in subscribers

| Subscriber | Output |
| --- | --- |
| `Subscribers::Logger` | Human-readable text — `[Task] started: "..."` style. Default. |
| `Subscribers::JsonLogger` | One JSON object per line. Suitable for shipping to log aggregators. |
| `Subscribers::Langfuse` | Sends traces to a [Langfuse](https://langfuse.com) instance via the ingestion API. |

Both wrap a `::Logger` instance and emit each event at a severity determined by `Subscribers::EventSeverity` — see [Log severity](#log-severity) below.

To switch the default subscriber to JSON output, set `log_format`:

```ruby
Rixie.configure do |config|
  config.logger     = Logger.new($stdout)
  config.log_format = :json   # → Subscribers::JsonLogger wrapping config.logger
end
```

If you need to fully control which subscribers are attached (e.g. to add an OpenTelemetry subscriber alongside the JSON logger), pass them via `default_subscribers` instead — that path bypasses `log_format`:

```ruby
Rixie.configure do |config|
  config.default_subscribers = [
    Rixie::Subscribers::JsonLogger.new(logger: Logger.new($stdout)),
    OpenTelemetrySubscriber.new
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
| `:debug` | `LlmCallStart`, `LlmCallEnd`, `ToolCallStart`, `ToolCallEnd` (success) |
| `:info`  | `TaskStart`, `TaskEnd`, `RunStart`, `RunEnd`, `Finished`, `CompressionStart`, `CompressionEnd` (completed) |
| `:warn`  | `ToolCallEnd` (when `result.error?`), `CompressionEnd` (failed) |

With the default `log_level = :info`, per-iteration noise (LLM calls, individual tool invocations) is silenced. Set `config.log_level = :debug` to see them, or `:warn` to surface only failures.

## Langfuse

`Subscribers::Langfuse` maps Rixie events to Langfuse's trace hierarchy and flushes them as a single batch on `TaskEnd`.

```
Task  → Langfuse Trace
  Run   → Span
    LLM call   → Generation  (model, provider, input/output tokens)
    Tool call  → Span        (arguments, result, error level)
```

### Setup

Start a local Langfuse instance with Docker Compose (a `docker-compose.yml` is included at the repo root), or use [Langfuse Cloud](https://cloud.langfuse.com) for a hosted option.

```bash
docker compose up -d     # local only
```

### Usage

```ruby
Rixie.configure do |config|
  config.default_subscribers = [
    Rixie::Subscribers::Langfuse.new(
      base_url:   ENV["LANGFUSE_BASE_URL"] || "http://localhost:3000",
      public_key: ENV["LANGFUSE_PUBLIC_KEY"],
      secret_key: ENV["LANGFUSE_SECRET_KEY"]
    )
  ]
end
```

If you want to keep the default logger alongside Langfuse:

```ruby
Rixie.configure do |config|
  config.default_subscribers = [
    Rixie::Subscribers::Logger.new(logger: config.logger),
    Rixie::Subscribers::Langfuse.new(
      base_url:   ENV.fetch("LANGFUSE_BASE_URL", "http://localhost:3000"),
      public_key: ENV["LANGFUSE_PUBLIC_KEY"],
      secret_key: ENV["LANGFUSE_SECRET_KEY"]
    )
  ]
end
```

The subscriber is also available in the [CLI](cli.md) via the `--langfuse` flag or environment variables — see [CLI — Langfuse tracing](cli.md#langfuse-tracing).

### Flush behavior

All ingestion events for a Task are buffered in memory and sent to `POST /api/public/ingestion` in a single HTTP request when `TaskEnd` fires. If the request fails (network error or non-2xx response), the error is logged at `warn` level and the agent continues normally — tracing failures are never fatal.

## Disabling the default logger

```ruby
Rixie.configure do |config|
  config.default_subscribers = []  # opt out of all default subscribers
end
```

## Adding custom subscribers

Implement `Rixie::Subscriber` and pass instances to `Session`. Here's an example that creates [OpenTelemetry](https://opentelemetry.io/) spans following the [GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/):

```ruby
require "opentelemetry/sdk"

class OpenTelemetrySubscriber < Rixie::Subscriber
  def initialize(tracer: OpenTelemetry.tracer_provider.tracer("my-app"))
    @tracer = tracer
  end

  def subscribe(listener)
    task_data = {}
    run_data  = {}
    llm_spans = {}
    tool_spans = {}

    listener.on(Rixie::Event::TaskStart) do |envelope|
      span = @tracer.start_span("invoke_agent", kind: :client, attributes: {
        "gen_ai.operation.name" => "invoke_agent"
      })
      ctx = OpenTelemetry::Trace.context_with_span(span)
      task_data[envelope.task_id] = {span: span, ctx: ctx}
    end

    listener.on(Rixie::Event::TaskEnd) do |envelope|
      entry = task_data.delete(envelope.task_id)
      next unless entry
      span = entry[:span]
      span.status = envelope.event.status == "completed" \
        ? OpenTelemetry::Trace::Status.ok
        : OpenTelemetry::Trace::Status.error("task #{envelope.event.status}")
      span.finish
    end

    listener.on(Rixie::Event::RunStart) do |envelope|
      parent_ctx = task_data[envelope.task_id]&.fetch(:ctx)
      span = @tracer.start_span("run", with_parent: parent_ctx, kind: :internal)
      ctx = OpenTelemetry::Trace.context_with_span(span)
      run_data[envelope.run_id] = {span: span, ctx: ctx}
    end

    listener.on(Rixie::Event::RunEnd) do |envelope|
      entry = run_data.delete(envelope.run_id)
      next unless entry
      span = entry[:span]
      span.status = envelope.event.status == "completed" \
        ? OpenTelemetry::Trace::Status.ok
        : OpenTelemetry::Trace::Status.error("run #{envelope.event.status}")
      span.finish
    end

    listener.on(Rixie::Event::LlmCallStart) do |envelope|
      e = envelope.event
      parent_ctx = run_data[envelope.run_id]&.fetch(:ctx)
      span = @tracer.start_span("chat #{e.model}", with_parent: parent_ctx, kind: :client, attributes: {
        "gen_ai.operation.name" => "chat",
        "gen_ai.system"         => e.provider,
        "gen_ai.request.model"  => e.model
      }.compact)
      llm_spans["#{envelope.run_id}:#{e.step_count}"] = span
    end

    listener.on(Rixie::Event::LlmCallEnd) do |envelope|
      e    = envelope.event
      span = llm_spans.delete("#{envelope.run_id}:#{e.step_count}")
      next unless span
      span.set_attribute("gen_ai.usage.input_tokens",        e.usage[:input_tokens])  if e.usage[:input_tokens]
      span.set_attribute("gen_ai.usage.output_tokens",       e.usage[:output_tokens]) if e.usage[:output_tokens]
      span.set_attribute("gen_ai.response.finish_reasons",   [e.finish_reason].compact) if e.finish_reason
      span.finish
    end

    listener.on(Rixie::Event::ToolCallStart) do |envelope|
      tc = envelope.event.tool_call
      parent_ctx = run_data[envelope.run_id]&.fetch(:ctx)
      span = @tracer.start_span("execute_tool #{tc.name}", with_parent: parent_ctx, kind: :internal, attributes: {
        "gen_ai.operation.name" => "execute_tool",
        "gen_ai.tool.name"      => tc.name,
        "gen_ai.tool.call.id"   => tc.id
      })
      tool_spans[tc.id] = span
    end

    listener.on(Rixie::Event::ToolCallEnd) do |envelope|
      result = envelope.event.result
      span   = tool_spans.delete(envelope.event.tool_call.id)
      next unless span
      span.status = result.error? \
        ? OpenTelemetry::Trace::Status.error(result.error.message)
        : OpenTelemetry::Trace::Status.ok
      span.finish
    end
  end
end

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  subscribers:  [OpenTelemetrySubscriber.new]
)
```

This produces a span tree like:

```
invoke_agent                          # Task
  └─ run                             # Run
       └─ chat gpt-4.1               # LlmCall #1
       └─ execute_tool web_search    # ToolCall
       └─ chat gpt-4.1               # LlmCall #2
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
| `Event::LlmCallStart` | `step_count: Integer`, `model: String \| nil`, `provider: String \| nil` | Before each LLM call inside the think loop |
| `Event::LlmCallEnd` | `step_count: Integer`, `usage: Hash`, `finish_reason: String \| nil` | After each LLM call returns. `usage` always has `:input_tokens` and `:output_tokens` — the provider's reported values when available, otherwise a character-length estimate (1 token ≈ 4 chars). |
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
  LlmCallEnd
  → ToolCallStart × N   (sequential, all before any execution)
  → tool execution      (parallel or sequential)
  → ToolCallEnd × N     (sequential, in tool_calls order)
  → ToolCallsCompleted
```

On the `:finish` path:

```
LlmCallStart
  LlmCallEnd
  ThoughtCompleted
  Finished
```

`Finished` is always the last event for a Run.
