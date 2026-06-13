# CLI Design Guidelines

## Layer Architecture

```
CLI                          # REPL loop, option parsing, session lifecycle
├── Terminal                 # Wraps ::CLI::UI — the only place that knows cli/ui
├── Renderer                 # All terminal output; receives Terminal via DI
│   ├── Spinner              # Spinner thread; owned by Renderer
│   └── Markdown             # Pure function: markdown text → styled text via Terminal
├── SessionPicker            # -r resume picker; lists saved sessions and reads the choice
├── Tracing                  # Facade over tracing backends; one class per backend
│   ├── Tracing::Langfuse    # --langfuse option, LANGFUSE_* env vars
│   └── Tracing::Otel        # --otel options, OTLP endpoint + Basic auth
└── Commands::*              # One class per slash command; delegates output to Renderer
```

## Framework vs. Reference App

`Rixie::CLI` is a **framework** for building interactive CLIs — it ships no opinionated defaults. It registers no tools and sets no system prompt; `Rixie::CLI.start` on its own is a blank-slate assistant on the `simple` strategy. The opinionated wiring (the built-in tool set, the `Instructions::DEFAULT` prompt) lives in the **reference app**, `bin/rixie`, which registers tools via `register_tool` and sets `default_instructions` before calling `start`.

Do not reintroduce default tools or a default prompt inside `cli.rb`. New built-in capabilities that are part of the *rixie reference experience* are wired up in `bin/rixie`; the framework only exposes the registration hooks (`register_tool`, `register_agent`, `register_command`) and the `default_instructions` / `default_strategy` accessors.

## Responsibility Boundaries

- **Input is CLI's responsibility.** `CLI` owns the `Reline.readline` loop. No other class reads from stdin or prompts the user, with one exception: `SessionPicker` prompts during the `-r` startup flow, before the REPL begins. It is constructed and invoked only by `CLI`; Commands and Renderer must never read input.
- **Output is Renderer's responsibility.** All `puts` / `print` calls go through `Renderer`. Commands, CLI, and Spinner never output directly.
- **Commands own behavior only.** A command reads its argument from `arg` and delegates display to `@renderer`. If an argument is missing, it shows current state and available options so the user can retry.

## Terminal

`Terminal` is the **only** class that may reference `::CLI::UI`. It exposes:

- **Semantic style methods** (return formatted strings): `success`, `error`, `warn`, `accent`, `bold`, `secondary`
- **Layout methods**: `fmt(text)` for arbitrary cli-ui markup, `frame(title, **opts, &block)`
- **Class method**: `Terminal.enable_stdout_router` — called once at startup

No other class may call `::CLI::UI` directly or embed `{{color:...}}` format strings.

```ruby
# Good — semantic name, called via @terminal
@terminal.success("✓")
@terminal.accent("plan-execute")

# Bad — cli/ui leaking outside Terminal
::CLI::UI.fmt("{{green:✓}}")
renderer.text("{{cyan:/help}}")
```

## Renderer

`Renderer` is the **only** class that may call `puts` / `print`. Commands, CLI, and Spinner never output directly — they go through Renderer.

`Terminal` is injected via `initialize(terminal: Terminal.new)`. The spinner is constructed once in `initialize` and reused across `start_spinner` / `stop_spinner` calls.

### Output helpers (private)

| Helper | Purpose |
|---|---|
| `indented(text, level: 1)` | Returns `"  " * level + text` — base indentation primitive |
| `puts_indented(text, level: 1)` | Prints `indented(text, level:)` |
| `fmt(text)` | Passes raw cli-ui markup through `@terminal.fmt` — use sparingly, only when no semantic method fits (e.g. `{{*}}`) |
| `frame(title, **opts, &block)` | Delegates to `@terminal.frame` |

### Public semantic accessors

Renderer exposes `bold(text)` and `accent(text)` as public methods so commands can embed formatted fragments in messages without knowing about cli/ui:

