# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Rixie::CLI.register_agent(name, instructions:, tools:, model:)` — register named agent presets
  that bundle a system prompt and tool set. Users switch between them at runtime with the new `/agent NAME`
  slash command. Switching rebuilds the `Session` while carrying over the existing conversation context.
  `model:` is optional and overrides the current model when the preset is activated.
- `/agent [NAME]` slash command with tab completion for preset names.
- `Rixie::CLI.default_instructions` and `Rixie::CLI.default_strategy` class accessors,
  letting a custom CLI set framework-wide defaults for the system prompt and the
  startup strategy.
- `provider_params:` option on `Session` and `LLM::Client`, and `config.default_provider_params`,
  to pass arbitrary parameters directly to the provider API.
  Use this to supply model-specific parameters such as `max_completion_tokens:` for GPT-5
  or `seed:` for reproducibility.
- `session_id:` option on `Session` so a resumed session keeps saving under the same
  store key instead of generating a fresh id (and fragmenting one conversation
  across store entries).
- `Session.resume(session_id:, ...)` helper to restore a persisted
  session in one step (loads context from store and reuses the same session_id).
- `Rixie::Store::File` — JSON file persistence store (default path: `~/.rixie/sessions.json`)
  with atomic writes, so sessions survive across processes.
- `list_sessions(limit:)` on the `Store::Base` interface (implemented by `File`, `Memory`,
  and `Null`), returning `Rixie::Store::Row` rows (`session_id`, `created_at`, `updated_at`,
  `entry_count`, `preview`) sorted most recently updated first.
- `-r` / `--resume` CLI option: lists saved sessions in an interactive picker and resumes
  the selected one via `Session.resume`. The CLI persists sessions with `Store::File` by
  default when `config.store` is not set.
- `Tool::Fetch.with(max_length:)` factory. Fetch output is now truncated at 50,000
  characters by default (with a `... [truncated]` marker) so a single huge page
  cannot blow the prompt budget.
- `max_body_size:` option on `Http::Client` (default 10 MiB). The decoded response
  body is capped, and gzip/deflate decompression aborts as soon as the cap is
  exceeded, guarding against oversized responses and compression bombs.

### Changed

- `Rixie::CLI` is now a blank-slate framework: `Rixie::CLI.start` no longer registers
  the built-in tools or a default system prompt on its own. The built-in tool set and
  the default prompt (`Rixie::CLI::Instructions::DEFAULT`) are now wired up by the reference
  app (`bin/rixie`) instead. Custom CLIs register only the tools they need and set their own
  prompt via `Rixie::CLI.default_instructions`. The `bundle exec rixie` experience is unchanged.

### Fixed

- `Agent::Plan`, `Agent::ReAct`, and `Agent::Compressor` silently dropped the base
  agent's `max_steps`, `token_counter`, and (for `Plan`) `parallel_tool_calls`,
  resetting them to defaults. A user-configured step budget now applies to every
  phase of a strategy. `ReAct` still forces `parallel_tool_calls: false` by design.
- `LLM::Client::Resolver` raised `NameError` when resolving a provider registered with a
  custom adapter class while the OpenAI adapter had never been loaded.
- SSRF protection in `Http::Client` now blocks link-local (`169.254.0.0/16`, including
  cloud metadata endpoints), CGNAT (`100.64.0.0/10`), multicast, and reserved ranges,
  for both IPv4 and IPv6. The hostname/IP classifier now uses `IPAddr` instead of a regex.
- Malformed JSON in tool-call arguments returned by the LLM now raises `Rixie::LLM::Error`
  instead of an unwrapped `JSON::ParserError`.
- `PromptBuilder` no longer emits a system message with `null` content when `instructions`
  is nil or empty (real providers reject such messages).
- `Session#live` raises a descriptive `Rixie::ConfigurationError` when no stream client is
  available (previously crashed with `NoMethodError` on the first LLM call).

### Removed

- `max_tokens:` parameter on `Session` / `LLM::Client` and `config.default_max_tokens` —
  use `provider_params: { max_tokens: N }` (or `max_completion_tokens:` for models that require it) instead.

## [0.1.0] - 2026-05-29

Initial release. Requires Ruby 3.4 or newer.

### Added

- Conceptual hierarchy: `Session → Task → Run → Agent` with the think+act loop.
- Strategies: `Simple`, `PlanExecute`, `ReAct`.
- Built-in tools: `HumanInput`, `Fetch`, `WebSearch`, `WikipediaSearch`,
  `CurrentTime`, `Calculator`, `FileRead`, `FileList`, `FileSearch`.
- LLM provider support: `openai` and any OpenAI-compatible endpoint
  (GitHub Models, Ollama).
- MCP (Model Context Protocol) HTTP client for importing remote tools.
- Interactive CLI (`bin/rixie`) with slash commands, tab completion,
  and markdown rendering.
- Streaming via `Session#live`.
- Context compression via `Session#compress!`.
- Multi-agent orchestration: wrap a `Session` as a tool.
- Event bus with pluggable subscribers. Built-in:
  `Subscribers::Logger` (text) and `Subscribers::JsonLogger` (one JSON
  object per event). Both dispatch through `Subscribers::EventSeverity`,
  which maps each event to a `::Logger` severity (`:debug` for
  per-iteration events, `:warn` for failures, `:info` otherwise).
- Shared `Rixie::Http::Client` with SSRF protection, gzip/deflate
  decoding, and `allow_private:` opt-out for trusted endpoints.
- Optional runtime dependencies: `openai`, `nokogiri`, `cli-ui`.
  Each raises `Rixie::ConfigurationError` with an actionable message
  when used without the gem installed.

[Unreleased]: https://github.com/madogiwa0124/rixie/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/madogiwa0124/rixie/releases/tag/v0.1.0
