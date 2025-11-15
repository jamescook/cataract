# frozen_string_literal: true

require_relative '../test_helper'

# Edge case tests for CSS parser
class TestEdgeCases < Minitest::Test
  # ============================================================================
  # Whitespace tolerance
  # ============================================================================

  def test_selector_list_without_space_before_brace
    # Browsers accept this, so we should too
    css = 'h1,h2,h3{ color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Should parse all 3 selectors
    assert_equal 3, sheet.rules.size, 'Should parse all 3 selectors even without space before {'

    # Check selectors are correct
    assert_equal 'h1', sheet.rules[0].selector
    assert_equal 'h2', sheet.rules[1].selector
    assert_equal 'h3', sheet.rules[2].selector

    # Check declarations
    sheet.rules.each do |rule|
      assert_equal 1, rule.declarations.size
      assert_equal 'color', rule.declarations[0].property
      assert_equal 'red', rule.declarations[0].value
    end
  end

  def test_single_selector_without_space_before_brace
    css = 'h1{ color: blue; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 1, sheet.rules.size
    assert_equal 'h1', sheet.rules[0].selector
    assert_equal 'color', sheet.rules[0].declarations[0].property
    assert_equal 'blue', sheet.rules[0].declarations[0].value
  end

  def test_selector_list_with_inconsistent_spacing
    # Mix of spaces and no spaces
    css = 'h1,h2  ,  h3{ color: green; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 3, sheet.rules.size
    assert_equal 'h1', sheet.rules[0].selector
    assert_equal 'h2', sheet.rules[1].selector
    assert_equal 'h3', sheet.rules[2].selector
  end

  def test_selector_list_no_space_after_comma
    css = 'h1,h2,h3 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 3, sheet.rules.size
  end

  def test_class_selectors_no_space_before_brace
    css = '.test1,.test2,.test3{ background: yellow; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 3, sheet.rules.size
    assert_equal '.test1', sheet.rules[0].selector
    assert_equal '.test2', sheet.rules[1].selector
    assert_equal '.test3', sheet.rules[2].selector
  end
end
