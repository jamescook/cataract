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
  #   # => ImportStatement(url: "mobile.css", media: :"screen and (max-width: 768px)")
  #
  # @attr [Integer] id The import's position in the source (0-indexed)
  # @attr [String] url The URL to import (without quotes or url() wrapper)
  # @attr [Symbol, nil] media The media query as a symbol, or nil if no media query
  # @attr [Boolean] resolved Whether this import has been resolved/processed
  ImportStatement = Struct.new(:id, :url, :media, :resolved) unless const_defined?(:ImportStatement)

  class ImportStatement
    # Compare two ImportStatement objects for equality.
    # Two imports are equal if they have the same URL and media query.
    # The ID is ignored as it's an implementation detail.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if equal, false otherwise
    def ==(other)
      return false unless other.is_a?(ImportStatement)

      url == other.url && media == other.media
    end

    alias eql? ==

    # Generate hash code for ImportStatement.
    # Uses URL and media query (ignores ID).
    #
    # @return [Integer] Hash code
    def hash
      [url, media].hash
    end
  end
end
