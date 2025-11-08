# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Tests for the Cataract module-level API
# - Cataract.parse_css (wrapper for Stylesheet.parse)
# - Cataract.merge (rule merging with CSS cascade)
class TestCataract < Minitest::Test
  # ============================================================================
  # Cataract.parse_css - Module-level parsing wrapper
  # ============================================================================

  def test_parse_css_returns_stylesheet
    sheet = Cataract.parse_css('body { color: red; }')

    assert_instance_of Cataract::Stylesheet, sheet
    assert_equal 1, sheet.size
  end

  # ============================================================================
  # Cataract.merge - CSS cascade merging
  # ============================================================================

  # Helper to find declaration by property name
  def find_property(declarations, property_name)
    decl = declarations.find { |d| d.property == property_name }
    return nil unless decl

    decl.important ? "#{decl.value} !important" : decl.value
  end

  def test_merge_simple
    rules = Cataract.parse_css(<<~CSS)
      .test1 { color: black; }
      .test1 { margin: 0px; }
    CSS

    merged = rules.merge.rules.first.declarations

    assert_equal 'black', find_property(merged, 'color')
    assert_equal '0px', find_property(merged, 'margin')
  end

  def test_merge_same_property_later_wins
    rules = Cataract.parse_css(<<~CSS)
      .test { color: red; }
      .test { color: blue; }
    CSS

    merged = rules.merge.rules.first.declarations

    assert_equal 'blue', find_property(merged, 'color')
  end

  def test_merge_with_specificity
    rules = Cataract.parse_css(<<~CSS)
      .test { color: red; }
      #test { color: blue; }
    CSS

    merged = rules.merge.rules.first.declarations

    # ID selector (#test) has higher specificity, should win
    assert_equal 'blue', find_property(merged, 'color')
  end

  def test_merge_important_wins
    rules = Cataract.parse_css(<<~CSS)
      .test { color: red !important; }
      #test { color: blue; }
    CSS

    merged = rules.merge.rules.first.declarations

    # !important wins even with lower specificity
    assert_equal 'red !important', find_property(merged, 'color')
  end

  def test_merge_accepts_stylesheet
    sheet = Cataract.parse_css('.test { color: red; margin: 10px; }')
    merged = sheet.merge.rules.first.declarations

    assert_equal 'red', find_property(merged, 'color')
    assert_equal '10px', find_property(merged, 'margin')
  end

  # test_merge_accepts_array and test_merge_empty_returns_empty_array removed
  # These tested the old module-level Cataract.merge API which has been replaced
  # with the instance method Stylesheet#merge in the new parser

  def test_merge_creates_shorthand_properties
    rules = Cataract.parse_css(<<~CSS)
      .test { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }
    CSS

    merged = rules.merge.rules.first.declarations

    # Should create margin shorthand
    assert_equal '10px', find_property(merged, 'margin')
    # Longhand properties should not be present
    assert_nil find_property(merged, 'margin-top')
  end

  def test_merge_with_mixed_shorthand_longhand
    # Per W3C cascade rules, when you have:
    #   margin: 5px;        <- sets all four sides to 5px
    #   margin-top: 10px;   <- overrides just the top
    # The final computed values are: top=10px, right=5px, bottom=5px, left=5px
    #
    # Cataract.merge optimizes this by creating a shorthand: "10px 5px 5px"
    # This is the CSS 3-value syntax: top, right/left, bottom (right and left collapsed)
    rules = Cataract.parse_css(<<~CSS)
      .test { margin: 5px; margin-top: 10px; }
    CSS

    merged = rules.merge.rules.first.declarations

    assert_equal '10px 5px 5px', find_property(merged, 'margin')
  end
end
