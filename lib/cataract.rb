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

  private

  # TODO: Remove this if no longer needed
  # Expand shorthand properties into longhand
  # Returns a new array of Declarations::Value with expanded properties
  def self.expand_shorthand_declarations(declarations)
    expanded = []

    declarations.each do |decl|
      property = decl.property.downcase
      value = decl.value
      is_important = decl.important

      # Expand shorthand properties using C extension
      expanded_props = case property
                       when 'background'
                         Cataract.expand_background(value)
                       when 'margin'
                         Cataract.expand_margin(value)
                       when 'padding'
                         Cataract.expand_padding(value)
                       when 'border'
                         Cataract.expand_border(value)
                       when 'border-color'
                         Cataract.expand_border_color(value)
                       when 'border-style'
                         Cataract.expand_border_style(value)
                       when 'border-width'
                         Cataract.expand_border_width(value)
                       when 'border-top'
                         Cataract.expand_border_side(value, 'top')
                       when 'border-right'
                         Cataract.expand_border_side(value, 'right')
                       when 'border-bottom'
                         Cataract.expand_border_side(value, 'bottom')
                       when 'border-left'
                         Cataract.expand_border_side(value, 'left')
                       when 'font'
                         Cataract.expand_font(value)
                       when 'list-style'
                         Cataract.expand_list_style(value)
                       else
                         # Not a shorthand property - keep as-is
                         nil
                       end

      if expanded_props
        # Shorthand was expanded - create new declarations preserving !important flag
        expanded_props.each do |prop, val|
          expanded << Declarations::Value.new(
            property: prop,
            value: val,
            important: is_important
          )
        end
      else
        # Not a shorthand - keep original
        expanded << decl
      end
    end

    expanded
  end
end
