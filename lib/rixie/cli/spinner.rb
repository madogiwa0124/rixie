# frozen_string_literal: true

module Rixie
  class CLI
    class Spinner
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      def initialize(terminal:, prefix:, io: $stdout)
        @terminal = terminal
        @prefix = prefix
        @io = io
        @mutex = Mutex.new
        @stopped = true
        @thread = nil
      end

      def start
        return self unless stopped?

        @mutex.synchronize { @stopped = false }
        @thread = Thread.new do
          i = 0
          loop do
            break if @mutex.synchronize { @stopped }
            @io.print "\r#{@prefix}#{@terminal.accent(FRAMES[i % FRAMES.size])} Thinking..."
            @io.flush
            i += 1
            sleep 0.08
          end
        end
        self
      end

      def stop
        return if stopped?
        @mutex.synchronize { @stopped = true }
        @thread&.join
        @io.print "\r#{@prefix}#{" " * 20}\r#{@prefix}"
        @io.flush
      end

      def stopped?
        @mutex.synchronize { @stopped }
      end
    end
  end
end
