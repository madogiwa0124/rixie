# Streaming

`Session#live` returns an `Enumerator` that yields `Event::Envelope` objects as the LLM generates its response. Pattern match on `envelope.event` to handle each event type. These are the same events delivered to subscribers — `live` and `subscribe` share the same event bus.

```ruby
session = Rixie::Session.new(instructions: "You are a helpful assistant.")

session.live("Tell me about Ruby.").each do |envelope|
  case envelope.event
  in Rixie::Event::Token[delta:]
    print delta
    $stdout.flush
  in Rixie::Event::ToolCallStart[tool_call:]
    puts "\n[calling #{tool_call.name}...]"
  in Rixie::Event::ToolCallEnd[tool_call:, result:]
    puts "[#{tool_call.name} → #{result.content}]"
  in Rixie::Event::Finished[content:]
    puts "\n[done] #{content}"
  else
  end
end
```

## Event types

| Class | Fields | Emitted when |
| --- | --- | --- |
| `Rixie::Event::Token` | `delta: String` | A text chunk arrives from the LLM |
| `Rixie::Event::ToolCallStart` | `tool_call: LLM::ToolCall` | A tool call is about to execute |
| `Rixie::Event::ToolCallEnd` | `tool_call: LLM::ToolCall`, `result: ToolExecutor::Result` | A tool call has completed. `result.content` is the tool output; `result.error?` is true if the tool raised — the error is returned to the LLM as the tool result and the agent continues its loop. Fires in `tool_calls` order — not completion order — even when `parallel_tool_calls: true`. |
| `Rixie::Event::ToolCallsCompleted` | `tool_calls: Array`, `tool_results: Array` | All tool calls in one LLM iteration have completed |
| `Rixie::Event::ThoughtCompleted` | `thought: Thought` | The LLM returned a finish response (not emitted for tool-call iterations) |
| `Rixie::Event::Finished` | `content: String \| nil` | The agent produces its final answer. `nil` on the `return_direct` exit path. |

`Event::Finished#content` is the full concatenated response — the same string you would get from `session.chat`. See [Subscribers › Subscribable events](subscribers.md#subscribable-events) for the full event catalog (task/run lifecycle, compression, etc. — these are also delivered through `live`).

## Streaming with tool use

`live` supports tools the same way `chat` does. `ToolCallStart` and `ToolCallEnd` fire around each individual tool execution, making it possible to show real-time progress.

```ruby
session = Rixie::Session.new(
  instructions: "You are a weather assistant.",
  tools: [weather_tool]
)

session.live("What's the weather in Tokyo?").each do |envelope|
  case envelope.event
  in Rixie::Event::Token[delta:]          then print delta
  in Rixie::Event::ToolCallStart[tool_call:] then puts "\n[calling #{tool_call.name}...]"
  in Rixie::Event::ToolCallEnd[tool_call:, result:] then puts "[done #{tool_call.name}: #{result.content}]"
  in Rixie::Event::Finished[content:]     then puts "\n#{content}"
  else # ignore ToolCallsCompleted, ThoughtCompleted
  end
end
```

## Collecting the full response

If you only need the final text, convert to an array and find `Finished`:

```ruby
envelopes = session.live("Summarize Ruby in one sentence.").to_a
output    = envelopes.find { |e| e.event.is_a?(Rixie::Event::Finished) }.event.content
```

## Context and history

`live` participates in the same context as `chat`. Tasks from both methods are accumulated and passed to subsequent calls.

```ruby
session.chat("My name is Alice.")
session.live("What's my name?").each { |e| print e.event.delta if e.event.is_a?(Rixie::Event::Token) }
# streams: "Your name is Alice."
```

## Using a custom stream client

By default, `Session` creates a second streaming-enabled LLM client automatically from your configured `default_provider` and `default_model`. To use a different model or endpoint for streaming, pass `stream_client:` explicitly:

```ruby
stream_client = Rixie::LLM::Client.new(
  provider: "openai",
  model:    "gpt-4.1-mini",
  stream:   true
)

session = Rixie::Session.new(
  instructions:  "You are a helpful assistant.",
  stream_client: stream_client
)
```
