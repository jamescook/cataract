# frozen_string_literal: true

module Cataract
  # Represents a CSS @import statement
  #
  # @import statements are parsed and stored separately in the stylesheet's @_imports array.
  # They can later be resolved by the ImportResolver to fetch and inline the imported CSS.
  #
  # Per CSS spec, @import must appear before all rules except @charset and @layer.
  # Any @import that appears after a style rule is invalid and will be ignored with a warning.
  #
  # @example Basic import
  #   @import "styles.css";
  #   # => ImportStatement(url: "styles.css", media: nil)
  #
  # @example Import with media query
  #   @import "mobile.css" screen and (max-width: 768px);
  #   # => ImportStatement(url: "mobile.css", media_query_id: 0)
  #
  # @attr [Integer] id The import's position in the source (0-indexed)
  # @attr [String] url The URL to import (without quotes or url() wrapper)
  # @attr [String, nil] media The media query string (e.g., "print", "screen and (max-width: 768px)"), or nil
  # @attr [Integer, nil] media_query_id The MediaQuery ID, or nil if no media query
  # @attr [Boolean] resolved Whether this import has been resolved/processed
  ImportStatement = Struct.new(:id, :url, :media, :media_query_id, :resolved) unless const_defined?(:ImportStatement)

  class ImportStatement
    # Factory method for creating ImportStatement in tests.
    # Uses keyword arguments to avoid positional parameter confusion.
    #
    # @param id [Integer] Import ID (position in source)
    # @param url [String] URL to import
    # @param media [String, nil] Media query string (e.g., "print", "screen and (max-width: 768px)")
    # @param media_query_id [Integer, nil] MediaQuery ID
    # @param resolved [Boolean] Whether import has been resolved
    # @return [ImportStatement] New import statement instance
    #
    # @example Create an import with keyword arguments
    #   ImportStatement.make(
    #     id: 0,
    #     url: 'styles.css',
    #     media: nil,
    #     media_query_id: nil,
    #     resolved: false
    #   )
    def self.make(id:, url:, media: nil, media_query_id: nil, resolved: false)
      new(id, url, media, media_query_id, resolved)
    end

    # Compare two ImportStatement objects for equality.
    # Two imports are equal if they have the same URL and media query.
    # The import ID is ignored as it's an implementation detail.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if equal, false otherwise
    def ==(other)
      return false unless other.is_a?(ImportStatement)

      # Compare by media string (for unparsed imports) or media_query_id (for resolved imports)
      url == other.url && media == other.media
    end

    alias eql? ==

    # Generate hash code for ImportStatement.
    # Uses URL and media string (ignores import ID position).
    #
    # @return [Integer] Hash code
    def hash
      [url, media].hash
    end
  end
end
