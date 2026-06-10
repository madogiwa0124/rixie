# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Rixie
  module Subscribers
    # Sends Rixie events to a Langfuse instance via the ingestion API.
    #
    # Trace hierarchy:
    #   Task  → Langfuse Trace
    #   Run   → Langfuse Span (child of Trace)
    #   LLM call  → Langfuse Generation (child of Run span)
    #   Tool call → Langfuse Span (child of Run span)
    #
    # All events are buffered per Task and flushed in a single batch on TaskEnd.
    class Langfuse < Rixie::Subscriber
      def initialize(base_url:, public_key:, secret_key:, flusher: nil)
        @base_url = base_url.chomp("/")
        @public_key = public_key
        @secret_key = secret_key
        @flusher = flusher
      end

      def subscribe(listener)
        trace_id = SecureRandom.uuid
        batch = []
        run_spans = {}   # run_id  => span_id
        llm_gens = {}    # step_count => { gen_id:, run_id: }
        tool_spans = {}  # tool_call.id => span_id

        listener.on(Event::TaskStart) do |env|
          e = env.event
          batch << ingestion_event("trace-create", {
            id: trace_id,
            timestamp: iso8601(env.occurred_at),
            name: truncate(e.user_input.to_s, 100),
            sessionId: env.session_id,
            input: e.user_input,
            metadata: {strategy: e.strategy.class.name},
            tags: ["rixie"]
          })
        end

        listener.on(Event::RunStart) do |env|
          span_id = SecureRandom.uuid
          run_spans[env.run_id] = span_id
          batch << ingestion_event("span-create", {
            id: span_id,
            traceId: trace_id,
            name: "run",
            startTime: iso8601(env.occurred_at),
            input: env.event.user_input
          })
        end

        listener.on(Event::LlmCallStart) do |env|
          e = env.event
          gen_id = SecureRandom.uuid
          llm_gens[e.step_count] = {gen_id: gen_id, run_id: env.run_id}
          batch << ingestion_event("generation-create", {
            id: gen_id,
            traceId: trace_id,
            parentObservationId: run_spans[env.run_id],
            name: "llm_call",
            startTime: iso8601(env.occurred_at),
            model: e.model,
            metadata: {provider: e.provider, step: e.step_count}
          })
        end

        listener.on(Event::LlmCallEnd) do |env|
          e = env.event
          state = llm_gens[e.step_count]
          next unless state
          batch << ingestion_event("generation-update", {
            id: state[:gen_id],
            endTime: iso8601(env.occurred_at),
            usage: {input: e.usage[:input_tokens], output: e.usage[:output_tokens], unit: "TOKENS"},
            metadata: {finish_reason: e.finish_reason}
          })
        end

        listener.on(Event::ToolCallStart) do |env|
          tc = env.event.tool_call
          span_id = SecureRandom.uuid
          tool_spans[tc.id] = span_id
          batch << ingestion_event("span-create", {
            id: span_id,
            traceId: trace_id,
            parentObservationId: run_spans[env.run_id],
            name: tc.name,
            startTime: iso8601(env.occurred_at),
            input: tc.arguments,
            metadata: {tool_call_id: tc.id}
          })
        end

        listener.on(Event::ToolCallEnd) do |env|
          e = env.event
          span_id = tool_spans[e.tool_call.id]
          next unless span_id
          batch << ingestion_event("span-update", {
            id: span_id,
            endTime: iso8601(env.occurred_at),
            output: e.result.content,
            level: e.result.error? ? "ERROR" : "DEFAULT"
          })
        end

        listener.on(Event::RunEnd) do |env|
          e = env.event
          span_id = run_spans[env.run_id]
          next unless span_id
          batch << ingestion_event("span-update", {
            id: span_id,
            endTime: iso8601(env.occurred_at),
            output: e.output,
            level: (e.status == "completed") ? "DEFAULT" : "ERROR"
          })
        end

        listener.on(Event::TaskEnd) do |env|
          e = env.event
          batch << ingestion_event("trace-create", {
            id: trace_id,
            output: e.output
          })
          flush(batch)
        end
      end

      private

      def ingestion_event(type, body)
        {id: SecureRandom.uuid, type: type, timestamp: iso8601(Time.now), body: body}
      end

      def iso8601(time)
        time.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      end

      def truncate(str, max)
        (str.length > max) ? "#{str[0, max - 3]}..." : str
      end

      def flush(batch)
        return if batch.empty?
        @flusher ? @flusher.call(batch) : http_flush(batch)
      rescue => e
        Rixie.logger.warn { "[Langfuse] flush failed: #{e.message}" }
      end

      def http_flush(batch)
        uri = URI("#{@base_url}/api/public/ingestion")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.basic_auth(@public_key, @secret_key)
        req.body = JSON.generate({batch: batch})
        res = http.request(req)
        unless res.code.to_i.between?(200, 299)
          Rixie.logger.warn { "[Langfuse] ingestion returned #{res.code}: #{res.body}" }
          return
        end
        body = JSON.parse(res.body)
        errors = body["errors"]
        if errors&.any?
          Rixie.logger.warn { "[Langfuse] ingestion partial failure: #{errors}" }
        end
      rescue JSON::ParserError
        # ignore unparseable response bodies
      end
    end
  end
end
