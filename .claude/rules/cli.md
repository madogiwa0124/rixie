# CLI Design Guidelines

## Layer Architecture

```
CLI                          # REPL loop, option parsing, session lifecycle
├── Terminal                 # Wraps ::CLI::UI — the only place that knows cli/ui
├── Renderer                 # All terminal output; receives Terminal via DI
│   ├── Spinner              # Spinner thread; owned by Renderer
│   └── Markdown             # Pure function: markdown text → styled text via Terminal
└── Commands::*              # One class per slash command; delegates output to Renderer
```

## Responsibility Boundaries

- **Input is CLI's responsibility.** `CLI` owns the `Reline.readline` loop. No other class reads from stdin or prompts the user.
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

## Testing

The CLI layer is not unit-tested. Testing approach:

- **Unit tests** (`test/rixie/cli/`): `Renderer`, `Spinner`, and individual `Commands::*` classes — behavior, output format, tab completion
- **Integration test** (`test/integration/cli_test.rb`): smoke test that `CLI#run` completes without error (stubs `Reline.readline` and `build_session`)
- **Manual**: `bundle exec rixie` for interactive verification

`CLI` itself (`cli.rb`) has no unit tests — its logic is thin REPL wiring that is better verified manually or through the integration smoke test.
