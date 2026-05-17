# Rixie

AI agent orchestration for Ruby.

## Overview

Rixie is a standalone Ruby gem for orchestrating AI agents — no Rails required.

An **Agent** thinks and acts via an LLM and a set of tools, looping until it reaches a final answer. A **Session** manages the full conversation, accumulating history across multiple chats. A **Strategy** controls how a goal is accomplished: the default `Simple` strategy runs a single agent loop, while `PlanExecute` first builds a step-by-step plan and then executes each step in sequence.

## Installation

Add to your Gemfile:

```ruby
gem "rixie"

# Also add the provider gem you need:
gem "openai"       # for OpenAI, GitHub Models, Ollama, and other OpenAI-compatible endpoints
```

## Configuration

```ruby
Rixie.configure do |config|
  config.default_provider  = "openai"
  config.default_model     = "gpt-4.1-mini"
  config.default_max_steps = 10
  config.store             = Rixie::Store::Memory.new
  config.logger            = Logger.new($stdout)
  config.log_level         = :info
end
```

### Built-in providers

Rixie has one built-in provider. The API key is read from an environment variable.

| Provider | env var          |
| -------- | ---------------- |
| `openai` | `OPENAI_API_KEY` |

### OpenAI-compatible endpoints

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

### Custom adapters

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
  model:        "claude-opus-4-5"
)
```

## Architecture

```
Session          # manages the full conversation; accumulates history across chats
└── Task         # accomplishes a single goal; owns a Strategy
    └── Run × N  # one LLM loop per step; calls Agent#think
        └── Agent         # thinks and acts: calls the LLM, executes tools, loops until done
```

| Class | Responsibility |
| --- | --- |
| `Session` | Entry point. Resolves config, creates `Agent` and `LLM::Client`, exposes `chat` and `live`. |
| `Task` | Runs a `Strategy` and accumulates `Run` results. Manages an `EventListener`. |
| `Run` | Calls `agent.think` once. Accumulates tool-call steps. |
| `Agent` | The think-act loop: calls the LLM, executes tools, emits events. |
| `Strategy` | Controls how many Runs a Task executes. `Simple` = 1 Run; `PlanExecute` = plan + N Runs. |

## CLI

Rixie includes an interactive CLI for chatting with an LLM directly from the terminal.

```bash
bundle exec rixie --provider openai --model gpt-4.1-mini
```

Ollama is supported as a built-in provider — no registration required:

```bash
bundle exec rixie --provider ollama --model qwen3.5:4b
```

### Options

| Option | Description |
| --- | --- |
| `--provider PROVIDER` | LLM provider (`openai`, `ollama`, or any registered custom provider) |
| `--model MODEL` | Model name |
| `--instructions TEXT` | Override the default system prompt |
| `--debug` | Print full LLM logs to stdout |
| `--version` | Print version and exit |
| `--help` | Print usage and exit |

### Slash commands

Type `/` during a session to run a command. Tab completion is available for all commands and their arguments.

| Command | Description |
| --- | --- |
| `/strategy [simple\|plan-execute]` | Switch the execution strategy. Omit the argument for interactive selection. |
| `/model MODEL` | Switch the model mid-session (resets the LLM client but keeps conversation context). |
| `/help` | List available commands. |

Type `exit` or press `Ctrl+C` to quit.

### Custom commands

Add your own slash commands by subclassing `Rixie::CLI::Commands::Base` and registering the class with `Rixie::CLI.register_command`.

```ruby
require "rixie/cli"

class ClearCommand < Rixie::CLI::Commands::Base
  def name        = "clear"
  def description = "Clear the terminal screen"

  def call(_arg, cli:)
    system("clear")
  end
end

Rixie::CLI.register_command(ClearCommand)
Rixie::CLI.start
```

The `Base` interface:

| Method | Required | Description |
| --- | --- | --- |
| `name` | Yes | Command name, used as `/name` in the REPL |
| `description` | Yes | Shown in `/help` |
| `call(arg, cli:)` | Yes | Called when the user runs `/name [arg]`. `arg` is the rest of the input after the command name, or `nil`. `cli` is the running `CLI` instance. |
| `complete(input)` | No | Returns tab-completion candidates as full strings (e.g. `["/name value1", "/name value2"]`). Default: `[]`. |

Use `renderer` (available via the private accessor) for all output — never call `puts` directly:

```ruby
def call(arg, cli:)
  renderer.success("Done: #{renderer.bold(arg)}")
  renderer.error("Something went wrong")
  renderer.text("Some plain text")
