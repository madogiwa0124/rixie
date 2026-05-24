# Context Compression

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

## Keeping recent entries

Pass `keep_recent:` to preserve the most recent N context entries verbatim alongside the summary:

```ruby
session.compress!(keep_recent: 2)
# => context: [Summary, ..., History[-2], History[-1]]
```

## Customizing summarization

Pass a custom `Agent::Compressor` to override the default summarization behavior:

```ruby
compressor = Rixie::Agent::Compressor.new(
  base_agent: session.agent,
  summarization_instructions: "Summarize in bullet points, focusing on action items."
)

session.compress!(compressor: compressor)
```

You can also subclass `Agent::Compressor` to fully control the summarization logic.

## Measuring context size

`session.context_size` returns an approximate token count for the current context. Use it to decide when to compress:

```ruby
session.compress! if session.context_size > 8_000
```
