require_relative 'cataract/version'
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/parser'
require 'cataract/cataract'

module Cataract
  def self.parse(css_string, options = {})
    parser = Parser.new(options)
    parser.parse(css_string)
    parser
  end

  # Merge multiple CSS rules according to CSS cascade rules
  #
  # @param rules [Array<Hash>] Array of parsed rules from parse_css
  # @return [Hash] Merged declarations as property => value hash
  #
  # Rules are merged according to CSS cascade:
  # 1. Higher specificity wins
  # 2. !important declarations win over non-important
  # 3. Later declarations with same specificity win
  # 4. Shorthand properties are created from longhand (e.g., margin-* -> margin)
  #
  # Example:
  #   rules = Cataract.parse_css(".test { color: red; } #test { color: blue; }")
  #   merged = Cataract.merge(rules)
  #   merged['color'] # => "blue"
  def self.merge(rules)
    return [] if rules.nil? || rules.empty?

    # Call C implementation for performance
    Cataract.merge_rules(rules)
  end
end
