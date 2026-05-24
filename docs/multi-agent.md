# Multi-Agent Orchestration

Agents can be composed by wrapping a `Session` as a `Rixie::Tool`. The orchestrator treats each sub-agent as a callable tool, delegating subtasks without sharing conversation context.

```ruby
research_agent = Rixie::Session.new(instructions: "You are a research specialist.")
write_agent    = Rixie::Session.new(instructions: "You are a technical writer.")

orchestrator = Rixie::Session.new(
  instructions: "Coordinate research and writing to produce reports.",
  tools: [
    Rixie::Tool.new(
      name:         "research",
      description:  "Research a topic and return findings.",
      input_schema: {
        type: "object",
        properties: {query: {type: "string"}},
        required: ["query"]
      },
      call: ->(args) { research_agent.chat(args["query"]) }
    ),
    Rixie::Tool.new(
      name:         "write",
      description:  "Write a report based on a topic.",
      input_schema: {
        type: "object",
        properties: {topic: {type: "string"}},
        required: ["topic"]
      },
      call: ->(args) { write_agent.chat(args["topic"]) }
    )
  ],
  parallel_tool_calls: true
)

puts orchestrator.chat("Research Ruby 3.x and write a summary report.")
```

With `parallel_tool_calls: true`, the orchestrator executes tool calls that arrive in the same LLM turn concurrently. Each sub-agent runs in its own thread, so `call` implementations must be thread-safe.

**Context isolation** — each `Session` accumulates its own history independently. The orchestrator sees only the tool results (the sub-agent's final answer), not its internal reasoning. This keeps the orchestrator's context small regardless of how much work each sub-agent does internally.

**One-shot vs. stateful sub-agents** — if the orchestrator calls the same tool multiple times, the sub-agent's `Session` accumulates history across calls. For one-shot subtasks this is fine; for cases where each invocation should start fresh, construct a new `Session` inside the `call` lambda instead of capturing a shared one.
