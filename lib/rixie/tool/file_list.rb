# frozen_string_literal: true

require_relative "file_sandbox"

module Rixie
  class Tool
    build = ->(root_dir: nil) {
      Tool.new(
        name: "file_list",
        description: "List files matching a glob pattern within the configured root directory. " \
                     "Patterns are relative to root_dir; matches that escape root_dir are filtered out.",
        input_schema: {
          type: "object",
          properties: {
            pattern: {
              type: "string",
              description: "Glob pattern, e.g. '**/*.rb', 'src/*.js', 'lib/**/*'"
            }
          },
          required: ["pattern"]
        },
        call: ->(args) {
          base = FileSandbox.root(root_dir)
          pattern = (args["pattern"] || args[:pattern]).to_s
          matches = Dir.glob(pattern, base: base).select do |rel|
            FileSandbox.resolve(base, rel)
            true
          rescue FileSandbox::PathError
            false
          end
          matches.sort!
          matches.empty? ? "No files matched." : matches.join("\n")
        }
      )
    }
    FileList = build.call
    FileList.define_singleton_method(:with, &build)
  end
end
