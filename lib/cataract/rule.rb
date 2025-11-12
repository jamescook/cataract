# frozen_string_literal: true

module Cataract
  # Rules are created by the parser and stored in Stylesheet objects. Each rule contains:
  # - An ID (position in the stylesheet)
  # - A CSS selector string
  # - An array of Declaration structs
  # - A specificity value (calculated lazily)
  # - Parent rule ID for nested rules (nil if top-level)
  # - Nesting style (0=implicit, 1=explicit, nil=not nested)
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
  # @attr [Integer, nil] parent_rule_id Parent rule ID for nested rules
  # @attr [Integer, nil] nesting_style 0=implicit, 1=explicit, nil=not nested
  Rule = Struct.new(
    :id,
    :selector,
    :declarations,
    :specificity,
    :parent_rule_id,
    :nesting_style
  )

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

    # Check if this is a selector-based rule (vs an at-rule like @keyframes).
    #
    # @return [Boolean] Always returns true for Rule objects
    def selector?
      true
    end

    # Check if this is an at-rule.
    #
    # @return [Boolean] Always returns false for Rule objects
    def at_rule?
      false
    end

    # Check if this is a specific at-rule type.
    #
    # @param _type [Symbol] At-rule type (e.g., :keyframes, :font_face)
    # @return [Boolean] Always returns false for Rule objects
    def at_rule_type?(_type)
      false
    end

    # Check if this rule has a declaration with the specified property and optional value.
    #
    # @param property [String] CSS property name to match
    # @param value [String, nil] Optional value to match
    # @return [Boolean] true if rule has matching declaration
    #
    # @example Check for color property
    #   rule.has_property?('color') #=> true
    #
    # @example Check for specific property value
    #   rule.has_property?('color', 'red') #=> true
    def has_property?(property, value = nil)
      declarations.any? do |decl|
        property_matches = decl.property == property
        value_matches = value.nil? || decl.value == value
        property_matches && value_matches
      end
    end

    # Check if this rule has any !important declarations, optionally for a specific property.
    #
    # @param property [String, nil] Optional property name to match
    # @return [Boolean] true if rule has matching !important declaration
    #
    # @example Check for any !important
    #   rule.has_important? #=> true
    #
    # @example Check for color !important
    #   rule.has_important?('color') #=> true
    def has_important?(property = nil)
      if property
        declarations.any? { |d| d.property == property && d.important }
      else
        declarations.any?(&:important)
      end
    end

    # Compare rules for logical equality based on CSS semantics.
    #
    # Two rules are equal if they have the same selector and declarations.
    # Shorthand properties are expanded before comparison, so
    # `margin: 10px` equals `margin-top: 10px; margin-right: 10px; ...`
    #
    # Internal implementation details (id, specificity) are not considered
    # since they don't affect the CSS semantics.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if rules have same selector and declarations
    def ==(other)
      return false unless other.is_a?(Rule)
      return false unless selector == other.selector

      # Expand and normalize declarations for comparison
      # Cache expansion on self, compute fresh for other
      self_expanded = @_expanded_declarations ||= begin
        expanded = declarations.flat_map { |decl| Cataract._expand_shorthand(decl) }
        expanded.sort_by! { |d| [d.property, d.value, d.important ? 1 : 0] }
        expanded
      end

      # Check if other already has expanded cache
      if other.instance_variable_defined?(:@_expanded_declarations) && !other.instance_variable_get(:@_expanded_declarations).nil?
        other_expanded = other.instance_variable_get(:@_expanded_declarations)
      else
        # Expand other without caching
        other_expanded = other.declarations.flat_map { |decl| Cataract._expand_shorthand(decl) }
        other_expanded.sort_by! { |d| [d.property, d.value, d.important ? 1 : 0] }
      end

      self_expanded == other_expanded
    end
    alias eql? ==
  end
end
