# frozen_string_literal: true

require_relative 'cataract/version'
require_relative 'cataract/cataract' # Load C extension first (defines Rule struct)
require_relative 'cataract/cataract_new' # Load new parallel C extension (defines NewRule struct)
require_relative 'cataract/rule' # Add Ruby methods to Rule
require_relative 'cataract/stylesheet'
require_relative 'cataract/new_stylesheet' # New parallel implementation
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/import_resolver'

# Cataract is a high-performance CSS parser written in C with a Ruby interface.
#
# It provides fast CSS parsing, rule querying, cascade merging, and serialization.
# Designed for performance-critical applications that need to process large amounts of CSS.
#
# @example Basic usage
#   require 'cataract'
#
#   # Parse CSS
#   sheet = Cataract.parse_css("body { color: red; } h1 { color: blue; }")
#
#   # Query rules
#   sheet.each_selector { |selector, declarations, specificity, media| ... }
#
#   # Merge with cascade rules
#   merged = Cataract.merge(sheet)
#
# @see Stylesheet Main class for working with parsed CSS
# @see RuleSet Represents individual CSS rules
module Cataract
  class << self
    alias parse_css_internal parse_css

    # Parse a CSS string into a Stylesheet object.
    #
    # This is the main entry point for parsing CSS. It returns a Stylesheet
    # object that can be queried, modified, and serialized.
    #
    # @param css [String] The CSS string to parse
    # @param imports [Boolean, Hash] Whether to resolve @import statements.
    #   Pass true to enable with defaults, or a hash with options:
    #   - allowed_schemes: Array of allowed URI schemes (default: ['https'])
    #   - extensions: Array of allowed file extensions (default: ['css'])
    #   - max_depth: Maximum import nesting depth (default: 5)
    #   - base_path: Base directory for resolving relative imports
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS rules
    # @raise [IOError] If import resolution fails and io_exceptions option is enabled
    #
    # @example Parse simple CSS
    #   sheet = Cataract.parse_css("body { color: red; }")
    #   sheet.size #=> 1
    #
    # @example Parse with imports
    #   sheet = Cataract.parse_css("@import 'style.css';", imports: true)
    #
    # @example Parse with import options
    #   sheet = Cataract.parse_css(css, imports: {
    #     allowed_schemes: ['https', 'file'],
    #     base_path: '/path/to/css'
    #   })
    #
    # @see Stylesheet#parse
    # @see Stylesheet.parse
    def parse_css(css, imports: false)
      # Resolve @import statements if requested
      css = ImportResolver.resolve(css, imports) if imports

      Stylesheet.parse(css)
    end
  end

  # Merge multiple CSS rules according to CSS cascade rules.
  #
  # Takes multiple rules (typically with the same selector) and merges their
  # declarations according to CSS cascade rules. This is useful for computing
  # the final computed style for an element.
  #
  # @param rules [Array<Rule>, Stylesheet, Enumerator] Rules to merge.
  #   Can be an array of Rule structs, a Stylesheet object, or an Enumerator.
  # @return [Array<Declaration>] Array of merged declaration values.
  #   Returns empty array if input is nil or empty.
  #
  # Merge rules:
  # 1. Higher specificity wins
  # 2. !important declarations win over non-important
  # 3. Later declarations with same specificity and importance win
  # 4. Shorthand properties are created from longhand when possible (e.g., margin-* -> margin)
  #
  # @example Merge rules from a stylesheet
  #   sheet = Cataract.parse_css(".test { color: red; } #test { color: blue; }")
  #   merged = Cataract.merge(sheet)
  #   # merged contains declarations with blue color (higher specificity)
  #
  # @example Merge rules with !important
  #   sheet = Cataract.parse_css(".test { color: red !important; } #test { color: blue; }")
  #   merged = Cataract.merge(sheet)
  #   # merged contains red color (!important wins despite lower specificity)
  #
  # @example Merge creates shorthand properties
  #   sheet = Cataract.parse_css(".test { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }")
  #   merged = Cataract.merge(sheet)
  #   # merged contains "margin: 10px" shorthand instead of four longhand properties
  def self.merge(rules)
    return [] if rules.nil? || rules.empty?

    # Accept both Stylesheet and Array for convenience
    input = if rules.is_a?(Stylesheet)
              # Pass hash structure directly to C - it will flatten efficiently
              rules.rule_groups
            elsif rules.is_a?(Enumerator)
              rules.to_a
            else
              rules
            end

    # Call C implementation for performance (handles both hash and array)
    Cataract.merge_rules(input)
  end
end
