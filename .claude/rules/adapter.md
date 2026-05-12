# Adapter Boundary Policy

## Core Rule

**Provider-specific encoding and decoding must be confined to `LLM::Adapter::*`.**

Internal objects (`Message::*`, `Tool`, `LLM::ToolCall`, `LLM::Response`) are provider-agnostic. Conversion to and from any provider's wire format happens only inside the adapter. This means a user can add support for a new LLM provider by writing a single adapter class — no changes to internal objects are required.

## Internal Model

| Class | Role |
|---|---|
| `Message::System/User/Assistant/Tool` | Provider-agnostic internal message representation |
| `Tool` | Provider-agnostic tool definition (`name`, `description`, `input_schema`) |
| `LLM::ToolCall` | Provider-agnostic tool call (`id`, `name`, `arguments`) |
| `LLM::Response` | Provider-agnostic LLM response (`content`, `tool_calls`, `finish_reason`) |

## Adapter Contract

An adapter receives internal objects and must return internal objects:

```ruby
# messages: Array<Rixie::Message::*>  — provider-agnostic
# tools:    Array<Rixie::Tool>         — provider-agnostic
# returns:  Rixie::LLM::Response       — provider-agnostic

def chat(messages, tools:)
  encoded_messages = encode_messages(messages)  # adapter-private
  encoded_tools    = encode_tools(tools)        # adapter-private
  raw = call_provider_api(encoded_messages, encoded_tools)
  decode_response(raw)                          # adapter-private
end
```

## Encoding Responsibilities

### Messages

`Message::*` objects are pure data — they have no encoding methods. Each adapter implements its own `encode_message` private method by pattern-matching on the message type:

```ruby
def encode_message(msg)
  case msg
  when Rixie::Message::System    then {role: "system",    content: msg.content}
  when Rixie::Message::User      then {role: "user",      content: msg.content}
  when Rixie::Message::Assistant then encode_assistant(msg)
  when Rixie::Message::Tool      then encode_tool_result(msg)
  end
end

def encode_messages(messages)
  messages.map { |m| encode_message(m) }
end
```

### Tools

Adapters receive `Tool` objects and encode them to their provider's format. Do not call `Tool#to_definition` — it does not exist. Use `tool.name`, `tool.description`, `tool.input_schema` directly:

```ruby
def encode_tools(tools)
  tools.map do |tool|
    {name: tool.name, description: tool.description, input_schema: tool.input_schema}
  end
end
```

### Response

Adapters must return `LLM::Response` with `LLM::ToolCall` objects:

```ruby
def decode_response(raw)
  tool_calls = raw_tool_calls.map do |tc|
    Rixie::LLM::ToolCall.new(id: tc[:id], name: tc[:name], arguments: tc[:arguments])
  end
  Rixie::LLM::Response.new(content: content, tool_calls: tool_calls, finish_reason: finish_reason)
end
```

## Naming Convention for Provider-Specific Methods on Internal Objects

When an internal object (`LLM::ToolCall`, `LLM::Response`, etc.) has a convenience method that encodes/decodes a specific provider's wire format, prefix the method name with the provider name:

```ruby
# Good — provider is explicit in the name
LLM::ToolCall.from_openai_wire(raw)
LLM::ToolCall#to_openai_wire
LLM::Response.from_openai_wire(raw)

# Bad — generic name hides provider-specific behavior
LLM::ToolCall.build_from_raw(raw)   # ❌ "raw" doesn't say which format
LLM::ToolCall#to_wire               # ❌ which wire format?
```

These methods are called only from the corresponding adapter (or from other provider-prefixed methods). Non-OpenAI adapters construct internal objects directly via `.new` and are not forced to use these methods.

## What NOT to do

```ruby
# Bad — provider wire format leaking into internal objects
messages.map(&:to_wire)          # to_wire does not exist on Message; encode in the adapter

# Bad — adapter receiving or returning OpenAI hashes instead of internal objects
def chat(messages, tools:)
  # messages is already OpenAI format — wrong, should be Message::* objects
end

# Bad — internal objects knowing about provider format
class Message::Assistant
  def to_anthropic_format  # ❌ provider knowledge does not belong here
  end
end
```

## Adding a Custom Adapter

1. Implement `chat(messages, tools:)` and `stream(messages, tools:, &block)`.
2. Encode `messages` (`Array<Message::*>`) to your provider's format inside the adapter.
3. Encode `tools` (`Array<Tool>`) to your provider's format inside the adapter.
4. Return `LLM::Response` with `LLM::ToolCall` objects.
5. Register via `config.register_provider`.

No changes to `Message`, `Tool`, `LLM::ToolCall`, `LLM::Response`, or any other internal class are needed.
