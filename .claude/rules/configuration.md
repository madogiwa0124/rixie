# Configuration Dependency Policy

## Core Rule

**`Rixie.config` must only be accessed in `Session`.**

`Session` is the user-facing boundary (entry point). Everything in `Configuration` is a value the user may want to customize, so config resolution is centralized in `Session`. Inner objects (`Agent`, `Task`, `Run`, etc.) must not reference `Rixie.config`.

## Resolution Layers

| Layer | Responsibility | config access |
|---|---|---|
| `Session` | User boundary. Resolves config and passes values to inner objects. | ✅ Here only |
| `LLM::Client::Resolver` | Maps provider / model to an adapter. | ⚠️ `custom_providers` only (see exception below) |
| `Agent` / `Task` / `Run` | Domain objects. | ❌ Must not access config |

### Exception: `Rixie.config.custom_providers`

`LLM::Client::Resolver` accesses `Rixie.config.custom_providers`. This is not a user preference ("which provider to use by default") but an adapter registry ("which providers are available"). It is infrastructure knowledge that belongs in the Resolver, so it is allowed as an exception.

```ruby
# OK in Resolver — registry, not a preference
all_providers = BUILTIN_PROVIDERS.merge(Rixie.config.custom_providers)

# Not allowed in Resolver — user preferences belong in Session
model    ||= Rixie.config.default_model     # ❌
provider ||= Rixie.config.default_provider  # ❌
```

## Concrete Rules

### Session signature

```ruby
# Session resolves all config values
Session.new(
  instructions: "...",
  tools:        [...],
  max_steps:    nil,   # falls back to Rixie.config.default_max_steps
  store:        nil,   # falls back to Rixie.config.store
)
```

### Agent signature

```ruby
# Agent is a domain object — it does not know about config.
# A constant provides a safe fallback when Agent is constructed directly (e.g. internally).
Agent::DEFAULT_MAX_STEPS = 10

def initialize(..., max_steps: nil, ...)
  @max_steps = max_steps || DEFAULT_MAX_STEPS
end
```

### What NOT to do

```ruby
# Bad — default parameter is evaluated at class load time, before Rixie.configure runs
def initialize(max_steps: Rixie.config.default_max_steps)

# Bad — Agent resolves config internally instead of receiving the value from Session
@max_steps = max_steps || Rixie.config.default_max_steps
```

## Why

- **Class load time**: Ruby evaluates default parameter values when the class is loaded, not when the method is called. Referencing `Rixie.config.xxx` in a signature would freeze the value before any `Rixie.configure` block runs.
- **Testability**: `Agent` and `Task` can be constructed in tests without touching global config state.
- **Natural override point**: Users decide their goal and parameters when starting a Session. Session being the override point for config is conceptually correct.

## When adding a new configurable attribute

1. Add `attr_accessor` to `Configuration`.
2. Add `attr_name: nil` to `Session#initialize`.
3. Resolve inside Session: `attr_name || Rixie.config.attr_name`, and pass the resolved value to inner objects.
4. Inner objects use the received value as-is — no config access.
