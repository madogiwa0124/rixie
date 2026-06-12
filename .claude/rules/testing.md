# Testing Strategy

## Two-Layer Structure

| Layer | Directory | Scope |
|---|---|---|
| Unit tests | `test/rixie/` | Single class behavior in isolation |
| Integration tests | `test/integration/` | Component collaboration through `Session` |

Unit tests target a single class. Integration tests construct a real `Session` and assert on behavior observable from the outside (output, task/run state).

## Injecting Fake LLM Responses

All tests use `Rixie::LLM::Adapter::Dummy` — no real HTTP requests are made unless running in live mode.

```ruby
# Unit test: construct adapter and client directly
adapter = Rixie::LLM::Adapter::Dummy.new(responses)
client  = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
agent   = Rixie::Agent.new(instructions: "...", llm_client: client)

# Integration test: use build_client helper (from Integration::Helper)
client  = build_client(responses: [...])
session = Rixie::Session.new(instructions: "...", llm_client: client)
```

Responses are consumed in order (FIFO). Enqueue them to match the expected LLM call sequence.

## Response Fixture Helpers

Integration tests inherit these from `Integration::Helper`. Unit tests define their own locally with the same shape.

```ruby
finish_response(content: "Done.")
# → {"choices" => [{"message" => {"content" => "Done.", "tool_calls" => nil}}]}

tool_call_response(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"})
# → {"choices" => [{"message" => {"content" => nil, "tool_calls" => [...]}}]}

plan_done_response(steps: [{"title" => "Step 1", "description" => "..."}])
# → tool_call_response wrapping a plan_done tool call
```

For `Strategy::PlanExecute`, enqueue: `[plan_done_response, *per_step_finish_responses]`.

## Resetting Global State

`Rixie.reset!` is called in every `setup`. This is handled automatically:
- Unit tests: via `Minitest::Test#setup` in `test/test_helper.rb`
- Integration tests: via `Integration::TestCase#setup` in `test/integration/test_helper.rb`

Never rely on global config state left over from a previous test. If a test needs a custom logger or config value, set it explicitly after `super` / after `Rixie.reset!`.

## Integration Test Base Class

```ruby
class MyTest < Integration::TestCase
  # Inherits: build_client, finish_response, tool_call_response, plan_done_response, live?
end
```

## Live Mode

Integration tests can run against real providers by setting env vars:

```bash
RIXIE_TEST_PROVIDER=openai RIXIE_TEST_MODEL=gpt-4.1-mini bundle exec rake test:integration
RIXIE_TEST_BASE_URL=http://localhost:11434/v1 RIXIE_TEST_MODEL=qwen3.5:4b bundle exec rake test:integration
```

Use `unless live?` to guard assertions that depend on exact dummy responses:

```ruby
assert task.completed?          # always assert — structure is invariant
assert_instance_of String, output

unless live?
  assert_equal "Exact LLM output", output   # dummy-only assertion
  assert_equal 2, task.runs.first.steps.size
end
```

## Fake Gems

`test/support/fake_gems/` contains a minimal stub of `openai`. It allows `require "openai"` in adapter code without installing the real gem. The unit test load path includes this directory (`test_helper.rb`).

Do not add logic to fake gems. They exist only to satisfy `require` at load time.

## What Belongs in Each Layer

**Unit test** — test the contract of a single class:
- Return values and state changes
- Error conditions and edge cases
- Event emissions (subscribe to `EventListener` directly)
- Private method visibility (`assert_raises NoMethodError`)

**Integration test** — test that components work together through `Session`:
- `session.chat(...)` returns the expected output
- `session.tasks.first.completed?` is true
- Run/step counts and tool call sequences

Do **not** reach into internal objects (e.g. `run.steps`) in unit tests of other classes — that is integration territory.

## Required: Tests for Public Interface Changes

The following always require a test — no exceptions:

- **New public method** — at minimum one test covering the happy path and one for each error/edge case
- **Behavior change to an existing public method** — update or add tests that cover the new behavior; remove tests that assert the old behavior
- **New event emission** — add a test that subscribes to the event and asserts it fires with the expected payload

These are non-negotiable. Skipping them is a bug in the development process, not a time-saving measure.

## What NOT to Do

```ruby
# Bad — real HTTP in a non-live test
client = Rixie::LLM::Client.new(provider: "openai", model: "gpt-4o")

# Bad — relying on config state from a previous test (reset! is not called)
def test_foo
  Rixie.config.default_model = "gpt-4o"
  # ... (no reset, pollutes subsequent tests)
end

# Bad — asserting exact LLM output without a live? guard
assert_equal "Exact string", output  # will break in live mode
```
