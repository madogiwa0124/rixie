# CLI

Rixie includes an interactive CLI for chatting with an LLM directly from the terminal.

```bash
bundle exec rixie --provider openai --model gpt-4.1-mini
```

Ollama is supported as a built-in provider — no registration required:

```bash
bundle exec rixie --provider ollama --model qwen3.5:4b
```

## Overview

The CLI is built on [Shopify's cli-ui](https://github.com/Shopify/cli-ui) for terminal rendering (colors, frames, spinners, markdown) and uses [`Reline`](https://github.com/ruby/reline) for line editing and tab completion. On top of that, it wraps a `Rixie::Session` in a REPL loop — each line you type becomes a `session.chat` call, so context accumulates across turns the same way it would in a library use case.

What you get out of the box:

- **Slash commands** — switch strategy/model, inspect or compress context, list help (see [Slash commands](#slash-commands))
- **Tab completion** — for both command names and command arguments
- **Markdown rendering** — agent output is rendered with cli-ui styling (headings, code blocks, lists)
- **Spinner** — while the agent is thinking or executing tools
- **Extensibility** — register your own slash commands and tools (see [Custom commands](#custom-commands), [Custom tools](#custom-tools))

## Architecture

```
CLI                     # REPL loop, option parsing, session lifecycle
├── Terminal            # Wraps cli-ui — the only layer that knows about cli-ui
├── Renderer            # All terminal output goes through here
│   ├── Spinner         # Background spinner thread, owned by Renderer
│   └── Markdown        # Renders markdown text via Terminal
└── Commands::*         # One class per slash command, delegates output to Renderer
```

| Layer | Responsibility |
| --- | --- |
| `CLI` | Owns the `Reline.readline` loop, parses CLI options, holds the live `Session`. The only layer that reads stdin. |
| `Terminal` | The only class that references `::CLI::UI`. Exposes semantic helpers (`success`, `error`, `accent`, `bold`, `frame`, …). |
| `Renderer` | The only class that calls `puts`/`print`. Commands and CLI delegate all output to it. Constructed with a `Terminal` via DI. |
| `Spinner` | Background spinner thread, owned by `Renderer` (one instance reused across `start_spinner` / `stop_spinner` calls). |
| `Markdown` | Pure function: markdown text → styled text via `Terminal`. Used to render agent output. |
| `Commands::Base` subclasses | One class per slash command (`/strategy`, `/model`, `/context`, `/compress`, `/help`). Each owns its own argument parsing, tab completion, and behavior. |

**Boundaries that matter when extending the CLI:**

- Custom commands must call `renderer.*` for output — never `puts`, never `::CLI::UI` directly. This keeps formatting consistent and testable.
- Custom commands must not call `Reline.readline`. If an argument is missing, show the current state and available choices so the user can retry — don't prompt mid-command.
- `Terminal` is the only escape hatch to `cli-ui`. If you need a color or layout primitive that `Renderer` doesn't expose, extend `Terminal` rather than reaching into `::CLI::UI` from a command.

## Options

| Option | Description |
| --- | --- |
| `--provider PROVIDER` | LLM provider (`openai`, `ollama`, or any registered custom provider) |
| `--model MODEL` | Model name |
| `--instructions TEXT` | Override the default system prompt |
| `--debug` | Print full LLM logs to stdout |
| `--version` | Print version and exit |
| `--help` | Print usage and exit |

## Slash commands

Type `/` during a session to run a command. Tab completion is available for all commands and their arguments.

| Command | Description |
| --- | --- |
| `/strategy [simple\|plan-execute\|re-act]` | Switch the execution strategy. Omit the argument to see the current value and available choices. |
| `/model MODEL` | Switch the model mid-session (resets the LLM client but keeps conversation context). |
| `/context` | Show approximate token count and number of entries in the current context. |
| `/compress [N]` | Compress conversation context into a summary, optionally keeping the most recent `N` entries verbatim (default `0`). |
| `/help` | List available commands. |

Type `exit` or press `Ctrl+C` to quit.

## Custom commands

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

## Custom tools

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
