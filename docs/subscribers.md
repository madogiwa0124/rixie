# Subscribers

Rixie uses a subscriber pattern for observability. By default, a `Subscribers::Logger` is attached to every session, which logs events (task start/end, LLM calls, tool calls, etc.) via the configured `logger`.

## Built-in subscribers

| Subscriber | Output |
| --- | --- |
| `Subscribers::Logger` | Human-readable text — `[Task] started: "..."` style. Default. |
| `Subscribers::JsonLogger` | One JSON object per line. Suitable for shipping to log aggregators. |
| `Subscribers::Langfuse` | Sends traces to a [Langfuse](https://langfuse.com) instance via the ingestion API. |
| `Subscribers::OpenTelemetry` | Exports spans to any [OpenTelemetry](https://opentelemetry.io/)-compatible backend via OTLP HTTP. |

The two logger subscribers wrap a `::Logger` instance and emit each event at a severity determined by `Subscribers::EventSeverity` — see [Log severity](#log-severity) below.

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
    Rixie::Subscribers::OpenTelemetry.new(service_name: "my-app")
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

The subscriber is also available in the [CLI](cli.md) via the `--langfuse` flag — see [CLI — Langfuse tracing](cli.md#langfuse-tracing).

### Flush behavior

All ingestion events for a Task are buffered in memory and sent to `POST /api/public/ingestion` in a single HTTP request when `TaskEnd` fires. If the request fails (network error or non-2xx response), the error is logged at `warn` level and the agent continues normally — tracing failures are never fatal.

## OpenTelemetry

`Subscribers::OpenTelemetry` exports Rixie events as OpenTelemetry spans via the OTLP HTTP exporter. Works with any OTLP-compatible backend (OpenObserve, Jaeger, Grafana Tempo, vendor APMs, ...).

```
Task  → span "task"           (root)
  Run   → span "run"
    LLM call   → span "gen_ai.chat"   (kind: client; model, provider, token usage)
    Tool call  → span "tool.<name>"   (error status when the tool fails)
```

LLM spans carry [GenAI semantic convention](https://opentelemetry.io/docs/specs/semconv/gen-ai/) attributes (`gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, ...). Failed runs/tasks and tool errors are marked with OTel error status.

### Dependencies

The OpenTelemetry gems are optional dependencies. The subscriber raises `Rixie::ConfigurationError` with instructions if they are missing:

```ruby
# Gemfile
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
```

### Setup

The `docker-compose.yml` at the repo root includes an [OpenObserve](https://openobserve.ai) service as a local backend (UI at `http://localhost:5080`, login `root@example.com` / `Complexpass#123`):

```bash
docker compose up -d
```

### Usage

```ruby
Rixie.configure do |config|
  config.default_subscribers = [
    Rixie::Subscribers::OpenTelemetry.new(
      service_name: "my-app",
      endpoint: "http://localhost:5080/api/default/v1/traces",
      headers: {"Authorization" => "Basic #{Base64.strict_encode64("root@example.com:Complexpass#123")}"}
    )
  ]
end
```

- `endpoint:` must be the **full** traces URL — it is passed to the OTLP exporter as-is (no `/v1/traces` appended). Omit it to let the exporter resolve standard `OTEL_EXPORTER_OTLP_*` env vars instead.
- `headers:` takes a plain Hash, so values need no URL encoding (unlike the `OTEL_EXPORTER_OTLP_HEADERS` env var).
- `tracer_provider:` injects a pre-configured `TracerProvider` — useful when your app already sets up OpenTelemetry globally, or in tests. When given, `endpoint:` / `headers:` are ignored.

The subscriber is also available in the [CLI](cli.md) via the `--otel` flag — see [CLI — OpenTelemetry tracing](cli.md#opentelemetry-tracing).

## Disabling the default logger

```ruby
Rixie.configure do |config|
  config.default_subscribers = []  # opt out of all default subscribers
end
```

## Adding custom subscribers

Implement `Rixie::Subscriber` and pass instances to `Session`. The example below builds a simple metrics collector that counts tokens, tool calls, and runs per session — demonstrating the `Envelope` API along the way.

```ruby
class MetricsSubscriber < Rixie::Subscriber
  attr_reader :metrics

  def initialize
    @metrics = Hash.new { |h, k| h[k] = {tokens_in: 0, tokens_out: 0, tool_calls: 0, runs: 0} }
  end

  def subscribe(listener)
    listener.on(Rixie::Event::RunStart) do |envelope|
      @metrics[envelope.session_id][:runs] += 1
    end

    listener.on(Rixie::Event::LlmCallEnd) do |envelope|
      usage = envelope.event.usage
      @metrics[envelope.session_id][:tokens_in]  += usage[:input_tokens].to_i
      @metrics[envelope.session_id][:tokens_out] += usage[:output_tokens].to_i
    end

    listener.on(Rixie::Event::ToolCallEnd) do |envelope|
      @metrics[envelope.session_id][:tool_calls] += 1
    end

    listener.on(Rixie::Event::TaskEnd) do |envelope|
      m = @metrics[envelope.session_id]
      puts "[#{envelope.session_id}] task #{envelope.event.status}: " \
           "#{m[:runs]} run(s), #{m[:tool_calls]} tool call(s), " \
           "#{m[:tokens_in] + m[:tokens_out]} tokens"
    end
  end
end

metrics = MetricsSubscriber.new
session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  subscribers:  [metrics]
)
session.chat("What is 2 + 2?")
p metrics.metrics
# => {"session-uuid" => {tokens_in: 42, tokens_out: 11, tool_calls: 0, runs: 1}}
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
| `Event::LlmCallStart` | `model: String \| nil`, `provider: String \| nil` | Before each LLM call inside the think loop. Correlate with `LlmCallEnd` via `envelope.run_id` (they strictly alternate per run); use `envelope.sequence_number` for ordering. |
| `Event::LlmCallEnd` | `usage: Hash`, `finish_reason: String \| nil` | After each LLM call returns. `usage` always has `:input_tokens` and `:output_tokens` — the provider's reported values when available, otherwise a character-length estimate (1 token ≈ 4 chars). |
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
