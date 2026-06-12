# frozen_string_literal: true

module Rixie
  module Subscribers
    # Sends Rixie events to an OpenTelemetry-compatible backend via OTLP HTTP.
    #
    # Span hierarchy:
    #   Task     → OTel Span (root)
    #   Run      → OTel Span (child of Task)
    #   LLM call → OTel Span (child of Run, kind=CLIENT)
    #   Tool call → OTel Span (child of Run)
    #
    # Requires: opentelemetry-sdk and opentelemetry-exporter-otlp gems.
    # These are optional — a ConfigurationError is raised if missing.
    class OpenTelemetry < Rixie::Subscriber
      def initialize(service_name:, endpoint: nil, headers: {}, tracer_provider: nil)
        @service_name = service_name
        @endpoint = endpoint
        @headers = headers
        @tracer_provider = tracer_provider
      end

      def subscribe(listener)
        tracer = resolve_tracer
        task_span = nil
        run_spans = {}   # run_id => span
        llm_spans = {}   # [run_id, step_count] => span
        tool_spans = {}  # tool_call.id => span

        listener.on(Event::TaskStart) do |env|
          e = env.event
          task_span = tracer.start_span(
            "task",
            attributes: {
              "rixie.task.strategy" => e.strategy.class.name,
              "rixie.task.input" => e.user_input.to_s.slice(0, 1000)
            },
            kind: :internal
          )
        end

        listener.on(Event::RunStart) do |env|
          next unless task_span
          ctx = ::OpenTelemetry::Trace.context_with_span(task_span)
          run_spans[env.run_id] = tracer.start_span(
            "run",
            with_parent: ctx,
            attributes: {"rixie.run.input" => env.event.user_input.to_s.slice(0, 1000)},
            kind: :internal
          )
        end

        listener.on(Event::LlmCallStart) do |env|
          e = env.event
          run_span = run_spans[env.run_id]
          next unless run_span
          ctx = ::OpenTelemetry::Trace.context_with_span(run_span)
          llm_spans[[env.run_id, e.step_count]] = tracer.start_span(
            "gen_ai.chat",
            with_parent: ctx,
            attributes: {
              "gen_ai.operation.name" => "chat",
              "gen_ai.system" => e.provider.to_s,
              "gen_ai.request.model" => e.model.to_s,
              "rixie.llm.step" => e.step_count
            },
            kind: :client
          )
        end

        listener.on(Event::LlmCallEnd) do |env|
          e = env.event
          span = llm_spans.delete([env.run_id, e.step_count])
          next unless span
          span.set_attribute("gen_ai.usage.input_tokens", e.usage[:input_tokens]) if e.usage[:input_tokens]
          span.set_attribute("gen_ai.usage.output_tokens", e.usage[:output_tokens]) if e.usage[:output_tokens]
          span.set_attribute("gen_ai.response.finish_reasons", e.finish_reason.to_s)
          span.finish
        end

        listener.on(Event::ToolCallStart) do |env|
          tc = env.event.tool_call
          run_span = run_spans[env.run_id]
          next unless run_span
          ctx = ::OpenTelemetry::Trace.context_with_span(run_span)
          tool_spans[tc.id] = tracer.start_span(
            "tool.#{tc.name}",
            with_parent: ctx,
            attributes: {
              "gen_ai.tool.name" => tc.name,
              "rixie.tool.call_id" => tc.id
            },
            kind: :internal
          )
        end

        listener.on(Event::ToolCallEnd) do |env|
          e = env.event
          span = tool_spans.delete(e.tool_call.id)
          next unless span
          if e.result.error?
            span.status = ::OpenTelemetry::Trace::Status.error(e.result.content.to_s.slice(0, 200))
          end
          span.finish
        end

        listener.on(Event::RunEnd) do |env|
          span = run_spans.delete(env.run_id)
          next unless span
          if env.event.status != "completed"
            span.status = ::OpenTelemetry::Trace::Status.error(env.event.status.to_s)
          end
          span.finish
        end

        listener.on(Event::TaskEnd) do |env|
          next unless task_span
          if env.event.status != "completed"
            task_span.status = ::OpenTelemetry::Trace::Status.error(env.event.status.to_s)
          end
          task_span.finish
        end
      end

      private

      def resolve_tracer
        @tracer ||= if @tracer_provider
          @tracer_provider.tracer(@service_name, Rixie::VERSION)
        else
          build_tracer
        end
      end

      def build_tracer
        begin
          require "opentelemetry/sdk"
          require "opentelemetry/exporter/otlp"
        rescue LoadError
          raise Rixie::ConfigurationError,
            "opentelemetry-sdk and opentelemetry-exporter-otlp gems are required for OpenTelemetry tracing. " \
            "Add `gem 'opentelemetry-sdk'` and `gem 'opentelemetry-exporter-otlp'` to your Gemfile."
        end

        resource = ::OpenTelemetry::SDK::Resources::Resource.create(
          "service.name" => @service_name
        )
        exporter_opts = {}
        exporter_opts[:endpoint] = @endpoint if @endpoint
        exporter_opts[:headers] = @headers if @headers.any?
        exporter = ::OpenTelemetry::Exporter::OTLP::Exporter.new(**exporter_opts)
        processor = ::OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
        provider = ::OpenTelemetry::SDK::Trace::TracerProvider.new(resource: resource)
        provider.add_span_processor(processor)
        provider.tracer(@service_name, Rixie::VERSION)
      end
    end
  end
end
