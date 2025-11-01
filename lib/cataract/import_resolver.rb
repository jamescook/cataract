# frozen_string_literal: true

require 'uri'
require 'open-uri'
require 'set'

module Cataract
  # Error raised during import resolution
  class ImportError < Error; end

  # Resolves @import statements in CSS
  # Handles fetching imported files and inlining them with proper security controls
  module ImportResolver
    # Default options for safe import resolution
    SAFE_DEFAULTS = {
      max_depth: 5,                      # Prevent infinite recursion
      allowed_schemes: ['https'],        # Only HTTPS by default
      extensions: ['css'],               # Only .css files
      timeout: 10,                       # 10 second timeout for fetches
      follow_redirects: true,            # Follow redirects
      base_path: nil                     # Base path for resolving relative imports
    }.freeze

    # Resolve @import statements in CSS
    #
    # @param css [String] CSS content with @import statements
    # @param options [Hash] Import resolution options
    # @param depth [Integer] Current recursion depth (internal)
    # @param imported_urls [Set] Set of already imported URLs to prevent circular references
    # @return [String] CSS with imports inlined
    def self.resolve(css, options = {}, depth: 0, imported_urls: Set.new)
      # Normalize options
      opts = normalize_options(options)

      # Check recursion depth
      # depth starts at 0, max_depth is count of imports allowed
      # depth 0: parsing main file (counts as import 1)
      # depth 1: parsing first @import  (counts as import 2)
      # depth 2: parsing nested @import (counts as import 3)
      if depth > opts[:max_depth]
        raise ImportError, "Import nesting too deep: exceeded maximum depth of #{opts[:max_depth]}"
      end

      # Find all @import statements at the top of the file
      # Per CSS spec, @import must come before all rules except @charset
      imports = extract_imports(css)

      return css if imports.empty?

      # Process each import
      resolved_css = +'' # Mutable string
      remaining_css = css

      imports.each do |import_data|
        url = import_data[:url]
        media = import_data[:media]

        # Validate URL
        validate_url(url, opts)

        # Check for circular references
        raise ImportError, "Circular import detected: #{url}" if imported_urls.include?(url)

        # Fetch imported CSS
        imported_css = fetch_url(url, opts)

        # Recursively resolve imports in the imported CSS
        imported_urls_copy = imported_urls.dup
        imported_urls_copy.add(url)
        imported_css = resolve(imported_css, opts, depth: depth + 1, imported_urls: imported_urls_copy)

        # Wrap in @media if import had media query
        imported_css = "@media #{media} {\n#{imported_css}\n}" if media

        resolved_css << imported_css << "\n"

        # Remove this import from remaining CSS
        remaining_css = remaining_css.sub(import_data[:full_match], '')
      end

      # Return resolved imports + remaining CSS
      resolved_css + remaining_css
    end

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

    # Extract @import statements from CSS
    # Returns array of hashes: { url: "...", media: "...", full_match: "..." }
    # Delegates to C implementation for performance
    def self.extract_imports(css)
      Cataract.extract_imports(css)
    end

    # Normalize URL - handle relative paths and missing schemes
    # Returns a URI object
    def self.normalize_url(url, base_path = nil)
      # Try to parse as-is first
      uri = URI.parse(url)

      # If no scheme, treat as relative file path
      if uri.scheme.nil?
        # Convert to file:// URL
        # Relative paths stay relative, absolute paths stay absolute
        if url.start_with?('/')
          uri = URI.parse("file://#{url}")
        else
          # Relative path - make it absolute relative to base_path or current directory
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
      uri = normalize_url(url, options[:base_path])

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

    # Fetch content from URL
    def self.fetch_url(url, options)
      uri = normalize_url(url, options[:base_path])

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

    # Fetch content via HTTP/HTTPS
    def self.fetch_http(uri, options)
      # Use open-uri with timeout
      open_uri_options = {
        read_timeout: options[:timeout],
        redirect: options[:follow_redirects]
      }

      # Use uri.open instead of URI.open to avoid shell command injection
      uri.open(open_uri_options, &:read)
    end
  end
end
