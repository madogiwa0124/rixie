# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `provider_params:` option on `Session` and `LLM::Client`, and `config.default_provider_params`,
  to pass arbitrary parameters directly to the provider API.
  Use this to supply model-specific parameters such as `max_completion_tokens:` for GPT-5
  or `seed:` for reproducibility.

### Fixed

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
