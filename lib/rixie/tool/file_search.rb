# frozen_string_literal: true

require_relative "file_sandbox"

module Rixie
  class Tool
    DEFAULT_FILE_SEARCH_RESULTS = 50
    DEFAULT_FILE_SEARCH_GLOB = "**/*"
    private_constant :DEFAULT_FILE_SEARCH_RESULTS, :DEFAULT_FILE_SEARCH_GLOB

    build = ->(root_dir: nil) {
      Tool.new(
        name: "file_search",
        description: "Search file contents for a regex pattern within the configured root directory. " \
                     "Returns matching lines in 'path:lineno:content' format. " \
                     "Binary files are skipped.",
        input_schema: {
          type: "object",
          properties: {
            pattern: {
              type: "string",
              description: "Regex pattern to search for"
            },
            glob: {
              type: "string",
              description: "Optional glob filter for files. Defaults to '#{DEFAULT_FILE_SEARCH_GLOB}'."
            },
            max_results: {
              type: "integer",
              description: "Maximum matches to return. Defaults to #{DEFAULT_FILE_SEARCH_RESULTS}."
            }
          },
          required: ["pattern"]
        },
        call: ->(args) {
          begin
            base = FileSandbox.root(root_dir)
            pattern = (args["pattern"] || args[:pattern]).to_s
            glob = (args["glob"] || args[:glob] || DEFAULT_FILE_SEARCH_GLOB).to_s
            max = (args["max_results"] || args[:max_results] || DEFAULT_FILE_SEARCH_RESULTS).to_i
            regex = Regexp.new(pattern)

            results = []
            catch(:done) do
              Dir.glob(glob, base: base).sort.each do |rel|
                full = begin
                  FileSandbox.resolve(base, rel)
                rescue FileSandbox::PathError
                  next
                end
                next unless File.file?(full)
                next if FileSandbox.binary?(full)

                File.foreach(full).with_index(1) do |line, lineno|
                  next unless line.match?(regex)
                  results << "#{rel}:#{lineno}:#{line.chomp}"
                  throw :done if results.size >= max
                end
              end
            end

            results.empty? ? "No matches found." : results.join("\n")
          rescue RegexpError => e
            "Error: invalid regex: #{e.message}"
          end
        }
      )
    }
    FileSearch = build.call
    FileSearch.define_singleton_method(:with, &build)
  end
end
