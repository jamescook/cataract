#!/usr/bin/env ruby
# frozen_string_literal: true

# Test creating shorthand properties from longhand through flatten operations
# When all longhand properties for a shorthand are present, flatten should
# automatically create the shorthand property.
class TestShorthandCreation < Minitest::Test
  # Helper to parse CSS with longhand properties and flatten to trigger shorthand creation
  def parse_and_flatten(css)
    sheet = Cataract.parse_css(css)
    flattened = sheet.flatten

    # The flattened stylesheet should have exactly one rule with all declarations
    Cataract::Declarations.new(flattened.rules.first.declarations)
  end

  # ===========================================================================
  # Margin Shorthand Creation
  # ===========================================================================

  def test_create_margin_all_same
    decls = parse_and_flatten('.test { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px }')

    # Should create shorthand when all sides are the same
    assert_equal '10px', decls['margin']
  end

  def test_create_margin_vertical_horizontal
    decls = parse_and_flatten('.test { margin-top: 10px; margin-right: 20px; margin-bottom: 10px; margin-left: 20px }')

    # Should create 2-value shorthand
    assert_equal '10px 20px', decls['margin']
  end

  def test_create_margin_top_horizontal_bottom
    decls = parse_and_flatten('.test { margin-top: 10px; margin-right: 20px; margin-bottom: 30px; margin-left: 20px }')

    # Should create 3-value shorthand
    assert_equal '10px 20px 30px', decls['margin']
  end

  def test_create_margin_all_different
    decls = parse_and_flatten('.test { margin-top: 10px; margin-right: 20px; margin-bottom: 30px; margin-left: 40px }')

    # Should create 4-value shorthand
    assert_equal '10px 20px 30px 40px', decls['margin']
  end

  def test_create_margin_missing_side
    decls = parse_and_flatten('.test { margin-top: 10px; margin-right: 20px; margin-bottom: 30px }')

    # Should NOT create shorthand if not all sides present - keeps longhands
    assert_nil decls['margin']
    assert_equal '10px', decls['margin-top']
    assert_equal '20px', decls['margin-right']
    assert_equal '30px', decls['margin-bottom']
  end

  # ===========================================================================
  # Padding Shorthand Creation
  # ===========================================================================

  def test_create_padding_all_same
    decls = parse_and_flatten('.test { padding-top: 5px; padding-right: 5px; padding-bottom: 5px; padding-left: 5px }')

    assert_equal '5px', decls['padding']
  end

  def test_create_padding_vertical_horizontal
    decls = parse_and_flatten('.test { padding-top: 10px; padding-right: 20px; padding-bottom: 10px; padding-left: 20px }')

    assert_equal '10px 20px', decls['padding']
  end

  # ===========================================================================
  # Border Shorthand Creation
  # ===========================================================================
  # Per W3C spec: border shorthand requires style, optionally width and color

  def test_create_border_width_all_same
    decls = parse_and_flatten('.test { border-top-width: 1px; border-right-width: 1px; border-bottom-width: 1px; border-left-width: 1px }')

    # Width-only creates border-width shorthand (border requires style)
    assert_equal '1px', decls['border-width']
    assert_nil decls['border']
  end

  def test_create_border_width_vertical_horizontal
    decls = parse_and_flatten('.test { border-top-width: 1px; border-right-width: 2px; border-bottom-width: 1px; border-left-width: 2px }')

    # When widths differ, creates border-width shorthand
    assert_equal '1px 2px', decls['border-width']
  end

  def test_create_border_style_all_same
    decls = parse_and_flatten('.test { border-top-style: solid; border-right-style: solid; border-bottom-style: solid; border-left-style: solid }')

    # Style-only can create full border shorthand
    assert_equal 'solid', decls['border']
  end

  def test_create_border_style_vertical_horizontal
    decls = parse_and_flatten('.test { border-top-style: solid; border-right-style: dashed; border-bottom-style: solid; border-left-style: dashed }')

    # When styles differ, creates border-style shorthand
    assert_equal 'solid dashed', decls['border-style']
  end

  def test_create_border_color_all_same
    decls = parse_and_flatten('.test { border-top-color: red; border-right-color: red; border-bottom-color: red; border-left-color: red }')

    # Color-only creates border-color shorthand (border requires style)
    assert_equal 'red', decls['border-color']
    assert_nil decls['border']
  end

  def test_create_border_color_vertical_horizontal
    decls = parse_and_flatten('.test { border-top-color: red; border-right-color: blue; border-bottom-color: red; border-left-color: blue }')

    # When colors differ, creates border-color shorthand
    assert_equal 'red blue', decls['border-color']
  end

  # ===========================================================================
  # Border Full Shorthand Creation
  # ===========================================================================

  def test_create_border_full
    # When all sides have same width, style, and color, should create border shorthand
    decls = parse_and_flatten('.test { border-top-width: 1px; border-top-style: solid; border-top-color: red; border-right-width: 1px; border-right-style: solid; border-right-color: red; border-bottom-width: 1px; border-bottom-style: solid; border-bottom-color: red; border-left-width: 1px; border-left-style: solid; border-left-color: red }')

    assert_equal '1px solid red', decls['border']
  end

  def test_create_border_partial
    # When sides differ, should create border-width/style/color shorthands but not full border
    decls = parse_and_flatten('.test { border-top-width: 1px; border-top-style: solid; border-top-color: red; border-right-width: 2px; border-right-style: dashed; border-right-color: blue; border-bottom-width: 1px; border-bottom-style: solid; border-bottom-color: red; border-left-width: 2px; border-left-style: dashed; border-left-color: blue }')

    # Should have individual shorthands but not full border
    assert_equal '1px 2px', decls['border-width']
    assert_equal 'solid dashed', decls['border-style']
    assert_equal 'red blue', decls['border-color']
    assert_nil decls['border']
  end

  # ===========================================================================
  # Background Shorthand Creation
  # ===========================================================================

  def test_create_background_color_only
    decls = parse_and_flatten('.test { background-color: white }')

    # Single background property doesn't create shorthand
    assert_equal 'white', decls['background-color']
    assert_nil decls['background']
  end

  def test_create_background_multiple_properties
    decls = parse_and_flatten('.test { background-color: red; background-image: url(img.png); background-repeat: no-repeat }')

    # Multiple background properties should create shorthand
    assert_equal 'red url(img.png) no-repeat', decls['background']
  end

  # ===========================================================================
  # Font Shorthand Creation
  # ===========================================================================

  def test_create_font_basic
    # Font shorthand requires at minimum: font-size and font-family
    decls = parse_and_flatten('.test { font-size: 12px; font-family: Arial }')

    assert_equal '12px Arial', decls['font']
  end

  def test_create_font_with_line_height
    decls = parse_and_flatten('.test { font-size: 14px; line-height: 1.5; font-family: Arial }')

    # Should create font shorthand with line-height
    assert_equal '14px/1.5 Arial', decls['font']
  end

  def test_create_font_with_style_weight
    decls = parse_and_flatten('.test { font-style: italic; font-weight: bold; font-size: 16px; font-family: Arial }')

    # Should include style and weight
    assert_equal 'italic bold 16px Arial', decls['font']
  end

  # ===========================================================================
  # List-Style Shorthand Creation
  # ===========================================================================

  def test_create_list_style_single
    decls = parse_and_flatten('.test { list-style-type: square }')

    # Single property doesn't create shorthand
    assert_equal 'square', decls['list-style-type']
    assert_nil decls['list-style']
  end

  def test_create_list_style_multiple
    decls = parse_and_flatten('.test { list-style-type: square; list-style-position: inside }')

    # Multiple properties should create shorthand
    assert_equal 'square inside', decls['list-style']
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  def test_important_prevents_shorthand_creation
    # If properties have different !important flags, cannot create shorthand
    decls = parse_and_flatten('.test { margin-top: 10px !important; margin-right: 10px; margin-bottom: 10px; margin-left: 10px }')

    # Should keep longhands when !important flags differ
    assert_nil decls['margin']
    assert_equal '10px !important', decls['margin-top']
    assert_equal '10px', decls['margin-right']
  end

  def test_all_important_creates_shorthand
    # If all have !important, can create shorthand with !important
    decls = parse_and_flatten('.test { margin-top: 10px !important; margin-right: 10px !important; margin-bottom: 10px !important; margin-left: 10px !important }')

    # Should create shorthand with !important
    assert_equal '10px !important', decls['margin']
  end
end
