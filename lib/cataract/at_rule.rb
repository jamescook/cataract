# frozen_string_literal: true

module Cataract
  # Represents a CSS at-rule like @keyframes, @font-face, @supports, etc.
  #
  # AtRule is a C struct defined as: `Struct.new(:id, :selector, :content, :specificity)`
  #
  # At-rules define CSS resources or control structures rather than selecting elements.
  # Unlike regular rules, they don't have CSS specificity and can't be iterated with
  # `each_selector`.
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
    # Check if this rule type supports each_selector iteration.
    #
    # At-rules define resources or conditions rather than selecting elements,
    # so they don't participate in selector iteration.
    #
    # @return [Boolean] Always returns false for AtRule objects
    # @api private
    def supports_each_selector?
      false
    end
  end
end
