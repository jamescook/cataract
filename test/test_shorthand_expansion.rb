# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Test CSS shorthand property expansion
# Based on css_parser gem's shorthand expansion behavior
class TestShorthandExpansion < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # ===========================================================================
  # Margin/Padding Shorthand (Dimensions)
  # ===========================================================================

  def test_margin_four_values
    result = Cataract.expand_margin('1px 2px 3px 4px')

    assert_equal '1px', result['margin-top']
    assert_equal '2px', result['margin-right']
    assert_equal '3px', result['margin-bottom']
    assert_equal '4px', result['margin-left']
  end

  def test_margin_three_values
    result = Cataract.expand_margin('1px 2px 3px')

    assert_equal '1px', result['margin-top']
    assert_equal '2px', result['margin-right']
    assert_equal '3px', result['margin-bottom']
    assert_equal '2px', result['margin-left'] # mirrors right
  end

  def test_margin_two_values
    result = Cataract.expand_margin('1px 2px')

    assert_equal '1px', result['margin-top']
    assert_equal '2px', result['margin-right']
    assert_equal '1px', result['margin-bottom']  # mirrors top
    assert_equal '2px', result['margin-left']    # mirrors right
  end

  def test_margin_one_value
    result = Cataract.expand_margin('10px')

    assert_equal '10px', result['margin-top']
    assert_equal '10px', result['margin-right']
    assert_equal '10px', result['margin-bottom']
    assert_equal '10px', result['margin-left']
  end

  def test_margin_with_calc
    result = Cataract.expand_margin('10px calc(100% - 20px)')

    assert_equal '10px', result['margin-top']
    assert_equal 'calc(100% - 20px)', result['margin-right']
    assert_equal '10px', result['margin-bottom']
    assert_equal 'calc(100% - 20px)', result['margin-left']
  end

  def test_padding_four_values
    result = Cataract.expand_padding('5px 10px 15px 20px')

    assert_equal '5px', result['padding-top']
    assert_equal '10px', result['padding-right']
    assert_equal '15px', result['padding-bottom']
    assert_equal '20px', result['padding-left']
  end

  def test_padding_two_values
    result = Cataract.expand_padding('5px 10px')

    assert_equal '5px', result['padding-top']
    assert_equal '10px', result['padding-right']
    assert_equal '5px', result['padding-bottom']
    assert_equal '10px', result['padding-left']
  end

  def test_padding_one_value
    result = Cataract.expand_padding('8px')

    assert_equal '8px', result['padding-top']
    assert_equal '8px', result['padding-right']
    assert_equal '8px', result['padding-bottom']
    assert_equal '8px', result['padding-left']
  end

  # ===========================================================================
  # Border Shorthand
  # ===========================================================================

  def test_border_shorthand
    result = Cataract.expand_border('1px solid red')

    # Should expand to all sides
    assert_equal '1px', result['border-top-width']
    assert_equal 'solid', result['border-top-style']
    assert_equal 'red', result['border-top-color']
    assert_equal '1px', result['border-right-width']
    assert_equal 'solid', result['border-right-style']
    assert_equal 'red', result['border-right-color']
    assert_equal '1px', result['border-bottom-width']
    assert_equal 'solid', result['border-bottom-style']
    assert_equal 'red', result['border-bottom-color']
    assert_equal '1px', result['border-left-width']
    assert_equal 'solid', result['border-left-style']
    assert_equal 'red', result['border-left-color']
  end

  def test_border_shorthand_with_none
    result = Cataract.expand_border('none')

    assert_equal 'none', result['border-top-style']
    assert_equal 'none', result['border-right-style']
    assert_equal 'none', result['border-bottom-style']
    assert_equal 'none', result['border-left-style']
  end

  def test_border_side_shorthand
    result = Cataract.expand_border_side('top', '2px dashed blue')

    assert_equal '2px', result['border-top-width']
    assert_equal 'dashed', result['border-top-style']
    assert_equal 'blue', result['border-top-color']
  end

  def test_border_color_shorthand
    result = Cataract.expand_border_color('red green blue yellow')

    assert_equal 'red', result['border-top-color']
    assert_equal 'green', result['border-right-color']
    assert_equal 'blue', result['border-bottom-color']
    assert_equal 'yellow', result['border-left-color']
  end

  def test_border_width_shorthand
    result = Cataract.expand_border_width('1px 2px 3px 4px')

    assert_equal '1px', result['border-top-width']
    assert_equal '2px', result['border-right-width']
    assert_equal '3px', result['border-bottom-width']
    assert_equal '4px', result['border-left-width']
  end

  def test_border_style_shorthand
    result = Cataract.expand_border_style('solid dashed')

    assert_equal 'solid', result['border-top-style']
    assert_equal 'dashed', result['border-right-style']
    assert_equal 'solid', result['border-bottom-style']
    assert_equal 'dashed', result['border-left-style']
  end

  # ===========================================================================
  # Background Shorthand
  # ===========================================================================

  def test_background_shorthand_simple
    result = Cataract.expand_background('white')

    assert_equal 'white', result['background-color']
  end

  def test_background_shorthand_complex
    result = Cataract.expand_background('url(img.png) no-repeat center / cover')

    assert_equal 'url(img.png)', result['background-image']
    assert_equal 'no-repeat', result['background-repeat']
    assert_equal 'center', result['background-position']
    assert_equal 'cover', result['background-size']
  end

  # ===========================================================================
  # Font Shorthand
  # ===========================================================================

  def test_font_shorthand_simple
    result = Cataract.expand_font('12px Arial')

    assert_equal '12px', result['font-size']
    assert_equal 'Arial', result['font-family']
  end

  def test_font_shorthand_with_line_height
    result = Cataract.expand_font("bold 14px/1.5 'Helvetica Neue', sans-serif")

    assert_equal 'bold', result['font-weight']
    assert_equal '14px', result['font-size']
    assert_equal '1.5', result['line-height']
    assert_equal "'Helvetica Neue', sans-serif", result['font-family']
  end

  # ===========================================================================
  # List-style Shorthand
  # ===========================================================================

  def test_list_style_shorthand
    result = Cataract.expand_list_style('square inside')

    assert_equal 'square', result['list-style-type']
    assert_equal 'inside', result['list-style-position']
  end

  # ===========================================================================
  # Security / Input Validation
  # ===========================================================================

  def test_split_value_rejects_huge_strings
    huge_string = 'a' * 100_000
    assert_raises(ArgumentError) do
      Cataract.split_value(huge_string)
    end
  end

  def test_expand_border_side_validates_side
    assert_raises(ArgumentError) do
      Cataract.expand_border_side('invalid', '1px solid red')
    end
  end

  def test_expand_border_side_allows_valid_sides
    %w[top right bottom left].each do |side|
      result = Cataract.expand_border_side(side, '1px solid red')

      assert_equal '1px', result["border-#{side}-width"]
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  def test_important_flag_preserved
    result = Cataract.expand_margin('10px !important')

    # Each expanded property should retain !important
    assert_match(/!important/, result['margin-top'])
    assert_match(/!important/, result['margin-right'])
    assert_match(/!important/, result['margin-bottom'])
    assert_match(/!important/, result['margin-left'])
  end

  def test_important_with_multiple_values
    result = Cataract.expand_margin('10px 20px !important')

    assert_equal '10px !important', result['margin-top']
    assert_equal '20px !important', result['margin-right']
    assert_equal '10px !important', result['margin-bottom']
    assert_equal '20px !important', result['margin-left']
  end

  def test_mixed_shorthand_and_longhand
    @sheet.parse('div { margin: 10px; margin-top: 20px; }')
    # each_selector now yields Declarations object, convert to string for expand_shorthand
    declarations_obj = @sheet.each_selector.first[1]
    declarations = @sheet.expand_shorthand(declarations_obj.to_s)

    # Longhand should override shorthand value
    assert_equal '20px', declarations['margin-top']
    assert_equal '10px', declarations['margin-right']
  end

  # ===========================================================================
  # Parser#expand_shorthand - Test all shorthand types through Parser API
  # ===========================================================================

  def test_parser_expand_shorthand_padding
    result = @sheet.expand_shorthand('padding: 5px 10px;')

    assert_equal '5px', result['padding-top']
    assert_equal '10px', result['padding-right']
    assert_equal '5px', result['padding-bottom']
    assert_equal '10px', result['padding-left']
  end

  def test_parser_expand_shorthand_border
    result = @sheet.expand_shorthand('border: 1px solid red;')

    assert_equal '1px', result['border-top-width']
    assert_equal '1px', result['border-right-width']
    assert_equal '1px', result['border-bottom-width']
    assert_equal '1px', result['border-left-width']
    assert_equal 'solid', result['border-top-style']
    assert_equal 'solid', result['border-right-style']
    assert_equal 'solid', result['border-bottom-style']
    assert_equal 'solid', result['border-left-style']
    assert_equal 'red', result['border-top-color']
    assert_equal 'red', result['border-right-color']
    assert_equal 'red', result['border-bottom-color']
    assert_equal 'red', result['border-left-color']
  end

  def test_parser_expand_shorthand_border_top
    result = @sheet.expand_shorthand('border-top: 2px dashed blue;')

    assert_equal '2px', result['border-top-width']
    assert_equal 'dashed', result['border-top-style']
    assert_equal 'blue', result['border-top-color']
  end

  def test_parser_expand_shorthand_border_right
    result = @sheet.expand_shorthand('border-right: 3px dotted green;')

    assert_equal '3px', result['border-right-width']
    assert_equal 'dotted', result['border-right-style']
    assert_equal 'green', result['border-right-color']
  end

  def test_parser_expand_shorthand_border_bottom
    result = @sheet.expand_shorthand('border-bottom: 4px double yellow;')

    assert_equal '4px', result['border-bottom-width']
    assert_equal 'double', result['border-bottom-style']
    assert_equal 'yellow', result['border-bottom-color']
  end

  def test_parser_expand_shorthand_border_left
    result = @sheet.expand_shorthand('border-left: 5px groove purple;')

    assert_equal '5px', result['border-left-width']
    assert_equal 'groove', result['border-left-style']
    assert_equal 'purple', result['border-left-color']
  end

  def test_parser_expand_shorthand_border_color
    result = @sheet.expand_shorthand('border-color: red blue;')

    assert_equal 'red', result['border-top-color']
    assert_equal 'blue', result['border-right-color']
    assert_equal 'red', result['border-bottom-color']
    assert_equal 'blue', result['border-left-color']
  end

  def test_parser_expand_shorthand_border_style
    result = @sheet.expand_shorthand('border-style: solid dashed;')

    assert_equal 'solid', result['border-top-style']
    assert_equal 'dashed', result['border-right-style']
    assert_equal 'solid', result['border-bottom-style']
    assert_equal 'dashed', result['border-left-style']
  end

  def test_parser_expand_shorthand_border_width
    result = @sheet.expand_shorthand('border-width: 1px 2px 3px;')

    assert_equal '1px', result['border-top-width']
    assert_equal '2px', result['border-right-width']
    assert_equal '3px', result['border-bottom-width']
    assert_equal '2px', result['border-left-width']
  end

  def test_parser_expand_shorthand_font
    result = @sheet.expand_shorthand('font: italic bold 16px/1.5 Arial, sans-serif;')

    assert_equal 'italic', result['font-style']
    assert_equal 'bold', result['font-weight']
    assert_equal '16px', result['font-size']
    assert_equal '1.5', result['line-height']
    assert_equal 'Arial, sans-serif', result['font-family']
  end

  def test_parser_expand_shorthand_list_style
    result = @sheet.expand_shorthand("list-style: square inside url('marker.png');")

    assert_equal 'square', result['list-style-type']
    assert_equal 'inside', result['list-style-position']
    assert_equal "url('marker.png')", result['list-style-image']
  end

  def test_parser_expand_shorthand_background
    result = @sheet.expand_shorthand("background: red url('bg.png') no-repeat center top;")

    assert_equal 'red', result['background-color']
    assert_equal "url('bg.png')", result['background-image']
    assert_equal 'no-repeat', result['background-repeat']
    # background-position captures all position values (per W3C spec)
    assert_equal 'center top', result['background-position']
  end

  def test_parser_expand_shorthand_with_important
    result = @sheet.expand_shorthand('margin: 10px !important;')

    assert_equal '10px !important', result['margin-top']
    assert_equal '10px !important', result['margin-right']
    assert_equal '10px !important', result['margin-bottom']
    assert_equal '10px !important', result['margin-left']
  end

  def test_parser_expand_shorthand_mixed_important
    result = @sheet.expand_shorthand('margin: 10px; padding: 5px !important;')

    assert_equal '10px', result['margin-top']
    assert_equal '10px', result['margin-right']
    assert_equal '5px !important', result['padding-top']
    assert_equal '5px !important', result['padding-right']
  end

  def test_parser_expand_shorthand_longhand_overrides_shorthand
    result = @sheet.expand_shorthand('margin: 10px; margin-top: 20px;')

    assert_equal '20px', result['margin-top']
    assert_equal '10px', result['margin-right']
    assert_equal '10px', result['margin-bottom']
    assert_equal '10px', result['margin-left']
  end

  def test_parser_expand_shorthand_longhand_only
    result = @sheet.expand_shorthand('color: red; font-size: 14px;')

    assert_equal 'red', result['color']
    assert_equal '14px', result['font-size']
  end

  def test_parser_expand_shorthand_empty_string
    result = @sheet.expand_shorthand('')

    assert_empty(result)
  end
end
