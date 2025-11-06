# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionRgb < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Tests targeting rgb/rgba output

  def test_hex_to_rgb_three_digit
    decls = convert_and_get_declarations(
      '.test { color: #fff }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 255 255)', decls['color']
  end

  def test_hex_to_rgb_three_digit_legacy
    decls = convert_and_get_declarations(
      '.test { color: #fff }',
      from: :hex, to: :rgb, variant: :legacy
    )
    assert_equal 'rgb(255, 255, 255)', decls['color']
  end

  def test_hex_to_rgb_six_digit
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_hex_to_rgb_six_digit_lowercase
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_hex_to_rgb_six_digit_uppercase
    decls = convert_and_get_declarations(
      '.test { color: #FF0000 }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_hex_to_rgb_eight_digit_with_alpha
    decls = convert_and_get_declarations(
      '.test { color: #ff000080 }',
      from: :hex, to: :rgb, variant: :modern
    )
    result = decls['color']
    assert_match(/^rgb\(255 0 0 \/ (0\.50\d*)\)$/, result)
    # Extract and validate alpha value (0x80 / 255 ≈ 0.502)
    alpha = result[/\/ ([\d.]+)\)/, 1].to_f
    assert_in_delta 0.502, alpha, 0.001
  end

  def test_hex_to_rgb_eight_digit_with_alpha_legacy
    decls = convert_and_get_declarations(
      '.test { color: #ff000080 }',
      from: :hex, to: :rgb, variant: :legacy
    )
    result = decls['color']
    assert_match(/^rgba\(255, 0, 0, (0\.50\d*)\)$/, result)
    # Extract and validate alpha value (0x80 / 255 ≈ 0.502)
    alpha = result[/, ([\d.]+)\)/, 1].to_f
    assert_in_delta 0.502, alpha, 0.001
  end

  def test_hex_to_rgb_zero_alpha
    decls = convert_and_get_declarations(
      '.test { color: #ff000000 }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0 / 0)', decls['color']
  end

  def test_hex_to_rgb_full_opacity_alpha
    decls = convert_and_get_declarations(
      '.test { color: #ff0000ff }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0 / 1)', decls['color']
  end

  def test_hex_to_rgb_multiple_properties
    decls = convert_and_get_declarations(<<~CSS, from: :hex, to: :rgb, variant: :modern)
      .test {
        color: #fff;
        background-color: #000;
        border-color: #ff0000;
      }
    CSS

    assert_equal 'rgb(255 255 255)', decls['color']
    assert_equal 'rgb(0 0 0)', decls['background-color']
    assert_equal 'rgb(255 0 0)', decls['border-color']
  end

  def test_hex_to_rgb_multiple_rules
    sheet = Cataract.parse_css(<<~CSS)
      .one { color: #fff }
      .two { color: #000 }
    CSS
    sheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)

    rules_array = []
    sheet.rules.each { |rule| rules_array << rule }

    decls_one = Cataract::Declarations.new(rules_array[0].declarations)
    decls_two = Cataract::Declarations.new(rules_array[1].declarations)

    assert_equal 'rgb(255 255 255)', decls_one['color']
    assert_equal 'rgb(0 0 0)', decls_two['color']
  end

  def test_hsl_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%) }',
      from: :hsl, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_hwb_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      from: :hwb, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_auto_detect_hex_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_border_color_three_values_hex_to_rgb
    decls = convert_and_get_declarations(
      '.test { border-color: #e9ecef #e9ecef #dee2e6; }',
      to: :rgb, variant: :modern
    )
    assert_equal 'rgb(233 236 239) rgb(233 236 239) rgb(222 226 230)', decls['border-color']
  end

  def test_border_color_four_values_hex_to_rgb
    decls = convert_and_get_declarations(
      '.test { border-color: #ff0000 #00ff00 #0000ff #ffff00; }',
      to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0) rgb(0 255 0) rgb(0 0 255) rgb(255 255 0)', decls['border-color']
  end

  def test_box_shadow_with_color
    # box-shadow: 0 0 10px #ff0000
    decls = convert_and_get_declarations(
      '.test { box-shadow: 0 0 10px #ff0000; }',
      to: :rgb, variant: :modern
    )
    assert_equal '0 0 10px rgb(255 0 0)', decls['box-shadow']
  end

  def test_multiple_box_shadows
    # Multiple box-shadows separated by commas
    decls = convert_and_get_declarations(
      '.test { box-shadow: 0 0 10px #ff0000, 0 0 20px #00ff00; }',
      to: :rgb, variant: :modern
    )
    assert_equal '0 0 10px rgb(255 0 0), 0 0 20px rgb(0 255 0)', decls['box-shadow']
  end

  def test_rgba_alias_uses_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :rgba
    )
    # :rgba should produce rgba() not rgb(... / alpha)
    assert_match(/^rgba\(255, 0, 0, 0\.50\d+\)$/, decls['color'])
  end

  def test_rgb_uses_modern_syntax_by_default
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :rgb
    )
    # :rgb should produce rgb(... / alpha) not rgba()
    assert_match(/^rgb\(\d+ \d+ \d+ \/ 0\.50/, decls['color'])
  end
end
