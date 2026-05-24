# Strategies

## Strategy::Simple (default)

Runs a single agent loop until the LLM returns a final answer. Suitable for most tasks.

```ruby
session.chat("Summarize this document.", strategy: Rixie::Strategy::Simple.new)
# Strategy::Simple is the default — the strategy argument can be omitted.
```

## Strategy::PlanExecute

First asks the agent to produce a step-by-step plan, then executes each step as a separate run. Suitable for complex multi-step tasks where explicit planning improves results.

```ruby
session.chat("Research and write a report on Ruby 3.x features.",
             strategy: Rixie::Strategy::PlanExecute.new)
```

## Strategy::ReAct

Wraps the agent with `Agent::ReAct`, which instructs the LLM to emit a `Thought:` reasoning trace in its text content before each tool call, and to make exactly one tool call per step. Suitable for tasks where surfacing the agent's reasoning is valuable — debugging, step-by-step problem solving, or models that benefit from explicit chain-of-thought.

```ruby
session.chat("Find the population of Tokyo, then multiply it by 2.",
             strategy: Rixie::Strategy::ReAct.new)
```

The reasoning trace appears in `Thought#content` on each `:tool_call` iteration, so you can observe it through the standard event stream (`Event::ThoughtCompleted` / `live`) without any ReAct-specific plumbing. Internally, `parallel_tool_calls` is forced to `false` so the Thought → Action → Observation cycle stays linear.
