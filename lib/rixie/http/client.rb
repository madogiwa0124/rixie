# frozen_string_literal: true

require "net/http"
require "uri"
require "zlib"
require "stringio"
require "openssl"
require "socket"

module Rixie
  module Http
    class Client
      DEFAULT_TIMEOUT = 30
      DEFAULT_HEADERS = {"User-Agent" => "Rixie/#{Rixie::VERSION}"}.freeze
      CONNECTION_ERRORS = [
        Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ECONNREFUSED,
        Errno::EADDRNOTAVAIL, Errno::ENETUNREACH,
        SocketError, OpenSSL::SSL::SSLError
      ].freeze
      REDIRECT_CODES = [301, 302, 303, 307, 308].freeze

      def initialize(timeout: DEFAULT_TIMEOUT, headers: {}, http_client: nil, allow_private: false)
        @timeout = timeout
        @default_headers = DEFAULT_HEADERS.merge(headers)
        @http_client = http_client
        @allow_private = allow_private
      end

      def get(url)
        validate_url!(url)
        execute_request(url) { |uri| Net::HTTP::Get.new(uri) }
      end

      def post(url, body: nil)
        validate_url!(url)
        execute_request(url) do |uri|
          req = Net::HTTP::Post.new(uri)
          req.body = body
          req
        end
      end

      private

      def validate_url!(url)
        uri = URI.parse(url)
        raise Rixie::Http::SSRFError, "Blocked scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)
        return if @allow_private
        host = uri.host.to_s
        raise Rixie::Http::SSRFError, "Blocked host: #{host}" if blocked_host?(host)
      end

      def execute_request(url, redirect_count: 0, &build_request)
        uri = URI.parse(url)
        http = http_client_for(uri)
        request = build_request.call(uri)
        @default_headers.each { |k, v| request[k] = v }
        response = http.request(request)

        return follow_redirect(url, response, redirect_count) if REDIRECT_CODES.include?(response.code.to_i)

        {status: response.code.to_i, headers: normalize_headers(response.to_hash), body: decode_body(response)}
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise Rixie::Http::TimeoutError, e.message
      rescue *CONNECTION_ERRORS => e
        raise Rixie::Http::ConnectionError, e.message
      rescue Rixie::Http::Error
        raise
      rescue => e
        raise Rixie::Http::Error, e.message
      end

      MAX_REDIRECTS = 5
      private_constant :MAX_REDIRECTS
      def follow_redirect(original_url, response, redirect_count)
        raise Rixie::Http::ConnectionError, "Too many redirects" if redirect_count >= MAX_REDIRECTS
        location = response["location"]
        raise Rixie::Http::ConnectionError, "Redirect missing Location header" unless location
        location = URI.join(original_url, location).to_s
        validate_url!(location)
        execute_request(location, redirect_count: redirect_count + 1) { |u| Net::HTTP::Get.new(u) }
      end

      def http_client_for(uri)
        return @http_client if @http_client

        build_http_client(uri)
      end

      def build_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        unless @allow_private
          addresses = Socket.getaddrinfo(uri.host, nil, nil, :STREAM).map { |a| a[3] }
          addresses.each do |ip|
            raise Rixie::Http::SSRFError, "Blocked host: #{ip}" if blocked_host?(ip)
          end
          http.ipaddr = addresses.first
        end
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        http
      end

      # NOTE: This regex is not exhaustive but covers common private IP ranges and localhost.
      #       The http client also performs DNS resolution and checks resolved IPs against this pattern to mitigate SSRF risks.
      BLOCKED_HOSTS = /\A(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|localhost|0\.0\.0\.0)/
      private_constant :BLOCKED_HOSTS
      def blocked_host?(host)
        return true if host.match?(BLOCKED_HOSTS)
        lower = host.delete_prefix("[").delete_suffix("]").downcase
        for_ipv6 = ->(host, lower) {
          ipv6_host = host.include?(":")
          loopback = lower == "::1"
          private_host = lower.start_with?("fc", "fd", "fe80:", "::ffff:")
          ipv6_host && (loopback || private_host)
        }
        for_ipv6.call(host, lower)
      end

      def normalize_headers(headers)
        headers.transform_keys(&:downcase)
      end

      def decode_body(response)
        encoding = response["content-encoding"]
        return response.body unless encoding

        case encoding.downcase
        when "gzip"
          Zlib::GzipReader.new(StringIO.new(response.body)).read
        when "deflate"
          Zlib::Inflate.inflate(response.body)
        else
          response.body
        end
      end
    end
  end
end
