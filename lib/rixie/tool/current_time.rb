# frozen_string_literal: true

require "time"

module Rixie
  class Tool
    CurrentTime = Tool.new(
      name: "current_time",
      description: "Get the current date and time as an ISO 8601 string. " \
                   "LLMs do not know the current time on their own — call this " \
                   "when the user asks about \"now\", \"today\", relative dates, " \
                   "or anything time-sensitive.",
      input_schema: {
        type: "object",
        properties: {
          timezone: {
            type: "string",
            description: "Either 'local' (system local time) or 'utc'. Defaults to 'local'.",
            enum: ["local", "utc"]
          }
        }
      },
      call: ->(args) {
        tz = (args["timezone"] || args[:timezone] || "local").to_s.downcase
        time = (tz == "utc") ? Time.now.utc : Time.now
        time.iso8601
      }
    )
  end
end
