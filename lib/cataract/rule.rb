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
  # @attr [Integer, nil] selector_list_id ID linking rules from same selector list (e.g., "h1, h2")
  # @attr [Integer, nil] media_query_id ID of the MediaQuery this rule belongs to (nil if not in media query)
  Rule = Struct.new(
    :id,
    :selector,
    :declarations,
    :specificity,
    :parent_rule_id,
    :nesting_style,
    :selector_list_id,
    :media_query_id
  )

  class Rule
    # Factory method for creating Rules with keyword arguments (for tests/readability).
    # C code and hot paths should use positional arguments directly via Rule.new.
    #
    # @param id [Integer] The rule's position in the stylesheet
    # @param selector [String] CSS selector
    # @param declarations [Array<Declaration>] Array of declarations
    # @param specificity [Integer, nil] Specificity value (nil to calculate lazily)
    # @param parent_rule_id [Integer, nil] Parent rule ID for nested rules
    # @param nesting_style [Integer, nil] Nesting style (0=implicit, 1=explicit, nil=not nested)
    # @param selector_list_id [Integer, nil] Selector list ID for grouping
    # @param media_query_id [Integer, nil] MediaQuery ID for rules in media queries
    # @return [Rule] New rule instance
    #
    # @example Create a rule with keyword arguments
    #   Rule.make(
    #     id: 0,
    #     selector: '.foo',
    #     declarations: [Declaration.new('color', 'red', false)],
    #     specificity: 10,
    #     parent_rule_id: nil,
    #     nesting_style: nil,
    #     selector_list_id: nil,
    #     media_query_id: nil
    #   )
    def self.make(id:, selector:, declarations:, specificity: nil, parent_rule_id: nil, nesting_style: nil, selector_list_id: nil, media_query_id: nil)
      new(id, selector, declarations, specificity, parent_rule_id, nesting_style, selector_list_id, media_query_id)
    end

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
    # @param prefix_match [Boolean] Whether to match by prefix (default: false)
    # @return [Boolean] true if rule has matching declaration
    #
    # @example Check for color property
    #   rule.has_property?('color') #=> true
    #
    # @example Check for specific property value
    #   rule.has_property?('color', 'red') #=> true
    #
    # @example Check for any margin-related property
    #   rule.has_property?('margin', prefix_match: true) #=> true if has margin, margin-top, etc.
    def has_property?(property, value = nil, prefix_match: false)
      declarations.any? do |decl|
        property_matches = if prefix_match
                             decl.property.start_with?(property)
                           else
                             decl.property == property
                           end
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
    # Can also compare against a CSS string, which is parsed and compared.
    #
    # @param other [Object] Object to compare with (Rule or String)
    # @return [Boolean] true if rules have same selector and declarations
    def ==(other)
      case other
      when Rule
        return false unless selector == other.selector

        expanded_declarations == other.expanded_declarations
      when String
        # Parse CSS string and compare to first rule
        parsed = Cataract.parse_css(other)
        return false unless parsed.rules.size == 1

        self == parsed.rules.first
      else
        false
      end
    end
    alias eql? ==

    # Generate hash code for this rule.
    #
    # Hash is based on selector and expanded declarations to match the
    # equality semantics. This allows rules to be used as Hash keys or
    # in Sets correctly.
    #
    # @return [Integer] hash code
    # rubocop:disable Naming/MemoizedInstanceVariableName
    def hash
      @_hash ||= [self.class, selector, expanded_declarations].hash
    end
    # rubocop:enable Naming/MemoizedInstanceVariableName

    protected

    # Get expanded and normalized declarations for this rule.
    #
    # Shorthands are expanded into their longhand equivalents and sorted
    # to enable semantic comparison. Result is cached.
    #
    # @return [Array<Declaration>] expanded declarations
    # rubocop:disable Naming/MemoizedInstanceVariableName
    def expanded_declarations
      @_expanded_declarations ||= begin
        expanded = declarations.flat_map { |decl| Cataract.expand_shorthand(decl) }
        expanded.sort_by! { |d| [d.property, d.value, d.important ? 1 : 0] }
        expanded
      end
    end
    # rubocop:enable Naming/MemoizedInstanceVariableName
  end
end
