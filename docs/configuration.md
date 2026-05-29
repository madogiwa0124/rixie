# Configuration

```ruby
Rixie.configure do |config|
  config.default_provider    = "openai"
  config.default_model       = "gpt-4.1-mini"
  config.default_max_steps   = 10
  config.store               = Rixie::Store::Memory.new
  config.logger              = Logger.new($stdout)
  config.log_level           = :info
  config.log_format          = :text # :text → Subscribers::Logger (default); :json → Subscribers::JsonLogger.
                                     # Both wrap config.logger automatically — no need to repeat it.
  config.default_subscribers = nil   # nil → [default subscriber chosen by log_format]; [] → no subscribers
                                     # nil means "unset — use the built-in default"; [] means "explicitly opt out"
                                     # Pass an array to fully override (e.g. add an OpenTelemetry subscriber).
end
```

## Built-in providers

Rixie has one built-in provider. The API key is read from an environment variable.

| Provider | env var          |
| -------- | ---------------- |
| `openai` | `OPENAI_API_KEY` |

## OpenAI-compatible endpoints

GitHub Models, Ollama, and other OpenAI-compatible endpoints use the `:openai` adapter. Register them as a custom provider with a `base_url`:

```ruby
Rixie.configure do |config|
  # GitHub Models
  config.register_provider("github",
    adapter:  :openai,
    base_url: "https://models.github.ai/inference",
    api_key:  ENV["GITHUB_TOKEN"]
  )

  # Ollama (local)
  config.register_provider("ollama",
    adapter:  :openai,
    base_url: "http://localhost:11434/v1",
    api_key:  "ollama"
  )
end
```

## Custom adapters

You can plug in any LLM by writing an adapter class and registering it as a provider. An adapter must implement two methods:

```ruby
def chat(messages, tools:)   # → Rixie::LLM::Response
def stream(messages, tools:, &block)  # yields Event::Token objects, → Rixie::LLM::Response
```

For example, to add Anthropic support using the [`anthropic`](https://github.com/anthropics/anthropic-sdk-ruby) gem:

```ruby
require "anthropic"

class AnthropicAdapter
  DEFAULT_MAX_TOKENS = 4096

  def initialize(model:, api_key:, max_tokens: nil, **)
    @model      = model
    @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
    @client     = Anthropic::Client.new(access_token: api_key)
  end

  def chat(messages, tools:)
    params = {model: @model, messages: encode_messages(messages), max_tokens: @max_tokens}
    params[:tools] = encode_tools(tools) unless tools.empty?
    result = @client.messages(parameters: params)
    decode_response(result)
  end

  def stream(messages, tools:, &block)
    # Falls back to non-streaming. Implement SSE if you need token-by-token output.
    chat(messages, tools: tools)
  end

  private

  def encode_messages(messages)
    messages.map do |msg|
      case msg
      when Rixie::Message::System
        # Anthropic takes system prompt as a top-level parameter; filter these out here
        # and pass msg.content as `system:` in the API call if needed.
        nil
      when Rixie::Message::User
        {role: "user", content: msg.content}
      when Rixie::Message::Assistant
        {role: "assistant", content: msg.content || ""}
      when Rixie::Message::Tool
        {role: "user", content: [{type: "tool_result", tool_use_id: msg.tool_call_id, content: msg.content}]}
      end
    end.compact
  end

  def encode_tools(tools)
    tools.map do |tool|
      {name: tool.name, description: tool.description, input_schema: tool.input_schema}
    end
  end

  def decode_response(result)
    blocks     = result["content"] || []
    tool_calls = blocks.select { |b| b["type"] == "tool_use" }.map do |tc|
      Rixie::LLM::ToolCall.new(id: tc["id"], name: tc["name"], arguments: tc["input"])
    end
    content = blocks.find { |b| b["type"] == "text" }&.fetch("text", nil)
    Rixie::LLM::Response.new(content: content, tool_calls: tool_calls, finish_reason: result["stop_reason"])
  end
end

Rixie.configure do |config|
  config.register_provider("anthropic",
    adapter: AnthropicAdapter,
    api_key: ENV["ANTHROPIC_API_KEY"]
  )
end

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  provider:     "anthropic",
  model:        "claude-sonnet-4-6"
)
```

## Providers

`provider` and `model` are always specified separately. This is intentional — some providers (e.g. GitHub Models) serve models whose names contain another provider's name (`"openai/gpt-4.1"`), and a combined string would be ambiguous.

```ruby
# OpenAI
session = Rixie::Session.new(instructions: "...", provider: "openai", model: "gpt-4.1")

# GitHub Models (registered as custom provider)
session = Rixie::Session.new(instructions: "...", provider: "github",    model: "openai/gpt-4.1-mini")

# Ollama (registered as custom provider)
session = Rixie::Session.new(instructions: "...", provider: "ollama",    model: "llama3")
```

## Persisting sessions across requests

Use a store to save and restore conversation history:

```ruby
store = Rixie::Store::Memory.new

# First request
session = Rixie::Session.new(instructions: "You are a helpful assistant.", store: store)
session.chat("Hello, my name is Alice.")
session_id = session.session_id

# Later request — restore history and continue
context = store.load(session_id)
session = Rixie::Session.new(
  instructions:    "You are a helpful assistant.",
  store:           store,
  initial_context: context
)
puts session.chat("What's my name?")
# => "Your name is Alice."
```

`Store::Memory` keeps history in memory. Implement `Rixie::Store::Base` (`#save`, `#load`) to persist to a database or cache.
