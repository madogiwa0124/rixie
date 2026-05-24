# frozen_string_literal: true

module Rixie
  class Tool
    # Shared path resolution + safety check for file_read / file_list / file_search.
    # Rejects paths that escape the configured root directory after expansion.
    module FileSandbox
      class PathError < StandardError; end

      def self.root(root_dir)
        File.expand_path(root_dir || Dir.pwd)
      end

      def self.resolve(root_dir, relative_path)
        segments = relative_path.to_s.split(%r{[/\\]})
        raise PathError, "Path '#{relative_path}' contains '..' segment" if segments.include?("..")

        base = root(root_dir)
        target = File.expand_path(relative_path.to_s, base)
        return target if target == base || target.start_with?(base + File::SEPARATOR)

        raise PathError, "Path '#{relative_path}' is outside root_dir"
      end

      BINARY_PROBE_BYTES = 8192
      private_constant :BINARY_PROBE_BYTES

      def self.binary?(path)
        File.open(path, "rb") { |f| f.read(BINARY_PROBE_BYTES).to_s.include?("\0") }
      end
    end
  end
end
