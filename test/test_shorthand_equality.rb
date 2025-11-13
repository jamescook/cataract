# frozen_string_literal: true

# Tests for Rule/Declaration equality with shorthand properties
class TestShorthandEquality < Minitest::Test
  def test_shorthand_vs_longhand_declarations_not_equal
    # Declarations are still not equal (they're different objects)
    # But Rules will be equal after expansion
    shorthand = Cataract::Declaration.new('margin', '10px', false)
    longhand_top = Cataract::Declaration.new('margin-top', '10px', false)

    refute_equal shorthand, longhand_top
  end

  def test_shorthand_vs_longhand_rules_are_equal
    # Parse rule with shorthand
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    shorthand_rule = sheet1.rules.first

    # Parse rule with longhand
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')
    longhand_rule = sheet2.rules.first

    # These ARE semantically equivalent and should be equal after shorthand expansion
    assert_equal shorthand_rule, longhand_rule
  end

  def test_remove_rules_with_merged_rule_objects_works
    # This demonstrates that remove_rules! works correctly
    # even when rules have been merged (shorthand expansion)

    sheet = Cataract.parse_css(<<~CSS)
      .box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }
    CSS

    assert_equal 1, sheet.rules_count

    # Merge the stylesheet (this creates shorthand properties)
    merged = sheet.merge
    merged_rule = merged.rules.first

    # Remove using the merged rule object - should work now with shorthand-aware equality
    sheet.remove_rules!(merged_rule)

    # Equality now works correctly with shorthand expansion
    assert_equal 0, sheet.rules_count, 'Rule should be removed even after merge creates shorthand'
  end

  def test_remove_rules_by_selector_avoids_equality_issue
    # This shows that CSS string matching avoids the equality problem
    sheet = Cataract.parse_css(<<~CSS)
      .box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }
    CSS

    assert_equal 1, sheet.rules_count

    # Remove by selector (CSS string) - this works regardless of shorthand
    sheet.remove_rules!('.box { }')

    assert_equal 0, sheet.rules_count
  end
end
