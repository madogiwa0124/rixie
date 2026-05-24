# frozen_string_literal: true

require_relative "file_sandbox"

module Rixie
  class Tool
    DEFAULT_FILE_READ_LIMIT = 2000
    private_constant :DEFAULT_FILE_READ_LIMIT

    build = ->(root_dir: nil) {
      Tool.new(
        name: "file_read",
        description: "Read a text file from the configured root directory. " \
                     "Paths are relative to root_dir; absolute or '..' paths that " \
                     "escape root_dir are rejected. Binary files are not returned.",
        input_schema: {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the file, relative to root_dir"
            },
            offset: {
              type: "integer",
              description: "Line number to start reading from (1-indexed). Defaults to 1."
            },
            limit: {
              type: "integer",
              description: "Maximum number of lines to read. Defaults to #{DEFAULT_FILE_READ_LIMIT}."
            }
          },
          required: ["path"]
        },
        call: ->(args) {
          begin
            rel_path = args["path"] || args[:path]
            target = FileSandbox.resolve(root_dir, rel_path)
            next "Error: File not found: #{rel_path}" unless File.file?(target)
            next "Error: Binary file not supported: #{rel_path}" if FileSandbox.binary?(target)

            offset = (args["offset"] || args[:offset] || 1).to_i
            limit = (args["limit"] || args[:limit] || DEFAULT_FILE_READ_LIMIT).to_i
            File.foreach(target).drop(offset - 1).take(limit).join
          rescue FileSandbox::PathError => e
            "Error: #{e.message}"
          end
        }
      )
    }
    FileRead = build.call
    FileRead.define_singleton_method(:with, &build)
  end
end
