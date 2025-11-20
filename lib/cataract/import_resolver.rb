# frozen_string_literal: true

require 'uri'
require 'open-uri'

module Cataract
  # Error raised during import resolution
  class ImportError < Error; end

  # Resolves @import statements in CSS
  # Handles fetching imported files and inlining them with proper security controls
  module ImportResolver
    # Default fetcher implementation using File I/O and Net::HTTP
    # Can be replaced with custom fetchers for different environments (e.g., browser, caching)
    class DefaultFetcher
      # Fetch content from a URL
      #
      # @param url [String] URL to fetch
      # @param options [Hash] Import resolution options
      # @return [String] Fetched content
      # @raise [ImportError] If fetching fails
      def call(url, options)
        uri = ImportResolver.normalize_url(url, base_path: options[:base_path], base_uri: options[:base_uri])

        case uri.scheme
        when 'file'
          # Read from local filesystem
          File.read(uri.path)
        when 'http', 'https'
          # Fetch from network
          fetch_http(uri, options)
        else
          raise ImportError, "Unsupported scheme: #{uri.scheme}"
        end
      rescue Errno::ENOENT
        raise ImportError, "Import file not found: #{url}"
      rescue OpenURI::HTTPError => e
        raise ImportError, "HTTP error fetching import: #{url} (#{e.message})"
      rescue SocketError => e
        raise ImportError, "Network error fetching import: #{url} (#{e.message})"
      rescue StandardError => e
        raise ImportError, "Error fetching import: #{url} (#{e.class}: #{e.message})"
      end

      private

      # Fetch content via HTTP/HTTPS
      def fetch_http(uri, options)
        # Use open-uri with timeout
        open_uri_options = {
          read_timeout: options[:timeout],
          redirect: options[:follow_redirects]
        }

        # Use uri.open instead of URI.open to avoid shell command injection
        uri.open(open_uri_options, &:read)
      end
    end

    # Default options for safe import resolution
    SAFE_DEFAULTS = {
      max_depth: 5,                      # Prevent infinite recursion
      allowed_schemes: ['https'],        # Only HTTPS by default
      extensions: ['css'],               # Only .css files
      timeout: 10,                       # 10 second timeout for fetches
      follow_redirects: true,            # Follow redirects
      base_path: nil,                    # Base path for resolving relative file imports
      base_uri: nil,                     # Base URI for resolving relative HTTP imports
      fetcher: nil                       # Custom fetcher (defaults to DefaultFetcher)
    }.freeze

    # Normalize options with safe defaults
    def self.normalize_options(options)
      if options == true
        # imports: true -> use safe defaults
        SAFE_DEFAULTS.dup
      elsif options.is_a?(Hash)
        # imports: { ... } -> merge with safe defaults
        SAFE_DEFAULTS.merge(options)
      else
        raise ArgumentError, 'imports option must be true or a Hash'
      end
    end

    # Normalize URL - handle relative paths and missing schemes
    # Returns a URI object
    #
    # @param url [String] URL to normalize
    # @param base_path [String, nil] Base path for resolving relative file imports
    # @param base_uri [String, nil] Base URI for resolving relative HTTP imports
    def self.normalize_url(url, base_path: nil, base_uri: nil)
      # Try to parse as-is first
      uri = URI.parse(url)

      # If no scheme, treat as relative path
      if uri.scheme.nil?
        # If we have a base_uri (HTTP/HTTPS), resolve against it
        if base_uri
          base = URI.parse(base_uri)
          uri = base.merge(url)
        elsif url.start_with?('/')
          # Absolute file path
          uri = URI.parse("file://#{url}")
        else
          # Relative file path - make it absolute relative to base_path or current directory
          absolute_path = if base_path
                            File.expand_path(url, base_path)
                          else
                            File.expand_path(url)
                          end
          uri = URI.parse("file://#{absolute_path}")
        end
      end

      uri
    rescue URI::InvalidURIError => e
      raise ImportError, "Invalid import URL: #{url} (#{e.message})"
    end

    # Validate URL against security options
    def self.validate_url(url, options)
      uri = normalize_url(url, base_path: options[:base_path], base_uri: options[:base_uri])

      # Check scheme
      unless options[:allowed_schemes].include?(uri.scheme)
        raise ImportError,
              "Import scheme '#{uri.scheme}' not allowed. Allowed schemes: #{options[:allowed_schemes].join(', ')}"
      end

      # Check extension
      path = uri.path || ''
      ext = File.extname(path).delete_prefix('.')

      unless ext.empty? || options[:extensions].include?(ext)
        raise ImportError,
              "Import extension '.#{ext}' not allowed. Allowed extensions: #{options[:extensions].join(', ')}"
      end

      # Additional security checks for file:// scheme
      if uri.scheme == 'file'
        # Resolve to absolute path to prevent directory traversal
        file_path = uri.path

        # Check file exists and is readable
        unless File.exist?(file_path) && File.readable?(file_path)
          raise ImportError, "Import file not found or not readable: #{file_path}"
        end

        # Prevent reading sensitive files (basic check)
        dangerous_paths = ['/etc/', '/proc/', '/sys/', '/dev/']
        if dangerous_paths.any? { |prefix| file_path.start_with?(prefix) }
          raise ImportError, "Import of sensitive system files not allowed: #{file_path}"
        end
      end

      true
    rescue URI::InvalidURIError => e
      raise ImportError, "Invalid import URL: #{url} (#{e.message})"
    end
  end
end
