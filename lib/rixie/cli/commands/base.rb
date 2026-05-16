# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Base
        def initialize(renderer:)
          @renderer = renderer
        end

        def name
          raise NotImplementedError
        end

        def description
          raise NotImplementedError
        end

        def call(arg, cli:)
          raise NotImplementedError
        end

        def complete(input)
          []
        end

        private

        attr_reader :renderer
      end
    end
  end
end