end
```

### Custom tools

Register tools with `Rixie::CLI.register_tool` to make them available in the CLI session. This is useful for testing tools interactively or building domain-specific CLIs.

```ruby
require "rixie/cli"

weather_tool = Rixie::Tool.new(
  name:         "get_weather",
  description:  "Returns the current weather for a given city.",
  input_schema: {
    type: "object",
    properties: { city: { type: "string" } },
    required: ["city"]
  },
  call: ->(args) { "Sunny, 24°C in #{args["city"]}" }
)

Rixie::CLI.register_tool(weather_tool)
Rixie::CLI.start
```

## Quick Start

```ruby
require "rixie"

Rixie.configure do |config|
  config.default_provider = "openai"
  config.default_model    = "gpt-4.1-mini"
end

session = Rixie::Session.new(instructions: "You are a helpful assistant.")
puts session.chat("What is the capital of France?")
# => "The capital of France is Paris."
```

## Agents and Tools

Define a tool using `Rixie::Tool`:

```ruby
weather_tool = Rixie::Tool.new(
  name:         "get_weather",
  description:  "Returns the current weather for a given city.",
  input_schema: {
    type: "object",
    properties: {
      city: { type: "string", description: "City name" }
    },
    required: ["city"]
  },
  call: ->(args) { "Sunny, 24°C in #{args["city"]}" }
)

session = Rixie::Session.new(
  instructions: "You are a weather assistant.",
  tools: [weather_tool]
)
puts session.chat("What's the weather in Tokyo?")
```

The `call` callable receives a hash of arguments and must return a string (or a value that responds to `to_s`).

## MCP (Model Context Protocol)

Rixie supports fetching tools from any MCP server that exposes an HTTP endpoint.

```ruby
require "rixie/mcp"

mcp = Rixie::MCP::Http::Client.new(url: "http://localhost:8000/mcp")

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  tools: mcp.tools
)
puts session.chat("What tools do you have available?")
```

`mcp.tools` returns an array of `Rixie::Tool` objects ready to pass to `Session`. Tool discovery and invocation are handled automatically — the agent calls tools on the MCP server the same way it calls any other tool.

### Authentication and custom headers

Pass additional headers for authentication:

```ruby
mcp = Rixie::MCP::Http::Client.new(
  url:     "https://my-mcp-server.example.com/mcp",
  headers: {"Authorization" => "Bearer #{ENV["MCP_TOKEN"]}"}
)
```

### Combining MCP tools with local tools

MCP tools and local `Rixie::Tool` instances can be mixed freely:

```ruby
local_tool = Rixie::Tool.new(
  name:         "current_time",
  description:  "Returns the current time.",
  input_schema: {type: "object", properties: {}},
  call:         ->(_) { Time.now.to_s }
)

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  tools: mcp.tools + [local_tool]
)
```

### Error handling

| Error class | Raised when |
| --- | --- |
| `Rixie::MCP::TimeoutError` | Connection or read timeout |
| `Rixie::MCP::ProtocolError` | MCP server returns a JSON-RPC error |
| `Rixie::MCP::RequestError` | Network or other HTTP error |

## Human-in-the-loop

Include `Rixie::Tool::HumanInput` in the tools list to let the agent ask the user for input or approval before proceeding. When the LLM calls `human_input`, the question is returned as the tool result, causing the agent to surface it as its final response. The user answers in the next `session.chat` call, and the existing context accumulation handles continuity naturally — no special state management is needed.

```ruby
session = Rixie::Session.new(
  instructions: "You are a careful assistant. Always ask for user " \
                "confirmation before performing destructive operations.",
  tools: [
    Rixie::Tool::HumanInput,
    file_deletion_tool
  ]
)

# Turn 1: LLM asks for confirmation
response = session.chat("Delete all log files.")
puts response
# => "Are you sure you want to delete all log files? This cannot be undone."

# Turn 2: User confirms, LLM proceeds
response = session.chat("Yes, go ahead.")
puts response
# => "Done. All log files have been deleted."
```

`Rixie::Tool::HumanInput` is opt-in — omitting it from the tools list means the agent will proceed without asking.

`HumanInput` is defined with `return_direct: true`, which causes the agent to stop the think-act loop immediately after the tool call and return the question as its response, rather than continuing to loop. You can use this flag on any custom tool that should short-circuit the loop in the same way.

## Strategies

### Strategy::Simple (default)

Runs a single agent loop until the LLM returns a final answer. Suitable for most tasks.

```ruby
session.chat("Summarize this document.", strategy: Rixie::Strategy::Simple.new)
# Strategy::Simple is the default — the strategy argument can be omitted.
```

### Strategy::PlanExecute

First asks the agent to produce a step-by-step plan, then executes each step as a separate run. Suitable for complex multi-step tasks where explicit planning improves results.

```ruby
session.chat("Research and write a report on Ruby 3.x features.",
             strategy: Rixie::Strategy::PlanExecute.new)
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