```ruby
renderer.success("Model set to #{renderer.bold(new_model)}")
renderer.text("#{renderer.accent("/help")}  — Show commands")
```

## Commands

Each command inherits `Commands::Base` and receives `renderer:` in the constructor.

```ruby
class MyCommand < Base
  def name        = "mycommand"
  def description = "Does something"

  def call(arg, cli:)
    # Use renderer for all output
    renderer.success("Done: #{renderer.bold(arg)}")
  end

  def complete(input)
    # Return tab-completion candidates as ["/mycommand value1", ...]
    []
  end
end
```

Register via `CLI.register_command` (external) or add to the array in `CLI#initialize` (internal):

```ruby
# External (gem users)
Rixie::CLI.register_command(MyCommand)

# Internal (built-in commands added to CLI#initialize)
@commands = [
  Commands::Strategy.new(renderer: @renderer),
  Commands::Model.new(renderer: @renderer),
  Commands::Help.new(renderer: @renderer),
  Commands::MyCommand.new(renderer: @renderer),
]
```

Rules:
- Never call `puts` / `print` directly — use `@renderer`
- Never call `Reline.readline` — if an argument is missing, show current state and available options so the user can retry with an argument
- Never reference `::CLI::UI` — use `renderer.bold`, `renderer.accent`, etc.
- `complete(input)` must return full strings including the `/name` prefix

## Spinner

`Spinner` is owned by `Renderer` (constructed in `initialize`, not per-call). It is safe to call `start` and `stop` multiple times on the same instance.

`Renderer` exposes `start_spinner` and `stop_spinner` (no arguments). `CLI` never holds a spinner reference.

## SessionPicker

`SessionPicker` implements the `-r` / `--resume` startup flow: it lists saved sessions from the store and reads the user's numeric choice.

- Constructed with `store:` and `renderer:`; `pick(limit: 20)` returns the chosen `session_id` or `nil` (cancel / no saved sessions).
- It is the **only** class besides `CLI` allowed to call `Reline.readline`, and only before the REPL starts. It is constructed and invoked only by `CLI`.
- All output goes through `renderer` (`saved_sessions`, `error`, `text`) — display formatting, including timestamp rendering, lives in `Renderer#saved_sessions`, not in the picker.

## Tracing

`Tracing` is a facade over the optional tracing backends. One class per backend (`Tracing::Langfuse`, `Tracing::Otel`), each owning its OptionParser definitions, environment variables, and subscriber construction — backends are split by reason for change. `cli.rb` and `Renderer` carry no backend knowledge.

- `Tracing.add_options(parser, options)` delegates to each backend's `add_options`. Adding a tracing backend means one new class in `cli/tracing/` plus an entry in `Tracing::BACKENDS`.
- Each backend implements `.add_options(parser, options)`, `#subscriber` (`nil` when inactive), `#label`, and `#endpoint` (display value, `nil` when inactive).
- The facade is constructed with `(options, renderer:)`. `subscribers` returns the array to pass to `Session`; `active_endpoints` returns `[label, endpoint]` pairs for `Renderer#welcome` — the banner renders whatever it receives, without knowing backend names.
- Failed resolution (e.g. missing Langfuse credentials) disables the backend and reports via `renderer.error` — construction never raises.

## Testing

The CLI layer is not unit-tested. Testing approach:

- **Unit tests** (`test/rixie/cli/`): `Renderer`, `Spinner`, `SessionPicker`, `Tracing`, and individual `Commands::*` classes — behavior, output format, tab completion
- **Integration test** (`test/integration/cli_test.rb`): smoke test that `CLI#run` completes without error (stubs `Reline.readline` and `build_session`)
- **Manual**: `bundle exec rixie` for interactive verification

`CLI` itself (`cli.rb`) has no unit tests — its logic is thin REPL wiring that is better verified manually or through the integration smoke test.
