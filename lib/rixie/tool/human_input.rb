# frozen_string_literal: true

module Rixie
  class Tool
    HumanInput = Tool.new(
      name: "human_input",
      description: "Call this tool when you need input, clarification, or approval from " \
                   "the user before proceeding. The user will see your question and reply " \
                   "in the next message.",
      input_schema: {
        type: "object",
        properties: {
          question: {
            type: "string",
            description: "The question or prompt to present to the user"
          }
        },
        required: ["question"]
      },
      call: ->(args) { args["question"] },
      return_direct: true
    )
  end
end
