# frozen_string_literal: true

require_relative '../test_helper'

# Tests for selector list serialization with to_formatted_s
#
# Similar to test_selector_list_serialization.rb but for formatted output.
# Rules with same selector_list_id and identical declarations should be grouped.
class TestSelectorListFormattedSerialization < Minitest::Test
  # ============================================================================
  # Basic selector list serialization
  # ============================================================================

  def test_simple_selector_list_groups_on_serialization
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1, h2, h3 {
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_selector_list_preserves_original_order
    css = '.alpha, .zeta, .beta { margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      .alpha, .zeta, .beta {
        margin: 0;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_multiple_selector_lists_serialize_correctly
    css = 'h1, h2 { color: red; } p, div { color: blue; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1, h2 {
        color: red;
      }

      p, div {
        color: blue;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Single selectors (no grouping)
  # ============================================================================

  def test_single_selector_unchanged
    css = 'h1 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1 {
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_mixed_single_and_grouped_selectors
    css = 'h1 { font-size: 24px; } h2, h3 { color: red; } p { margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1 {
        font-size: 24px;
      }

      h2, h3 {
        color: red;
      }

      p {
        margin: 0;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Diverged declarations (no grouping when different)
  # ============================================================================

  def test_diverged_declarations_prevent_grouping
    css = 'h1, h2 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Modify one rule's declarations
    sheet.rules[0].declarations << Cataract::Declaration.new('font-size', '24px', false)

    expected = <<~CSS
      h1 {
        color: red;
        font-size: 24px;
      }

      h2 {
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_all_diverged_rules_serialize_separately
    css = 'a, b, c { margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Modify each rule differently
    sheet.rules[0].declarations << Cataract::Declaration.new('color', 'red', false)
    sheet.rules[1].declarations << Cataract::Declaration.new('color', 'blue', false)
    sheet.rules[2].declarations << Cataract::Declaration.new('color', 'green', false)

    expected = <<~CSS
      a {
        margin: 0;
        color: red;
      }

      b {
        margin: 0;
        color: blue;
      }

      c {
        margin: 0;
        color: green;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_partial_grouping_when_some_match
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Modify only h3
    sheet.rules[2].declarations << Cataract::Declaration.new('font-size', '18px', false)

    expected = <<~CSS
      h1, h2 {
        color: red;
      }

      h3 {
        color: red;
        font-size: 18px;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Complex selectors
  # ============================================================================

  def test_compound_selectors_in_list
    css = 'div.foo, span.bar, a#baz { display: block; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      div.foo, span.bar, a#baz {
        display: block;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_descendant_selectors_in_list
    css = '.parent .child, .other .nested { padding: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      .parent .child, .other .nested {
        padding: 10px;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_pseudo_class_selectors_in_list
    css = 'a:hover, a:focus, a:active { text-decoration: underline; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      a:hover, a:focus, a:active {
        text-decoration: underline;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_attribute_selectors_in_list
    css = '[type="text"], [type="email"], [type="password"] { border: 1px solid gray; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      [type="text"], [type="email"], [type="password"] {
        border: 1px solid gray;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_child_combinator_selectors_in_list
    css = 'div > p, span > a { font-weight: bold; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      div > p, span > a {
        font-weight: bold;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_adjacent_sibling_combinator_in_list
    css = 'h1 + p, h2 + p { margin-top: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1 + p, h2 + p {
        margin-top: 0;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_general_sibling_combinator_in_list
    css = 'h1 ~ p, h2 ~ p { color: gray; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1 ~ p, h2 ~ p {
        color: gray;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Whitespace handling
  # ============================================================================

  def test_selector_list_with_newlines_normalizes
    css = "h1,\nh2,\nh3 { color: red; }"
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1, h2, h3 {
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Media queries
  # ============================================================================

  def test_selector_list_in_media_query
    css = '@media screen { h1, h2 { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      @media screen {
        h1, h2 {
          color: red;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_selector_list_across_media_boundaries_no_grouping
    css = '@media screen { h1 { color: red; } } @media print { h1 { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      @media screen {
        h1 {
          color: red;
        }
      }

      @media print {
        h1 {
          color: red;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Important declarations
  # ============================================================================

  def test_selector_list_with_important_declarations
    css = 'h1, h2 { color: red !important; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1, h2 {
        color: red !important;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_mixed_important_prevents_grouping
    css = 'h1, h2 { color: red !important; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Remove !important from one rule
    sheet.rules[1].declarations[0].important = false

    expected = <<~CSS
      h1 {
        color: red !important;
      }

      h2 {
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Multiple declarations
  # ============================================================================

  def test_selector_list_with_multiple_declarations
    css = 'h1, h2 { color: red; font-size: 24px; margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      h1, h2 {
        color: red;
        font-size: 24px;
        margin: 0;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_declaration_order_must_match_for_grouping
    css = 'h1, h2 { color: red; margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Reverse declaration order for h2
    sheet.rules[1].declarations.reverse!

    expected = <<~CSS
      h1 {
        color: red;
        margin: 0;
      }

      h2 {
        margin: 0;
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  # ============================================================================
  # Round-trip tests
  # ============================================================================

  def test_selector_list_round_trip
    css = <<~CSS
      h1, h2, h3 {
        color: red;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    serialized = sheet.to_formatted_s

    # Parse the serialized output
    sheet2 = Cataract::Stylesheet.parse(serialized)

    # Should have same number of rules
    assert_equal sheet.rules.size, sheet2.rules.size

    # Should serialize identically
    assert_equal serialized, sheet2.to_formatted_s
  end

  def test_complex_stylesheet_round_trip
    css = <<~CSS
      h1, h2 {
        color: red;
      }

      .foo {
        margin: 0;
      }

      p, div, span {
        padding: 10px;
      }

      a:hover, a:focus {
        text-decoration: underline;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    serialized = sheet.to_formatted_s
    sheet2 = Cataract::Stylesheet.parse(serialized)

    assert_equal serialized, sheet2.to_formatted_s
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  def test_empty_selector_list_not_serialized
    css = 'h1, h2 { color: red; } p { margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Remove first two rules (the h1, h2 group)
    sheet.instance_variable_get(:@rules).shift(2)

    expected = <<~CSS
      p {
        margin: 0;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_single_rule_from_selector_list_no_grouping
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Remove h2 and h3
    sheet.instance_variable_get(:@rules).delete_at(2)
    sheet.instance_variable_get(:@rules).delete_at(1)

    expected = <<~CSS
      h1 {
        color: red;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_very_long_selector_list
    selectors = (1..20).map { |i| ".class-#{i}" }.join(', ')
    css = "#{selectors} { display: block; }"
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      #{selectors} {
        display: block;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end
end
