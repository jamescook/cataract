# frozen_string_literal: true

require_relative '../test_helper'

# Tests for media query list serialization (to_s)
#
# When parsing "@media screen, print { body { color: red; } }", we should
# serialize it back as a single grouped @media block, not as separate blocks:
#   @media screen, print { body { color: red; } }
#
# NOT:
#   @media screen { body { color: red; } }
#   @media print { body { color: red; } }
class TestMediaQueryListSerialization < Minitest::Test
  # ============================================================================
  # Basic media query list serialization
  # ============================================================================

  def test_simple_media_query_list_groups_on_serialization
    css = '@media screen, print { body { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # Should serialize back as grouped list
    expected = "@media screen, print {\nbody { color: red; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  def test_media_query_list_preserves_original_order
    css = '@media print, screen, handheld { body { margin: 0; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # Should preserve original order, not alphabetize
    expected = "@media print, screen, handheld {\nbody { margin: 0; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  def test_multiple_media_query_lists_serialize_correctly
    css = '@media screen, print { h1 { color: red; } } @media handheld, tv { p { color: blue; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = "@media screen, print {\nh1 { color: red; }\n}\n@media handheld, tv {\np { color: blue; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  # ============================================================================
  # Single media queries (no grouping)
  # ============================================================================

  def test_single_media_query_unchanged
    css = '@media screen { body { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # Single media queries should remain as-is
    expected = "@media screen {\nbody { color: red; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  def test_mixed_single_and_grouped_media_queries
    css = '@media screen { h1 { font-size: 24px; } } @media print, handheld { h2 { color: red; } } @media tv { p { margin: 0; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = "@media screen {\nh1 { font-size: 24px; }\n}\n@media print, handheld {\nh2 { color: red; }\n}\n@media tv {\np { margin: 0; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  # ============================================================================
  # Complex media queries with conditions
  # ============================================================================

  def test_media_query_list_with_conditions
    css = '@media screen and (min-width: 768px), print and (color) { body { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = "@media screen and (min-width: 768px), print and (color) {\nbody { color: red; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  def test_mixed_simple_and_complex_media_queries_in_list
    css = '@media screen, print and (color) { body { margin: 0; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = "@media screen, print and (color) {\nbody { margin: 0; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  # ============================================================================
  # Multiple rules within media query list
  # ============================================================================

  def test_media_query_list_with_multiple_rules
    css = '@media screen, print { h1 { color: red; } p { margin: 0; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = "@media screen, print {\nh1 { color: red; }\np { margin: 0; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  def test_media_query_list_with_selector_lists
    css = '@media screen, print { h1, h2 { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # Both selector list AND media query list should be preserved
    expected = "@media screen, print {\nh1, h2 { color: red; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  # ============================================================================
  # Whitespace handling
  # ============================================================================

  def test_media_query_list_normalizes_whitespace
    # Input has inconsistent spacing
    css = '@media screen,print  ,  handheld{ body { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # Output should normalize to single space after comma
    expected = "@media screen, print, handheld {\nbody { color: red; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  def test_media_query_list_with_newlines_normalizes
    css = "@media screen,\nprint,\nhandheld { body { color: red; } }"
    sheet = Cataract::Stylesheet.parse(css)

    # Newlines should be normalized to comma-space
    expected = "@media screen, print, handheld {\nbody { color: red; }\n}\n"

    assert_equal expected, sheet.to_s
  end

  # ============================================================================
  # Round-trip tests
  # ============================================================================

  def test_media_query_list_round_trip
    css = '@media screen, print, handheld { body { color: red; } }'
    sheet = Cataract::Stylesheet.parse(css)
    serialized = sheet.to_s

    # Parse the serialized output
    sheet2 = Cataract::Stylesheet.parse(serialized)

    # Should serialize identically
    assert_equal serialized, sheet2.to_s
  end

  def test_complex_stylesheet_with_media_query_lists_round_trip
    css = <<~CSS
      body { color: black; }
      @media screen, print { h1 { color: red; } }
      @media handheld { p { margin: 0; } }
      @media tv, projection { a:hover { text-decoration: underline; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    serialized = sheet.to_s
    sheet2 = Cataract::Stylesheet.parse(serialized)

    assert_equal serialized, sheet2.to_s
  end

  # ============================================================================
  # Media query filtering with to_s(media: ...)
  # ============================================================================

  def test_to_s_with_media_filter_preserves_list_when_applicable
    css = '@media screen, print { body { color: red; } } @media handheld { p { margin: 0; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # When filtering to :screen, should only output the screen rule
    # But since original was "screen, print", we might serialize as just "@media screen"
    # This is acceptable - we only preserve the list when ALL members are included
    output = sheet.to_s(media: :screen)

    # Should contain screen rule but NOT handheld
    assert_match(/@media screen/, output)
    assert_match(/body \{ color: red; \}/, output)
    refute_match(/handheld/, output)
    refute_match(/p \{ margin: 0; \}/, output)
  end

  def test_to_s_with_multiple_media_filter_preserves_list
    css = '@media screen, print { body { color: red; } } @media handheld { p { margin: 0; } }'
    sheet = Cataract::Stylesheet.parse(css)

    # When filtering to both [:screen, :print], should preserve the grouped list
    output = sheet.to_s(media: %i[screen print])

    expected = "@media screen, print {\nbody { color: red; }\n}\n"

    assert_equal expected, output
  end
end
