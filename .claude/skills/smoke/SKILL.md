---
name: smoke
description: >
  Run the smoke test against local Ollama to verify core features work with a real LLM.
  Invoke proactively (without being asked) after completing any change that touches:
  LLM adapter streaming or tool call accumulation, Agent think/llm_call loop,
  EventListener, Session#chat or Session#live, Strategy execution, or LLM::Client routing.
  These are areas where dummy-based unit tests pass but real LLM behavior can diverge.
allowed-tools: Bash
---

## Steps

1. Check that Ollama is running:

   !`curl -s --max-time 3 http://localhost:11434/api/tags > /dev/null 2>&1 && echo "ok" || echo "not running"`

   If the result is "not running", tell the user and stop.

2. Pick the fastest available model — prefer `qwen3.5:2b`, fall back to `qwen3.5:4b`:

   !`curl -s http://localhost:11434/api/tags | ruby -rjson -e 'names = JSON.parse($stdin.read)["models"].map { |m| m["name"] }; puts (names.find { |n| n.include?("qwen3.5:2b") } || names.find { |n| n.include?("qwen3.5") } || names.first || "none")'`

   If no model is found, tell the user and stop.

3. Run the smoke test with a 5-minute timeout using the model from step 2:

   ```bash
   RIXIE_TEST_BASE_URL=http://localhost:11434/v1 \
   RIXIE_TEST_MODEL=<model> \
   RIXIE_TEST_REQUEST_TIMEOUT=300 \
   bundle exec rake test:smoke 2>&1
   ```

4. Report the result: pass/fail count, duration, and which tests failed if any.
