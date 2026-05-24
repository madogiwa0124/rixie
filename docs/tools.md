# Agents and Tools

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

The `call` callable receives a hash of arguments and must return a string (or a value that responds to `to_s`). When `parallel_tool_calls: true` is set on the session, multiple tool calls requested in the same LLM turn are executed concurrently — ensure your `call` implementation is thread-safe.

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

## Web Tools

> `Rixie::Tool::Fetch` and `Rixie::Tool::WebSearch` (DuckDuckGo) require the optional **`nokogiri`** gem for HTML parsing. Add `gem "nokogiri"` to your Gemfile — without it, the first invocation raises `Rixie::ConfigurationError`.

### Fetch

`Rixie::Tool::Fetch` fetches a URL and returns the readable text content. HTML pages are sanitized — scripts, styles, navigation elements, headers, and footers are removed, and excess whitespace is collapsed. Non-HTML responses (JSON, plain text, etc.) are returned as-is.

```ruby
session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  tools: [Rixie::Tool::Fetch]
)
puts session.chat("What does https://example.com say?")
```

Requests to private or internal addresses (localhost, 10.x.x.x, 192.168.x.x, etc.) are blocked to prevent SSRF attacks.

### WebSearch

`Rixie::Tool::WebSearch` searches the web using DuckDuckGo Lite and returns a numbered list of results with titles, snippets, and URLs.

`WebSearch` is a pre-configured `Rixie::Tool` — use it directly, or call `.with` to get a variant with custom settings:

```ruby
session = Rixie::Session.new(
  instructions: "You are a research assistant.",
  tools: [Rixie::Tool::WebSearch]
)
puts session.chat("What are the latest Ruby releases?")
```

Options for `.with`:

| Option | Default | Description |
| --- | --- | --- |
| `max_results:` | `5` | Maximum number of search results to return |
| `provider:` | `Rixie::Search::DuckDuckGo.new` | Search provider. Must respond to `#search(query, max_results:)` returning `[{title:, snippet:, url:}, ...]` |

```ruby
# Fewer results
tools: [Rixie::Tool::WebSearch.with(max_results: 3)]

# Custom provider
tools: [Rixie::Tool::WebSearch.with(provider: MySearchProvider.new)]
```

### WikipediaSearch

`Rixie::Tool::WikipediaSearch` searches Wikipedia via the MediaWiki API and returns titles, snippets, and URLs.

```ruby
session = Rixie::Session.new(
  instructions: "You are an encyclopedic assistant.",
  tools: [Rixie::Tool::WikipediaSearch]
)
puts session.chat("Who was Ada Lovelace?")
```

Options for `.with`:

| Option | Default | Description |
| --- | --- | --- |
| `language:` | `"en"` | Wikipedia language subdomain (e.g. `"ja"`, `"de"`, `"fr"`) |
| `max_results:` | `5` | Maximum number of search results to return |

```ruby
# Japanese Wikipedia
tools: [Rixie::Tool::WikipediaSearch.with(language: "ja")]
```

### Using Fetch and WebSearch together

Combining both tools lets the agent search for pages and then read their full content:

```ruby
session = Rixie::Session.new(
  instructions: "You are a research assistant. Search the web and fetch pages as needed.",
  tools: [
    Rixie::Tool::WebSearch,
    Rixie::Tool::Fetch
  ]
)
puts session.chat("Summarize the Ruby 3.4 release notes.")
```

## File Tools

Three tools for reading and searching files on the local filesystem. All three are sandboxed to a configurable `root_dir` — paths that escape the root (via `..` segments or absolute paths) are rejected with an error returned to the LLM.

`root_dir` defaults to `Dir.pwd` evaluated **at call time**, so the default tracks the current process directory. Pass `.with(root_dir: "/path/to/project")` to pin the sandbox to a specific directory.

> **Security note:** symlinks within `root_dir` that point outside it are followed (the implementation uses `expand_path`, not `realpath`). Do not point `root_dir` at a directory containing untrusted symlinks.

### FileRead

`Rixie::Tool::FileRead` reads a file's contents. Binary files (detected by null-byte probe) are rejected. Supports `offset` (1-indexed line) and `limit` (default 2000 lines) for slicing large files.

```ruby
session = Rixie::Session.new(
  instructions: "You are a code reviewer.",
  tools: [Rixie::Tool::FileRead.with(root_dir: "/path/to/repo")]
)
puts session.chat("Summarize lib/foo.rb")
```

### FileList

`Rixie::Tool::FileList` lists files matching a glob pattern relative to `root_dir`.

```ruby
tools: [Rixie::Tool::FileList.with(root_dir: "/path/to/repo")]
# Agent can call: file_list(pattern: "lib/**/*.rb")
```

### FileSearch

`Rixie::Tool::FileSearch` grep-searches files by regex. Output format is `path:lineno:content`. Optional `glob:` filter and `max_results:` cap (default 50) keep results manageable.

```ruby
tools: [Rixie::Tool::FileSearch.with(root_dir: "/path/to/repo")]
# Agent can call: file_search(pattern: "TODO", glob: "**/*.rb", max_results: 20)
```

## Utility Tools

### CurrentTime

`Rixie::Tool::CurrentTime` returns the current time as an ISO 8601 string. LLMs do not know "now" on their own, so this fills the gap.

```ruby
tools: [Rixie::Tool::CurrentTime]
# Agent can call: current_time(timezone: "utc")  # or "local" (default)
```

### Calculator

`Rixie::Tool::Calculator` evaluates an arithmetic expression. Supports `+ - * / %`, parentheses, unary `+/-`, and `^` / `**` (right-associative). Integer division promotes to float (`5 / 2 → 2.5`). Parse errors and division-by-zero are returned as `"Error: ..."` strings rather than raised, so the LLM can see and correct them.

Implemented with a hand-rolled recursive-descent parser — `eval` is not used.

```ruby
tools: [Rixie::Tool::Calculator]
# Agent can call: calculator(expression: "(1 + 2) * 3 ^ 2")
```
