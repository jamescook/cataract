#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'

# Test creating shorthand properties from longhand
# This is the inverse of shorthand expansion
class TestShorthandCreation < Minitest::Test
  # Margin shorthand creation
  def test_create_margin_all_same
    input = {
      'margin-top' => '10px',
      'margin-right' => '10px',
      'margin-bottom' => '10px',
      'margin-left' => '10px'
    }
    result = Cataract.create_margin_shorthand(input)
    assert_equal '10px', result
  end

  def test_create_margin_vertical_horizontal
    input = {
      'margin-top' => '10px',
      'margin-right' => '20px',
      'margin-bottom' => '10px',
      'margin-left' => '20px'
    }
    result = Cataract.create_margin_shorthand(input)
    assert_equal '10px 20px', result
  end

  def test_create_margin_top_horizontal_bottom
    input = {
      'margin-top' => '10px',
      'margin-right' => '20px',
      'margin-bottom' => '30px',
      'margin-left' => '20px'
    }
    result = Cataract.create_margin_shorthand(input)
    assert_equal '10px 20px 30px', result
  end

  def test_create_margin_all_different
    input = {
      'margin-top' => '10px',
      'margin-right' => '20px',
      'margin-bottom' => '30px',
      'margin-left' => '40px'
    }
    result = Cataract.create_margin_shorthand(input)
    assert_equal '10px 20px 30px 40px', result
  end

  def test_create_margin_missing_side
    input = {
      'margin-top' => '10px',
      'margin-right' => '20px',
      'margin-bottom' => '30px'
      # margin-left missing
    }
    result = Cataract.create_margin_shorthand(input)
    assert_nil result, 'Should return nil if not all sides present'
  end

  # Padding shorthand creation (same logic as margin)
  def test_create_padding_all_same
    input = {
      'padding-top' => '5px',
      'padding-right' => '5px',
      'padding-bottom' => '5px',
      'padding-left' => '5px'
    }
    result = Cataract.create_padding_shorthand(input)
    assert_equal '5px', result
  end

  def test_create_padding_vertical_horizontal
    input = {
      'padding-top' => '10px',
      'padding-right' => '20px',
      'padding-bottom' => '10px',
      'padding-left' => '20px'
    }
    result = Cataract.create_padding_shorthand(input)
    assert_equal '10px 20px', result
  end

  # Border-width shorthand creation (from individual sides)
  def test_create_border_width_all_same
    input = {
      'border-top-width' => '1px',
      'border-right-width' => '1px',
      'border-bottom-width' => '1px',
      'border-left-width' => '1px'
    }
    result = Cataract.create_border_width_shorthand(input)
    assert_equal '1px', result
  end

  def test_create_border_width_different
    input = {
      'border-top-width' => '1px',
      'border-right-width' => '2px',
      'border-bottom-width' => '3px',
      'border-left-width' => '4px'
    }
    result = Cataract.create_border_width_shorthand(input)
    assert_equal '1px 2px 3px 4px', result
  end

  # Border-style shorthand creation (from individual sides)
  def test_create_border_style_all_same
    input = {
      'border-top-style' => 'solid',
      'border-right-style' => 'solid',
      'border-bottom-style' => 'solid',
      'border-left-style' => 'solid'
    }
    result = Cataract.create_border_style_shorthand(input)
    assert_equal 'solid', result
  end

  # Border-color shorthand creation (from individual sides)
  def test_create_border_color_all_same
    input = {
      'border-top-color' => 'black',
      'border-right-color' => 'black',
      'border-bottom-color' => 'black',
      'border-left-color' => 'black'
    }
    result = Cataract.create_border_color_shorthand(input)
    assert_equal 'black', result
  end

  # Border shorthand creation (from border-width, border-style, border-color)
  def test_create_border_full
    input = {
      'border-width' => '1px',
      'border-style' => 'solid',
      'border-color' => 'black'
    }
    result = Cataract.create_border_shorthand(input)
    assert_equal '1px solid black', result
  end

  def test_create_border_partial
    input = {
      'border-width' => '2px',
      'border-style' => 'dashed'
      # border-color missing
    }
    result = Cataract.create_border_shorthand(input)
    assert_equal '2px dashed', result, 'Should combine available properties'
  end

  def test_create_border_missing_all
    input = {}
    result = Cataract.create_border_shorthand(input)
    assert_nil result, 'Should return nil if no border properties'
  end

  # Background shorthand creation
  def test_create_background_color_only
    input = {
      'background-color' => 'red'
    }
    result = Cataract.create_background_shorthand(input)
    assert_equal 'red', result
  end

  def test_create_background_multiple
    input = {
      'background-color' => 'black',
      'background-image' => 'none'
    }
    result = Cataract.create_background_shorthand(input)
    assert_equal 'black none', result
  end

  def test_create_background_full
    input = {
      'background-color' => 'white',
      'background-image' => 'url(bg.png)',
      'background-repeat' => 'no-repeat',
      'background-position' => 'center'
    }
    result = Cataract.create_background_shorthand(input)
    assert_equal 'white url(bg.png) no-repeat center', result
  end

  # Font shorthand creation
  def test_create_font_minimal
    input = {
      'font-size' => '12px',
      'font-family' => 'Arial'
    }
    result = Cataract.create_font_shorthand(input)
    assert_equal '12px Arial', result
  end

  def test_create_font_with_weight
    input = {
      'font-weight' => 'bold',
      'font-size' => '14px',
      'font-family' => 'Helvetica'
    }
    result = Cataract.create_font_shorthand(input)
    assert_equal 'bold 14px Helvetica', result
  end

  def test_create_font_full
    input = {
      'font-style' => 'italic',
      'font-weight' => 'bold',
      'font-size' => '16px',
      'line-height' => '1.5',
      'font-family' => 'Georgia, serif'
    }
    result = Cataract.create_font_shorthand(input)
    assert_equal 'italic bold 16px/1.5 Georgia, serif', result
  end

  def test_create_font_missing_required
    input = {
      'font-weight' => 'bold'
      # missing font-size and font-family (required)
    }
    result = Cataract.create_font_shorthand(input)
    assert_nil result, 'Should return nil without required properties'
  end

  # List-style shorthand creation
  def test_create_list_style_type_only
    input = {
      'list-style-type' => 'disc'
    }
    result = Cataract.create_list_style_shorthand(input)
    assert_equal 'disc', result
  end

  def test_create_list_style_multiple
    input = {
      'list-style-type' => 'square',
      'list-style-position' => 'inside'
    }
    result = Cataract.create_list_style_shorthand(input)
    assert_equal 'square inside', result
  end
end
