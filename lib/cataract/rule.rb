# frozen_string_literal: true

module Cataract
  # Represents a CSS rule with a selector and declarations.
  #
  # Rule is a C struct defined as: `Struct.new(:id, :selector, :declarations, :specificity)`
  #
  # Rules are created by the parser and stored in Stylesheet objects. Each rule
  # contains:
  # - An ID (position in the stylesheet)
  # - A CSS selector string
  # - An array of Declaration structs
  # - A specificity value (calculated lazily)
  #
  # Media query information is stored separately in Stylesheet's media_index.
  #
  # @example Access rule properties
  #   sheet = Cataract.parse_css("body { color: red; font-size: 14px; }")
  #   rule = sheet.rules.first
  #   rule.selector #=> "body"
  #   rule.specificity #=> 1
  #   rule.declarations.length #=> 2
  #
  # @attr [Integer] id The rule's position in the stylesheet (0-indexed)
  # @attr [String] selector The CSS selector (e.g., "body", ".class", "#id")
  # @attr [Array<Declaration>] declarations Array of CSS property declarations
  # @attr [Integer, nil] specificity CSS specificity value (calculated lazily)
  class Rule
    # Silence warning about method redefinition. We redefine below to lazily calculate
    # specificity
    undef_method :specificity if method_defined?(:specificity)

    # Get the CSS specificity value for this rule's selector.
    #
    # Specificity is calculated lazily on first access and then cached.
    # The calculation follows the CSS specification:
    # - Inline styles: not applicable to parsed stylesheets
    # - IDs: count of #id selectors
    # - Classes/attributes/pseudo-classes: count of .class, [attr], :pseudo
    # - Elements/pseudo-elements: count of element, ::pseudo
    #
    # @return [Integer] CSS specificity value
    #
    # @example Get specificity
    #   rule = Cataract.parse_css("#header .nav a").rules.first
    #   rule.specificity #=> 111 (1 ID + 1 class + 1 element)
    def specificity
      return self[:specificity] unless self[:specificity].nil?

      # Calculate and cache
      calculated = Cataract.calculate_specificity(selector)
      self[:specificity] = calculated
      calculated
    end

    # Check if this rule type supports each_selector iteration.
    #
    # Regular CSS rules support iteration, but at-rules (like @keyframes, @font-face)
    # do not since they define resources rather than selecting elements.
    #
    # @return [Boolean] Always returns true for Rule objects
    # @api private
    def supports_each_selector?
      true
    end
  end
end
