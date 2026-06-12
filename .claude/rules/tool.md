# Tool Authoring & Built-in Tool Policy

## Core Rule

**Tools are constructed via `Rixie::Tool.new(name:, description:, input_schema:, call:, return_direct:)`.**

`Tool` is a single concrete class — provider-agnostic. The same `Tool` instance is consumed by every adapter, which converts it to its provider's function-call format. Tool authors never touch provider-specific code, and built-in tools never subclass `Tool`.

## Tool Interface

| Field | Required | Description |
|---|---|---|
| `name:` | ✅ | Function name shown to the LLM. snake_case. |
| `description:` | ✅ | Natural-language description of what the tool does. Shown to the LLM. |
| `input_schema:` | ✅ | JSON Schema describing the arguments. The LLM uses this to fill in `arguments`. |
| `call:` | ✅ | Callable receiving an arguments Hash, returning a String (or any `to_s`-able value). |
| `return_direct:` | optional (default `false`) | When `true`, the agent exits the think loop immediately after this tool returns, surfacing its result as the final response. Use for tools that *are* the answer (e.g. `HumanInput`). |

```ruby
weather_tool = Rixie::Tool.new(
  name: "get_weather",
  description: "Get current weather for a city.",
  input_schema: {
    type: "object",
    properties: { city: { type: "string" } },
    required: ["city"]
  },
  call: ->(args) { "Sunny in #{args["city"]}" }
)
```

The `call` callable must be thread-safe when the session is configured with `parallel_tool_calls: true`.

## `.with` Factory Pattern (Pre-configured Tool Constants)

Built-in tools that may need user customization are defined as a pre-configured `Tool` instance with a `.with` factory method:

```ruby
class Tool
  build = ->(provider: Search::DuckDuckGo.new, max_results: 5) {
    Tool.new(name: "web_search", ..., call: ->(args) { ... })
  }
  WebSearch = build.call                            # default instance
  WebSearch.define_singleton_method(:with, &build)  # factory reuses the same lambda
end
```

This is the only acceptable pattern for built-in tools that take configuration. Do not subclass `Tool` to add configuration knobs.

**Tools that follow this pattern:** `Fetch` (`max_length:`), `WebSearch` (`provider:`, `max_results:`), `WikipediaSearch` (`language:`, `max_results:`), `FileRead` / `FileList` / `FileSearch` (`root_dir:`).

## Error Returning Convention

Tool errors must be **returned as a string starting with `"Error: ..."`**, not raised.

```ruby
# Good — LLM sees the error and can retry with corrected input
call: ->(args) {
  begin
    CalculatorParser.evaluate(args["expression"]).to_s
  rescue CalculatorParser::Error => e
    "Error: #{e.message}"
  end
}

# Bad — raised exceptions surface as ToolExecutor::Result#error?,
# losing the message visibility to the LLM
raise "Invalid expression"
```

`ToolExecutor#execute` does catch arbitrary exceptions and convert them to `Result#error?` — but that is a safety net for unexpected failures. Predictable errors (parse errors, bad input, file-not-found, regex compilation) should be returned as `"Error: ..."` strings so the LLM has a chance to recover.

Note: Ruby `->(args) { ... rescue ... }` syntax does **not** bind `rescue` to the lambda — wrap the body in explicit `begin / rescue / end`.

## Runtime Context Resolution

When a tool depends on process-level context (current directory, env vars, etc.), resolve it **at call time inside the `call:` lambda**, not at factory/load time.

```ruby
# Good — Dir.pwd evaluated per invocation
build = ->(root_dir: nil) {
  Tool.new(
    name: "file_read",
    call: ->(args) {
      base = root_dir || Dir.pwd   # ← per-call resolution
      ...
    }
  )
}

# Bad — Dir.pwd frozen when build.call runs at gem load
build = ->(root_dir: Dir.pwd) { ... }
```

If captured at load time, a later `cd` in the process silently breaks the tool.

## Path Safety (Filesystem Tools)

Filesystem tools must resolve paths via `Tool::FileSandbox`:

```ruby
target = FileSandbox.resolve(root_dir, args["path"])  # raises PathError on escape
```

`FileSandbox.resolve` rejects paths containing `..` segments and paths that escape `root_dir` after expansion. `FileSandbox.binary?(path)` detects binaries via null-byte probe (skip these in read tools).

Do not inline these checks in individual tools. A divergence between two file tools' safety logic is a security bug — keep the rule in one place.

**Documented limitation:** symlinks within `root_dir` pointing outside it will be followed (`expand_path` is used, not `realpath`). Do not point `root_dir` at directories containing untrusted symlinks.

## Built-in Tool Catalog

### Search providers (`lib/rixie/search/`)

**Rixie::Search::Base** — Interface for search providers. Subclasses implement `search(query, max_results:)` returning `[{title:, snippet:, url:}, ...]`.

**Rixie::Search::DuckDuckGo** — Searches DuckDuckGo Lite via `Http::Client`, parses HTML with Nokogiri. Extracts results from `a.result-link` elements and `td.result-snippet` cells; decodes target URLs from the `uddg` redirect parameter.

