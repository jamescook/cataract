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
  raise LoadError, "Cataract C extension is already loaded. Cannot load pure Ruby version."
end

# Define base module and error classes first
module Cataract
  class Error < StandardError; end
  class DepthError < Error; end
  class SizeError < Error; end
end

require_relative 'version'

# Define structs that are normally defined in C land
# These must be defined BEFORE loading the Ruby decorator files
module Cataract
  # Rule struct: (id, selector, declarations, specificity, parent_rule_id, nesting_style)
  # - id: Integer (0-indexed position in @rules array)
  # - selector: String (fully resolved/flattened selector)
  # - declarations: Array of Declaration
  # - specificity: Integer | nil (calculated lazily)
  # - parent_rule_id: Integer | nil (parent rule ID for nested rules)
  # - nesting_style: Integer | nil (0=implicit, 1=explicit, nil=not nested)
  Rule = Struct.new(:id, :selector, :declarations, :specificity, :parent_rule_id, :nesting_style)

  # Declaration struct: (property, value, important)
  # - property: String (CSS property name, lowercased)
  # - value: String (CSS property value)
  # - important: Boolean (true if !important)
  Declaration = Struct.new(:property, :value, :important)

  # AtRule struct: (id, selector, content, specificity)
  # Matches Rule interface for duck-typing
  # - id: Integer (0-indexed position in @rules array)
  # - selector: String (e.g., "@keyframes fade", "@font-face")
  # - content: Array of Rule or Declaration
  # - specificity: Always nil for at-rules
  AtRule = Struct.new(:id, :selector, :content, :specificity)

  # Declarations class for to_s method (used in merge operations)
  class Declarations < Array
    def to_s
      map { |d| "#{d.property}: #{d.value}#{d.important ? ' !important' : ''}" }.join('; ')
    end
  end
end

# Now load the Ruby decorator files that add methods to these structs
require_relative 'rule'
require_relative 'at_rule'
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
        result << ": "
        result << decl.value
        result << " !important" if decl.important
        result << ";"
        result << " " if i < @values.length - 1  # Add space after semicolon except for last
      end
      result
    end
  end
end

# Load pure Ruby implementation modules
require_relative 'pure/byte_constants'
require_relative 'pure/helpers'
require_relative 'pure/specificity'
require_relative 'pure/imports'
require_relative 'pure/serializer'
require_relative 'pure/parser'
require_relative 'pure/merge'

module Cataract
  # Flag to indicate pure Ruby version is loaded
  PURE_RUBY_LOADED = true

  # Compile flags (mimic C version)
  COMPILE_FLAGS = {
    debug: false,
    str_buf_optimization: false,
    pure_ruby: true
  }.freeze

  # ============================================================================
  # CORE PARSING
  # ============================================================================

  # Parse CSS string and return hash with rules, media_index, charset, etc.
  #
  # @param css_string [String] CSS to parse
  # @return [Hash] {
  #   rules: Array<Rule>,           # Flat array of Rule/AtRule structs
  #   _media_index: Hash,           # Symbol => Array of rule IDs
  #   charset: String|nil,          # @charset value if present
  #   _has_nesting: Boolean         # Whether any nested rules exist
  # }
  def self._parse_css(css_string)
    parser = Parser.new(css_string)
    parser.parse
  end

  # Parse CSS declarations from string (stub - not yet implemented)
  #
  # @param declarations_string [String] CSS declarations (e.g., "color: red; font-size: 14px")
  # @return [Array<Declaration>] Array of Declaration structs
  def self.parse_declarations(declarations_string)
    # TODO: Implement declaration parsing
    # Char-by-char, no regexp
    []
  end

  # ============================================================================
  # MERGING
  # ============================================================================

  # Merge stylesheet rules according to CSS cascade rules
  #
  # @param stylesheet [Stylesheet] Stylesheet to merge
  # @return [Stylesheet] New stylesheet with merged rules
  def self.merge(stylesheet)
    Merge.merge(stylesheet, mutate: false)
  end

  # Merge stylesheet rules in-place (mutates receiver)
  #
  # @param stylesheet [Stylesheet] Stylesheet to merge
  # @return [Stylesheet] Same stylesheet (mutated)
  def self.merge!(stylesheet)
    Merge.merge(stylesheet, mutate: true)
  end
end
