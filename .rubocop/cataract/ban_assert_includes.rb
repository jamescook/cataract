# frozen_string_literal: true

module RuboCop
  module Cop
    module Cataract
      # Bans the use of `assert_includes` and `assert_match` in favor of structural assertions.
      #
      # Both `assert_includes` and `assert_match` check substrings/patterns in strings,
      # which is too loose and can hide parser/serializer bugs.
      #
      # @example Bad - can hide regressions
      #   # Parser has a bug and drops the second rule:
      #   parsed = parse('body { color: red; } body { color: blue; }').to_s
      #   # => 'body { color: red; }'
      #   assert_includes parsed, 'body'  # PASSES but output is wrong!
      #   assert_match(/body/, parsed)    # PASSES but output is wrong!
      #
      # @example Good - use structural assertions
      #   # For collections:
      #   assert_member([:screen, :print], :screen)
      #   assert_member(stylesheet.selectors, 'body')
      #
      #   # For CSS verification:
      #   assert_equal expected_css, actual_css
      #   assert_has_selector('body', stylesheet)
      #   assert_has_property({ color: 'red' }, rule)
      #   assert_selector_count(2, stylesheet)
      #
      class BanAssertIncludes < Base
        MSG = 'Use structural assertions (assert_has_selector, assert_has_property, etc.) or ' \
              'assert_member for collections. String pattern matching with `assert_includes` and ' \
              '`assert_match` is banned because it is too loose and can hide parser/serializer regressions.'

        RESTRICT_ON_SEND = [:assert_includes, :assert_match].freeze

        def on_send(node)
          add_offense(node)
        end
      end
    end
  end
end
