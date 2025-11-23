# frozen_string_literal: true

# Pure Ruby implementation of Cataract CSS parser
#
# This is a character-by-character parser that closely mirrors the C implementation.
# ==================================================================
# NO REGEXP ALLOWED - consume chars one at a time like the C version.
# ==================================================================
#
# Load this instead of the C extension with:
#   require 'cataract/pure'
#
# Or run tests with:
#   CATARACT_PURE=1 rake test

# Check if C extension is already loaded
if defined?(Cataract::NATIVE_EXTENSION_LOADED)
  raise LoadError, 'Cataract C extension is already loaded. Cannot load pure Ruby version.'
end

# Define base module and error classes first
module Cataract
  class Error < StandardError; end
  class DepthError < Error; end
  class SizeError < Error; end
end

require_relative 'version'
require_relative 'constants'

# Load struct definitions and supporting files
# (These are also loaded by lib/cataract.rb, but we need them here for direct require)
require_relative 'declaration'
require_relative 'rule'
require_relative 'at_rule'
require_relative 'media_query'
require_relative 'import_statement'
require_relative 'stylesheet_scope'
require_relative 'stylesheet'
require_relative 'declarations'
require_relative 'import_resolver'

# Add to_s method to Declarations class for pure Ruby mode
module Cataract
  class Declarations
    # Serialize declarations to CSS string
    def to_s
      result = String.new
      @values.each_with_index do |decl, i|
        result << decl.property
        result << ': '
        result << decl.value
        result << ' !important' if decl.important
        result << ';'
        result << ' ' if i < @values.length - 1 # Add space after semicolon except for last
      end
      result
    end
  end
end

# Load pure Ruby implementation modules
require_relative 'pure/byte_constants'
require_relative 'pure/helpers'
require_relative 'pure/specificity'
require_relative 'pure/serializer'
require_relative 'pure/parser'
require_relative 'pure/flatten'

module Cataract
  # Flag to indicate pure Ruby version is loaded
  PURE_RUBY_LOADED = true

  # Implementation type constant
  IMPLEMENTATION = :ruby

  # Compile flags (mimic C version)
  COMPILE_FLAGS = {
    debug: false,
    str_buf_optimization: false,
    pure_ruby: true
  }.freeze

  # Parse CSS string and return hash with rules, media_index, charset, etc.
  #
  # @api private
  # @param css_string [String] CSS to parse
  # @param parser_options [Hash] Parser configuration options
  # @option parser_options [Boolean] :selector_lists (true) Track selector lists
  # @return [Hash] {
  #   rules: Array<Rule>,           # Flat array of Rule/AtRule structs
  #   _media_index: Hash,           # Symbol => Array of rule IDs
  #   charset: String|nil,          # @charset value if present
  #   _has_nesting: Boolean         # Whether any nested rules exist
  # }
  def self._parse_css(css_string, parser_options = {})
    parser = Parser.new(css_string, parser_options: parser_options)
    parser.parse
  end

  # NOTE: Copied from cataract.rb
  # Need to untangle this eventually
  def self.parse_css(css, **options)
    Stylesheet.parse(css, **options)
  end

  # Flatten stylesheet rules according to CSS cascade rules
  #
  # @param stylesheet [Stylesheet] Stylesheet to flatten
  # @return [Stylesheet] New stylesheet with flattened rules
  def self.flatten(stylesheet)
    Flatten.flatten(stylesheet, mutate: false)
  end

  # Flatten stylesheet rules in-place (mutates receiver)
  #
  # @param stylesheet [Stylesheet] Stylesheet to flatten
  # @return [Stylesheet] Same stylesheet (mutated)
  def self.flatten!(stylesheet)
    Flatten.flatten(stylesheet, mutate: true)
  end

  # Deprecated: Use flatten instead
  def self.merge(stylesheet)
    warn 'Cataract.merge is deprecated, use Cataract.flatten instead', uplevel: 1
    flatten(stylesheet)
  end

  # Deprecated: Use flatten! instead
  def self.merge!(stylesheet)
    warn 'Cataract.merge! is deprecated, use Cataract.flatten! instead', uplevel: 1
    flatten!(stylesheet)
  end

  # Expand a single shorthand declaration into longhand declarations.
  # Underscore prefix indicates semi-private API - use with caution.
  #
  # @param decl [Declaration] Declaration to expand
  # @return [Array<Declaration>] Array of expanded longhand declarations
  # @api private
  def self.expand_shorthand(decl)
    Flatten.expand_shorthand(decl)
  end

  # Add stub method to Stylesheet for pure Ruby implementation
  class Stylesheet
    # Color conversion is only available in the native C extension
    #
    # @raise [NotImplementedError] Always raises - color conversion requires C extension
    def convert_colors!(*_args)
      raise NotImplementedError, 'convert_colors! is only available in the native C extension'
    end
  end
end
