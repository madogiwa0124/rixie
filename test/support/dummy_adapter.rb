# frozen_string_literal: true

class DummyAdapter
  def initialize(responses)
    @responses = responses.dup
  end

  def chat(messages, tools:)
    raise "DummyAdapter exhausted: no more responses enqueued" if @responses.empty?
    @responses.shift
  end
end
