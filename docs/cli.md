# CLI

Rixie includes an interactive CLI for chatting with an LLM directly from the terminal.

> The CLI requires the optional **`cli-ui`** gem. Add `gem "cli-ui"` to your Gemfile — without it, loading the CLI raises `Rixie::ConfigurationError`.

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
| `--langfuse [BASE_URL]` | Enable Langfuse tracing (default base URL: `http://localhost:3000`). Requires `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` env vars. |
| `--otel [ENDPOINT]` | Enable OpenTelemetry tracing. Default endpoint: `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` env var, falling back to `http://localhost:5080/api/default/v1/traces` (local OpenObserve). |
| `--otel-user USER` | Basic auth username for the OTel backend (falls back to `OPENOBSERVE_USER`) |
| `--otel-password PASSWORD` | Basic auth password for the OTel backend (falls back to `OPENOBSERVE_PASSWORD`) |
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

## Langfuse tracing

The CLI can send traces to [Langfuse](https://langfuse.com). Each conversation turn becomes a Trace with Run, Generation, and tool-call Spans nested inside it.

Tracing is enabled only with the explicit `--langfuse` flag. Credentials come from the `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` env vars; the base URL defaults to `LANGFUSE_BASE_URL` (or `http://localhost:3000`) and can be overridden as the flag argument:

```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...

bundle exec rixie --provider openai --model gpt-4.1-mini --langfuse
# or point at a hosted instance:
bundle exec rixie --provider openai --model gpt-4.1-mini --langfuse https://cloud.langfuse.com
```

When active, the welcome frame shows `Langfuse: <base_url>`. Traces appear in the Langfuse UI after each response.

To run a local Langfuse instance, use the `docker-compose.yml` included at the project root:

```bash
docker compose up -d
open http://localhost:3000   # create an account and generate API keys
```

See [Subscribers — Langfuse](subscribers.md#langfuse) for programmatic usage.

## OpenTelemetry tracing

The CLI can also export traces to any OpenTelemetry-compatible backend via OTLP HTTP. Each conversation turn becomes a `task` span with `run`, `gen_ai.chat`, and `tool.*` spans nested inside it.

Tracing is enabled only with the explicit `--otel` flag. The endpoint resolves in this order: flag argument → `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` env var → `http://localhost:5080/api/default/v1/traces` (local OpenObserve). Note the endpoint must be the **full** traces URL — it is passed to the OTLP exporter as-is, so `/v1/traces` is not appended automatically.

```bash
# Local OpenObserve (started via docker compose up -d)
bundle exec rixie --provider openai --model gpt-4.1-mini \
  --otel --otel-user root@example.com --otel-password 'Complexpass#123'

# Any other OTLP HTTP backend
bundle exec rixie --provider openai --model gpt-4.1-mini \
  --otel http://collector:4318/v1/traces
```

`--otel-user` / `--otel-password` (or the `OPENOBSERVE_USER` / `OPENOBSERVE_PASSWORD` env vars) add a Basic auth header for backends that require it, such as OpenObserve. They are built into a header Hash internally, so special characters in the password need no URL encoding — unlike `OTEL_EXPORTER_OTLP_HEADERS`.

When active, the welcome frame shows `OpenTelemetry: <endpoint>`. The `docker-compose.yml` at the project root includes an OpenObserve service (UI at `http://localhost:5080`, login `root@example.com` / `Complexpass#123`).

The OpenTelemetry gems are optional dependencies — add `opentelemetry-sdk` and `opentelemetry-exporter-otlp` to your Gemfile to use this flag.

See [Subscribers — OpenTelemetry](subscribers.md#opentelemetry) for programmatic usage.

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
