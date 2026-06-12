# Store and Session Persistence

Use a store to persist conversation context across requests.

## Default store via configuration

Set a default store once in `Rixie.configure`:

```ruby
Rixie.configure do |config|
  config.store = Rixie::Store::Memory.new
end
```

Once configured, `Session.new` uses this store automatically.

## Persisting and resuming a session

```ruby
Rixie.configure do |config|
  config.store = Rixie::Store::Memory.new
end

# First request
session = Rixie::Session.new(instructions: "You are a helpful assistant.")
session.chat("Hello, my name is Alice.")
session_id = session.session_id

# Later request — restore history and continue in one step
resumed = Rixie::Session.resume(
  session_id: session_id,
  instructions: "You are a helpful assistant."
)
puts resumed.chat("What's my name?")
# => "Your name is Alice."
```

`Session.resume` loads `initial_context` from the resolved store and keeps saving under the same `session_id`.
If you want the same assistant behavior, pass the same `instructions` you used when the session was first created.
If omitted, resumed behavior may differ depending on your defaults.

When persisting through multiple requests, keep both values from the first request:

- `session.session_id` (which store key to load)

If you do not use `config.store`, pass `store:` explicitly to `Session.resume`.

## Per-session override

If you need a different backend for one session, pass `store:` explicitly:

```ruby
default_store = Rixie::Store::Memory.new
special_store = MyRedisStore.new

Rixie.configure do |config|
  config.store = default_store
end

# Uses default_store
normal = Rixie::Session.new(instructions: "Normal flow")

# Uses special_store only for this session
isolated = Rixie::Session.new(
  instructions: "Special flow",
  store: special_store
)
```

## Implementing a custom store

Implement `Rixie::Store::Base` and provide at least:

- `save(session_id, context)`
- `load(session_id)`

`context` is an array of `Context::History` / `Context::Summary` objects.
Persist them as hashes with `entry.to_store`, and restore with `Context::History.from_store` / `Context::Summary.from_store`.

Example:

```ruby
require "json"

class RedisStore < Rixie::Store::Base
  def initialize(redis:, namespace: "rixie:sessions")
    @redis = redis
    @namespace = namespace
  end

  def save(session_id, context)
    payload = context.map(&:to_store)
    @redis.set(key_for(session_id), JSON.dump(payload))
  end

  def load(session_id)
    raw = @redis.get(key_for(session_id))
    return [] if raw.nil?

    entries = JSON.parse(raw)
    entries.map { |entry| deserialize_entry(entry) }
  end

  private

  def key_for(session_id)
    "#{@namespace}:#{session_id}"
  end

  def deserialize_entry(entry)
    case entry["type"]
    when "history" then Rixie::Context::History.from_store(entry)
    when "summary" then Rixie::Context::Summary.from_store(entry)
    else raise Rixie::Error, "Unknown context entry type: #{entry["type"]}"
    end
  end
end
```

Use it as default:

```ruby
require "redis"

redis = Redis.new(url: ENV.fetch("REDIS_URL"))

Rixie.configure do |config|
  config.store = RedisStore.new(redis: redis)
end
```

Or per session:

```ruby
session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  store: RedisStore.new(redis: redis)
)
```

`Store::Memory` is in-memory only and is useful for tests and single-process apps. For production, use a persistent backend (database, cache, object storage, etc.).