### Persisting sessions across requests

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

## Streaming

`Session#live` returns an `Enumerator` that yields typed event objects as the LLM generates its response.

```ruby
session = Rixie::Session.new(instructions: "You are a helpful assistant.")

session.live("Tell me about Ruby.").each do |event|
  case event
  when Rixie::Event::Token
    print event.delta   # each streamed text chunk
    $stdout.flush
  when Rixie::Event::ThoughtCompleted
    # emitted after each iteration of the think loop
    if event.thought.tool_call?
      puts "\n[tool] #{event.thought.tool_calls.map(&:name).join(", ")}"
    end
  when Rixie::Event::Finished
    puts "\n[done] #{event.content}"
  end
end
```

### Event types

| Class | Fields | Emitted when |
| --- | --- | --- |
| `Rixie::Event::Token` | `delta: String` | A text chunk arrives from the LLM |
| `Rixie::Event::ThoughtCompleted` | `thought: Thought` | A single iteration of the think loop completes (either a tool call with results, or a finish) |
| `Rixie::Event::Finished` | `content: String` | The agent produces its final answer |

`Event::Finished#content` is the full concatenated response — the same string you would get from `session.chat`.

### Streaming with tool use

`live` supports tools the same way `chat` does. `Event::ThoughtCompleted` is emitted after each iteration; check `event.thought.tool_call?` to react specifically to tool execution rounds.

```ruby
session = Rixie::Session.new(
  instructions: "You are a weather assistant.",
  tools: [weather_tool]
)

session.live("What's the weather in Tokyo?").each do |event|
  case event
  when Rixie::Event::Token            then print event.delta
  when Rixie::Event::ThoughtCompleted then puts "\n[called #{event.thought.tool_calls.first.name}]" if event.thought.tool_call?
  when Rixie::Event::Finished         then puts "\n#{event.content}"
  end
end
```

### Collecting the full response

If you only need the final text, convert to an array and find `Finished`:

```ruby
events  = session.live("Summarize Ruby in one sentence.").to_a
output  = events.find { |e| e.is_a?(Rixie::Event::Finished) }.content
```

### Context and history

`live` participates in the same context as `chat`. Tasks from both methods are accumulated and passed to subsequent calls.

```ruby
session.chat("My name is Alice.")
session.live("What's my name?").each { |e| print e.delta if e.is_a?(Rixie::Event::Token) }
# streams: "Your name is Alice."
```

## Context Compression

As a conversation grows, the context sent to the LLM grows with it. `Session#compress!` summarizes the accumulated history into a single `Context::Summary` entry, reducing token usage while preserving the essence of the conversation.

```ruby
session = Rixie::Session.new(instructions: "You are a helpful assistant.")

session.chat("My name is Alice.")
session.chat("I live in Tokyo.")
session.chat("I love Ruby.")

# Summarize everything so far
session.compress!

# The conversation continues with the summary in context
puts session.chat("What do you know about me?")
# => "Based on our conversation, your name is Alice, you live in Tokyo, and you love Ruby."
```

`compress!` uses the same LLM client as the session to generate the summary. After compression, `session.tasks` is cleared and `session.context` contains only the summary (plus any preserved recent entries).

### Keeping recent entries

Pass `keep_recent:` to preserve the most recent N context entries verbatim alongside the summary:

```ruby
session.compress!(keep_recent: 2)
# => context: [Summary, ..., History[-2], History[-1]]
```

### Customizing summarization

Pass a custom `Agent::Compressor` to override the default summarization behavior:

```ruby
compressor = Rixie::Agent::Compressor.new(
  base_agent: session.agent,
  summarization_instructions: "Summarize in bullet points, focusing on action items."
)

session.compress!(compressor: compressor)
```

You can also subclass `Agent::Compressor` to fully control the summarization logic.

### Measuring context size

`session.context_size` returns an approximate token count for the current context. Use it to decide when to compress:

```ruby
session.compress! if session.context_size > 8_000
```

### Using a custom stream client

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
