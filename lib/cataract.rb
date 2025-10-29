require_relative 'cataract/version'
require_relative 'cataract/cataract'  # Load C extension first (defines Rule struct)
require_relative 'cataract/rule'  # Add Ruby methods to Rule
require_relative 'cataract/stylesheet'
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/parser'

module Cataract
  # Wrap parse_css to return Stylesheet instead of raw hash
  class << self
    alias_method :parse_css_internal, :parse_css

    def parse_css(css)
      result = parse_css_internal(css)
      # parse_css_internal always returns {rules: [...], charset: "UTF-8" | nil}
      Stylesheet.new(result[:rules], result[:charset])
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
    input = if rules.is_a?(Stylesheet)
      # Pass hash structure directly to C - it will flatten efficiently
      rules.instance_variable_get(:@rule_groups)
    elsif rules.is_a?(Enumerator)
      rules.to_a
    else
      rules
    end

    # Call C implementation for performance (handles both hash and array)
    Cataract.merge_rules(input)
  end
end