**Rixie::Search::Wikipedia** — Searches Wikipedia via the MediaWiki `action=query&list=search` API. Returns title / snippet (HTML-stripped) / url. Configurable `language:` (default `"en"`) selects the wiki language subdomain.

### Built-in tools (`lib/rixie/tool/`)

**Rixie::Tool::HumanInput** — Asks the user for input mid-loop. `return_direct: true` — the agent surfaces the question as its final response and waits for the next `session.chat` call.

**Rixie::Tool::Fetch** — Fetches a URL via `Http::Client`, sanitizes HTML (removes nav, scripts, styles, headers, footers, etc., collapses whitespace), and returns readable text. Non-HTML responses returned as-is. Output is truncated at `max_length:` characters (default 50,000) with a `... [truncated]` marker; `.with(max_length:)` for variants.

**Rixie::Tool::WebSearch** — Pre-configured `Tool` instance (default provider: `Search::DuckDuckGo`, `max_results: 5`). `.with(provider:, max_results:)` for variants.

**Rixie::Tool::WikipediaSearch** — Pre-configured `Tool` instance backed by `Search::Wikipedia`. `.with(language:, max_results:)` (e.g. `WikipediaSearch.with(language: "ja")`).

**Rixie::Tool::CurrentTime** — Returns the current time as an ISO 8601 string. Optional `timezone` argument (`"local"` or `"utc"`, default `"local"`). LLMs do not know "now" on their own.

**Rixie::Tool::Calculator** — Evaluates an arithmetic expression via a built-in recursive-descent parser. Supports `+ - * / %`, parens, unary `+/-`, `^` / `**` (right-associative). Integer division promotes to float (`5 / 2 → 2.5`). Parse errors / division-by-zero returned as `"Error: ..."` strings.

**Rixie::Tool::FileRead / FileList / FileSearch** — Filesystem tools. `.with(root_dir:)` factory (defaults to `Dir.pwd` at **call time**). All paths resolved against the configured root and rejected if they escape it (`PathError`). `FileRead` skips binary files, supports `offset` / `limit` for line slicing. `FileList` takes a glob pattern. `FileSearch` takes a regex `pattern` plus optional `glob` and `max_results` cap; output format `path:lineno:content`.

**Rixie::Tool::FileSandbox** — Internal helper module shared by the three file tools. Provides `root(root_dir)`, `resolve(root_dir, relative_path)` (raises `FileSandbox::PathError` on escape), and `binary?(path)`. Not intended for public use.

## Key Design Decisions

**`Tool::WebSearch` is a pre-configured `Tool` constant with a `.with` factory method.**
`WebSearch` is a `Tool` instance with default settings (`DuckDuckGo`, `max_results: 5`), usable as `tools: [Tool::WebSearch]`. Customization goes through `WebSearch.with(provider:, max_results:)`, which returns a new `Tool` instance. The singleton method is defined via `define_singleton_method(:with, &_build)`, reusing the same lambda that built the default. This avoids subclassing for what is just a factory while keeping the callsite symmetric with `Tool::Fetch`.

The same `.with` factory pattern is used by `Tool::Fetch` (`max_length:`), `Tool::WikipediaSearch` (`language:`, `max_results:`), and the three file tools (`root_dir:`). For the file tools specifically, `root_dir` is resolved to `Dir.pwd` at **call time** rather than factory time — if captured at gem load, it would freeze to the load-time directory and silently misbehave when the process later `cd`s.

**Path safety for file tools is centralized in `Tool::FileSandbox`.**
The three file tools share the same path-resolution rule (resolve against root, reject escapes), so the logic lives in `FileSandbox.resolve` rather than being inlined three times. This is justified abstraction, not over-engineering: a divergence between the three tools' safety checks would be a security bug. Symlink resolution is intentionally **not** performed — `expand_path` is used rather than `realpath`. Documented limitation: a symlink within `root_dir` pointing outside it will be followed when reading. Don't point `root_dir` at a directory containing untrusted symlinks.

**Calculator parser is hand-rolled, not `Dentaku` or `eval`.**
A small recursive-descent parser (~60 LOC in `Tool::CalculatorParser`) handles `+ - * / % ^ **`, parens, and unary sign. Chosen over `Dentaku` (extra runtime dependency for a feature that doesn't need its full power) and over `eval` (security risk; even with a regex allowlist on input characters, `eval` in the tool process feels wrong for an agent framework). Parser errors and division-by-zero are returned as `"Error: ..."` strings so the LLM sees them and can correct itself, rather than raised as exceptions that would surface as `ToolExecutor::Result#error?`.

## What NOT to Do

```ruby
# Bad — subclassing Tool to add configuration
class MyWebSearch < Rixie::Tool
  def initialize(max_results:)
    super(name: ..., ...)
    @max_results = max_results
  end
end

# Bad — raising on predictable errors
call: ->(args) { raise "File not found" unless File.exist?(args["path"]) }

# Bad — Dir.pwd captured at factory time
build = ->(root_dir: Dir.pwd) { Tool.new(...) }

# Bad — inlining path-safety checks
target = File.expand_path(args["path"], root_dir)
raise "escape" unless target.start_with?(root_dir)  # FileSandbox.resolve does this
```
