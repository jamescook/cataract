# frozen_string_literal: true

module Cataract
  # Represents a CSS at-rule like @keyframes, @font-face, @supports, etc.
  #
  # AtRule is a C struct defined as: `Struct.new(:id, :selector, :content, :specificity)`
  #
  # At-rules define CSS resources or control structures rather than selecting elements.
  # Unlike regular rules, they don't have CSS specificity and are filtered out when
  # using `select(&:selector?)`.
  #
  # The content field varies by at-rule type:
  # - `@keyframes`: Array of Rule (keyframe percentage blocks like "0%", "100%")
  # - `@font-face`: Array of Declaration (font property declarations)
  # - `@supports`: Array of Rule (conditional rules)
  #
  # @example Parse @keyframes
  #   css = "@keyframes fade { 0% { opacity: 0; } 100% { opacity: 1; } }"
  #   sheet = Cataract.parse_css(css)
  #   at_rule = sheet.rules.first
  #   at_rule.selector #=> "@keyframes fade"
  #   at_rule.content #=> [Rule, Rule] (two keyframe blocks)
  #
  # @example Parse @font-face
  #   css = "@font-face { font-family: 'MyFont'; src: url('font.woff'); }"
  #   sheet = Cataract.parse_css(css)
  #   at_rule = sheet.rules.first
  #   at_rule.selector #=> "@font-face"
  #   at_rule.content #=> [Declaration, Declaration]
  #
  # @attr [Integer] id The at-rule's position in the stylesheet (0-indexed)
  # @attr [String] selector The at-rule identifier (e.g., "@keyframes fade", "@font-face")
  # @attr [Array<Rule>, Array<Declaration>] content Nested rules or declarations
  # @attr [nil] specificity Always nil for at-rules (they don't have CSS specificity)
  class AtRule
    # Check if this is a selector-based rule (vs an at-rule like @keyframes).
    #
    # @return [Boolean] Always returns false for AtRule objects
    def selector?
      false
    end

    # Check if this is an at-rule.
    #
    # @return [Boolean] Always returns true for AtRule objects
    def at_rule?
      true
    end

    # Check if this is a specific at-rule type.
    #
    # @param type [Symbol] At-rule type (e.g., :keyframes, :font_face)
    # @return [Boolean] true if at-rule matches the type
    #
    # @example Check for @keyframes
    #   at_rule.at_rule_type?(:keyframes) #=> true if selector is "@keyframes ..."
    #
    # @example Check for @font-face
    #   at_rule.at_rule_type?(:font_face) #=> true if selector is "@font-face"
    def at_rule_type?(type)
      type_str = "@#{type.to_s.tr('_', '-')}"
      selector.start_with?(type_str)
    end

    # Check if this at-rule has a declaration with the specified property.
    #
    # @param _property [String] CSS property name
    # @param _value [String, nil] Optional value to match
    # @return [Boolean] Always returns false for AtRule objects
    def has_property?(_property, _value = nil)
      false
    end

    # Check if this at-rule has any !important declarations.
    #
    # @param _property [String, nil] Optional property name
    # @return [Boolean] Always returns false for AtRule objects
    def has_important?(_property = nil)
      false
    end

    # Compare at-rules by their attributes rather than object identity.
    #
    # Two at-rules are equal if they have the same id, selector, and content.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if at-rules have same attributes
    def ==(other)
      return false unless other.is_a?(AtRule)

      id == other.id &&
        selector == other.selector &&
        content == other.content
    end
    alias eql? ==
  end
end
