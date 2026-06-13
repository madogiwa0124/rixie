# Structured Output

By default `Session#chat` returns a `String`. Pass a JSON Schema via `schema:` to get back a
parsed Ruby `Hash` that conforms to that schema — useful for extraction, classification,
form-filling, and any downstream programmatic consumption.

```ruby
schema = {
  "type" => "object",
  "properties" => {
    "title"   => {"type" => "string"},
    "summary" => {"type" => "string"},
    "tags"    => {"type" => "array", "items" => {"type" => "string"}}
  },
  "required" => ["title", "summary"]
}

result = session.chat("Summarize this article: ...", schema: schema)
# => {"title" => "...", "summary" => "...", "tags" => [...]}
```

When `schema:` is omitted, behavior is unchanged — `chat` returns a `String`.

The schema is a **raw JSON Schema Hash** (the same shape `Rixie::Tool` uses for `input_schema`).
There is no custom DSL.

## How it works

The schema describes the **shape of the final answer**, not an action, so it is not modeled as a
tool. The agent's think loop runs **unconstrained**: tool-calling iterations never carry the
schema. Only the closing answer is schema-constrained. This means multi-step flows work naturally:

```ruby
# The agent may call web_search (unconstrained), then return the result as structured JSON.
session = Rixie::Session.new(instructions: "Research, then answer.", tools: [Rixie::Tool::WebSearch])
session.chat("Who founded Ruby and in what year?", schema: {
  "type" => "object",
  "properties" => {"founder" => {"type" => "string"}, "year" => {"type" => "integer"}},
  "required" => ["founder", "year"]
})
```

When the agent produces its final answer, `Rixie::Agent::StructuredOutput` parses it as JSON and
validates it against the schema. If it does not conform, the **finish generation is retried** (with
a corrective message and the schema applied), without re-running any tool calls — so a web search
never fires twice. After a bounded number of retries, `Rixie::SchemaValidationError` is raised.

## Provider support

- **OpenAI** uses native structured output (`response_format: { type: "json_schema" }`).
- **Other adapters** fall back to prompt-based JSON, relying on the corrective retry loop.

## Errors

```ruby
begin
  session.chat("...", schema: schema)
rescue Rixie::SchemaValidationError => e
  # The model could not produce schema-conforming output within the retry limit.
end
```

## Streaming is not supported

Structured output requires the complete response to parse and validate, which is incompatible with
token-by-token streaming. Passing `schema:` to `Session#live` raises `ArgumentError`:

```ruby
session.live("...", schema: schema)  # => ArgumentError
```
