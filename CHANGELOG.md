# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
