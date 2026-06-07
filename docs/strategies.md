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

## Custom Strategies

A strategy is any object that responds to `run(task:, listener:)` and returns the final output string. There is no base class to inherit — just implement the method.

```ruby
class MyStrategy
  def run(task:, listener:)
    # Create a Run, add it to task.runs, execute it, and return the output.
    run = Rixie::Run.new(
      user_input: task.user_input,
      agent:      task.agent,
      context:    task.context
    )
    task.runs << run
    run.execute(listener:)
    run.output
  end
end

session.chat("Hello", strategy: MyStrategy.new)
```

### Contract

| Requirement | Detail |
|---|---|
| `run` signature | `run(task:, listener:)` — keyword arguments, returns a String |
| `task.runs` | Push every `Run` you create onto `task.runs` before calling `run.execute` |
| `run.execute(listener:)` | Pass the received `listener` through — it carries event subscriptions for the whole Task |
| Return value | Return the string that becomes `Task#output` |

### What `task` Exposes

| Accessor | Type | Use |
|---|---|---|
| `task.user_input` | `String` | The message the user sent |
| `task.agent` | `Agent` | The configured agent (tools, instructions, LLM client) |
| `task.context` | `Array<Context::*>` | Accumulated conversation history from prior Tasks |
| `task.runs` | `Array<Run>` | Append your Run(s) here |

### Example: Retry Strategy

Run the agent up to N times and return the first successful output.

```ruby
class RetryStrategy
  def initialize(max_attempts: 3)
    @max_attempts = max_attempts
  end

  def run(task:, listener:)
    @max_attempts.times do
      run = Rixie::Run.new(
        user_input: task.user_input,
        agent:      task.agent,
        context:    task.context
      )
      task.runs << run
      run.execute(listener:)
      return run.output if run.completed?
    end
    raise Rixie::AgentError, "all #{@max_attempts} attempts failed"
  end
end
```
