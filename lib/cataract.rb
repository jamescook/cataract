require_relative 'cataract/version'
require 'cataract/cataract'  # Load C extension first (defines Rule struct)
require_relative 'cataract/rule'  # Add Ruby methods to Rule
require_relative 'cataract/stylesheet'
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/parser'

module Cataract
  # Wrap parse_css to return Stylesheet instead of raw array
  class << self
    alias_method :parse_css_internal, :parse_css

    def parse_css(css)
      rules = parse_css_internal(css)
      Stylesheet.new(rules)
    end
  end

  def self.parse(css_string, options = {})
    parser = Parser.new(options)
    parser.parse(css_string)
    parser
  end

  # Merge multiple CSS rules according to CSS cascade rules
  #
  # @param rules [Array<Struct>, Stylesheet] Array of Rule structs or Stylesheet
  # @return [Array<Declarations::Value>] Merged declarations
  #
  # Rules are merged according to CSS cascade:
  # 1. Higher specificity wins
  # 2. !important declarations win over non-important
  # 3. Later declarations with same specificity win
  # 4. Shorthand properties are created from longhand (e.g., margin-* -> margin)
  #
  # Example:
  #   sheet = Cataract.parse_css(".test { color: red; } #test { color: blue; }")
  #   merged = Cataract.merge(sheet)  # Can pass Stylesheet directly
  def self.merge(rules)
    return [] if rules.nil? || rules.empty?

    # Accept both Stylesheet and Array for convenience
    rules_array = rules.is_a?(Stylesheet) ? rules.rules : rules

    # Call C implementation for performance
    Cataract.merge_rules(rules_array)
  end
end
