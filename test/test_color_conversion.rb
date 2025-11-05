# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversion < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Hex to RGB conversion tests

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

    # Get merged declarations for each selector
    rules_array = []
    sheet.rules.each { |rule| rules_array << rule }

    decls_one = Cataract::Declarations.new(rules_array[0].declarations)
    decls_two = Cataract::Declarations.new(rules_array[1].declarations)

    assert_equal 'rgb(255 255 255)', decls_one['color']
    assert_equal 'rgb(0 0 0)', decls_two['color']
  end

  def test_hex_to_rgb_preserves_non_hex_colors
    decls = convert_and_get_declarations(
      '.test { color: blue; background: rgb(255, 0, 0); border-color: hsl(120, 100%, 50%) }',
      from: :hex, to: :rgb, variant: :modern
    )
    # Should not convert non-hex colors
    assert_equal 'blue', decls['color']
    # background shorthand expands to background-color
    assert_equal 'rgb(255, 0, 0)', decls['background-color']
    assert_equal 'hsl(120, 100%, 50%)', decls['border-color']
  end

  def test_hex_to_rgb_mixed_hex_and_non_hex
    decls = convert_and_get_declarations(
      '.test { color: #fff; background: blue }',
      from: :hex, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 255 255)', decls['color']
    # background shorthand expands to background-color
    assert_equal 'blue', decls['background-color']
  end

  def test_hex_to_rgb_in_shorthand_background
    decls = convert_and_get_declarations(
      '.test { background: #fff url(img.png) no-repeat }',
      from: :hex, to: :rgb, variant: :modern
    )
    # Should convert the hex color within the shorthand value
    assert_equal 'rgb(255 255 255) url(img.png) no-repeat', decls['background']
  end

  def test_hex_to_rgb_full_opacity_alpha
    decls = convert_and_get_declarations(
      '.test { color: #ff0000ff }',
      from: :hex, to: :rgb, variant: :modern
    )
    # Full opacity (ff = 255 = 1.0)
    result = decls['color']
    assert_match(/^rgb\(255 0 0 \/ 1(\.0*)?\)$/, result)
  end

  def test_hex_to_rgb_zero_alpha
    decls = convert_and_get_declarations(
      '.test { color: #ff000000 }',
      from: :hex, to: :rgb, variant: :modern
    )
    result = decls['color']
    assert_match(/^rgb\(255 0 0 \/ 0(\.0*)?\)$/, result)
  end

  def test_hex_to_rgb_returns_self
    stylesheet = Cataract.parse_css('.test { color: #fff }')
    result = stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    assert_same stylesheet, result
  end

  def test_convert_colors_with_media_queries
    sheet = Cataract.parse_css(<<~CSS)
      .test { color: #fff }
      @media screen {
        .test { color: #000 }
      }
    CSS
    sheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)

    # Collect all rules
    rules_array = []
    sheet.rules.each { |rule| rules_array << rule }

    # Top-level rule (all media)
    decls_top = Cataract::Declarations.new(rules_array[0].declarations)
    assert_equal 'rgb(255 255 255)', decls_top['color']

    # Rule inside @media screen
    decls_media = Cataract::Declarations.new(rules_array[1].declarations)
    assert_equal 'rgb(0 0 0)', decls_media['color']
  end

  # Edge cases - invalid/garbage color values

  def test_hex_to_rgb_invalid_length
    stylesheet = Cataract.parse_css('.test { color: #ff }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_invalid_five_digit
    stylesheet = Cataract.parse_css('.test { color: #12345 }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_invalid_characters
    stylesheet = Cataract.parse_css('.test { color: #gggggg }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_malformed_with_spaces
    # Parser might accept this as valid grammar but it's nonsense
    stylesheet = Cataract.parse_css('.test { color: #ff 00 00 }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_just_hash_symbol
    stylesheet = Cataract.parse_css('.test { color: # }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  # RGB to Hex conversion tests

  def test_rgb_to_hex_modern_syntax
    decls = convert_and_get_declarations(
      '.test { color: rgb(255 0 0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_rgb_to_hex_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_rgb_to_hex_with_alpha_modern
    decls = convert_and_get_declarations(
      '.test { color: rgb(255 0 0 / 0.5) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff000080', decls['color']
  end

  def test_rgb_to_hex_with_alpha_legacy
    decls = convert_and_get_declarations(
      '.test { color: rgba(255, 0, 0, 0.5) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff000080', decls['color']
  end

  def test_rgb_to_hex_white
    decls = convert_and_get_declarations(
      '.test { color: rgb(255 255 255) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ffffff', decls['color']
  end

  def test_rgb_to_hex_black
    decls = convert_and_get_declarations(
      '.test { color: rgb(0 0 0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#000000', decls['color']
  end

  def test_rgb_to_hex_full_opacity
    decls = convert_and_get_declarations(
      '.test { color: rgb(255 0 0 / 1.0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff0000ff', decls['color']
  end

  def test_rgb_to_hex_zero_alpha
    decls = convert_and_get_declarations(
      '.test { color: rgb(255 0 0 / 0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff000000', decls['color']
  end

  def test_rgb_to_hex_partial_alpha
    decls = convert_and_get_declarations(
      '.test { color: rgb(128 64 192 / 0.75) }',
      from: :rgb, to: :hex
    )
    # 0.75 * 255 = 191.25 ≈ 191 = 0xbf
    assert_equal '#8040c0bf', decls['color']
  end

  def test_rgb_to_hex_out_of_range_high
    stylesheet = Cataract.parse_css('.test { color: rgb(300, 0, 0) }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :rgb, to: :hex)
    end
    assert_match(/invalid rgb values/i, error.message)
  end

  def test_rgb_to_hex_out_of_range_negative
    stylesheet = Cataract.parse_css('.test { color: rgb(-10, 0, 0) }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :rgb, to: :hex)
    end
    assert_match(/invalid rgb values/i, error.message)
  end

  # HSL conversion tests

  def test_hex_to_hsl_red
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :hex, to: :hsl
    )
    assert_equal 'hsl(0, 100%, 50%)', decls['color']
  end

  def test_hex_to_hsl_green
    decls = convert_and_get_declarations(
      '.test { color: #00ff00 }',
      from: :hex, to: :hsl
    )
    assert_equal 'hsl(120, 100%, 50%)', decls['color']
  end

  def test_hex_to_hsl_blue
    decls = convert_and_get_declarations(
      '.test { color: #0000ff }',
      from: :hex, to: :hsl
    )
    assert_equal 'hsl(240, 100%, 50%)', decls['color']
  end

  def test_hex_to_hsl_white
    decls = convert_and_get_declarations(
      '.test { color: #ffffff }',
      from: :hex, to: :hsl
    )
    assert_equal 'hsl(0, 0%, 100%)', decls['color']
  end

  def test_hex_to_hsl_black
    decls = convert_and_get_declarations(
      '.test { color: #000000 }',
      from: :hex, to: :hsl
    )
    assert_equal 'hsl(0, 0%, 0%)', decls['color']
  end

  def test_hex_to_hsl_gray
    decls = convert_and_get_declarations(
      '.test { color: #808080 }',
      from: :hex, to: :hsl
    )
    assert_equal 'hsl(0, 0%, 50%)', decls['color']
  end

  def test_hsl_to_hex_red
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%) }',
      from: :hsl, to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_hsl_to_hex_green
    decls = convert_and_get_declarations(
      '.test { color: hsl(120, 100%, 50%) }',
      from: :hsl, to: :hex
    )
    assert_equal '#00ff00', decls['color']
  end

  def test_hsl_to_hex_blue
    decls = convert_and_get_declarations(
      '.test { color: hsl(240, 100%, 50%) }',
      from: :hsl, to: :hex
    )
    assert_equal '#0000ff', decls['color']
  end

  def test_hsl_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%) }',
      from: :hsl, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_rgb_to_hsl
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      from: :rgb, to: :hsl
    )
    assert_equal 'hsl(0, 100%, 50%)', decls['color']
  end

  def test_hsl_with_alpha_to_hex
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%, 0.5) }',
      from: :hsl, to: :hex
    )
    assert_equal '#ff000080', decls['color']
  end

  # HWB conversion tests

  def test_hwb_to_hex_red
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_hwb_to_hex_green
    decls = convert_and_get_declarations(
      '.test { color: hwb(120 0% 0%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#00ff00', decls['color']
  end

  def test_hwb_to_hex_blue
    decls = convert_and_get_declarations(
      '.test { color: hwb(240 0% 0%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#0000ff', decls['color']
  end

  def test_hwb_to_hex_with_whiteness
    # hwb(0 50% 0%) = pure red mixed with 50% white = light red
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 50% 0%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#ff8080', decls['color']
  end

  def test_hwb_to_hex_with_blackness
    # hwb(0 0% 50%) = pure red mixed with 50% black = dark red
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 50%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#800000', decls['color']
  end

  def test_hwb_to_hex_with_whiteness_and_blackness
    # hwb(0 25% 25%) = red with 25% white and 25% black
    # Pure red (1,0,0) * (1-0.25-0.25) + 0.25 = (0.75, 0.25, 0.25) = #bf4040
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 25% 25%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#bf4040', decls['color']
  end

  def test_hwb_to_hex_gray_from_wb_sum_100
    # hwb(0 50% 50%) = gray (when W+B=100%, hue doesn't matter)
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 50% 50%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#808080', decls['color']
  end

  def test_hwb_to_hex_normalized_wb_over_100
    # hwb(0 60% 60%) = W+B=120% > 100%, should normalize to 50%/50% = gray
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 60% 60%) }',
      from: :hwb, to: :hex
    )
    assert_equal '#808080', decls['color']
  end

  def test_hwb_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      from: :hwb, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_hwb_to_hsl
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      from: :hwb, to: :hsl
    )
    assert_equal 'hsl(0, 100%, 50%)', decls['color']
  end

  def test_rgb_to_hwb
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      from: :rgb, to: :hwb
    )
    assert_equal 'hwb(0 0% 0%)', decls['color']
  end

  def test_hex_to_hwb
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :hex, to: :hwb
    )
    assert_equal 'hwb(0 0% 0%)', decls['color']
  end

  def test_hwb_with_alpha_to_hex
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0% / 0.5) }',
      from: :hwb, to: :hex
    )
    assert_equal '#ff000080', decls['color']
  end

  def test_unsupported_source_format
    stylesheet = Cataract.parse_css('.test { color: #fff }')
    error = assert_raises(ArgumentError) do
      stylesheet.convert_colors!(from: :cmyk, to: :hex)
    end
    assert_match(/unsupported source format/i, error.message)
  end

  def test_unsupported_target_format
    stylesheet = Cataract.parse_css('.test { color: #fff }')
    error = assert_raises(ArgumentError) do
      stylesheet.convert_colors!(from: :hex, to: :cmyk)
    end
    assert_match(/unsupported target format/i, error.message)
  end

  # Auto-detect format tests (from: :any or omitted)

  def test_auto_detect_hex_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_auto_detect_rgb_to_hex
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_auto_detect_hsl_to_hex
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%) }',
      to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_auto_detect_hwb_to_hex
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      to: :hex
    )
    assert_equal '#ff0000', decls['color']
  end

  def test_auto_detect_mixed_to_hex
    sheet = Cataract.parse_css(<<~CSS)
      .red { color: #ff0000 }
      .green { color: rgb(0, 255, 0) }
      .blue { color: hsl(240, 100%, 50%) }
      .yellow { color: hwb(60 0% 0%) }
    CSS
    sheet.convert_colors!(to: :hex)

    rules_array = []
    sheet.rules.each { |rule| rules_array << rule }

    decls_red = Cataract::Declarations.new(rules_array[0].declarations)
    decls_green = Cataract::Declarations.new(rules_array[1].declarations)
    decls_blue = Cataract::Declarations.new(rules_array[2].declarations)
    decls_yellow = Cataract::Declarations.new(rules_array[3].declarations)

    assert_equal '#ff0000', decls_red['color']
    assert_equal '#00ff00', decls_green['color']
    assert_equal '#0000ff', decls_blue['color']
    assert_equal '#ffff00', decls_yellow['color']
  end

  def test_auto_detect_mixed_to_hsl
    sheet = Cataract.parse_css(<<~CSS)
      .red { color: #ff0000 }
      .green { color: rgb(0, 255, 0) }
      .blue { color: hsl(240, 100%, 50%) }
    CSS
    sheet.convert_colors!(to: :hsl)

    rules_array = []
    sheet.rules.each { |rule| rules_array << rule }

    decls_red = Cataract::Declarations.new(rules_array[0].declarations)
    decls_green = Cataract::Declarations.new(rules_array[1].declarations)
    decls_blue = Cataract::Declarations.new(rules_array[2].declarations)

    assert_equal 'hsl(0, 100%, 50%)', decls_red['color']
    assert_equal 'hsl(120, 100%, 50%)', decls_green['color']
    assert_equal 'hsl(240, 100%, 50%)', decls_blue['color']
  end

  def test_explicit_any_format
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :any, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  def test_missing_to_argument
    stylesheet = Cataract.parse_css('.test { color: #fff }')
    error = assert_raises(ArgumentError) do
      stylesheet.convert_colors!
    end
    assert_match(/missing keyword.*:to/i, error.message)
  end

  def test_ignores_gradients_with_embedded_colors
    # Should not try to convert colors embedded in gradient functions
    sheet = Cataract.parse_css(<<~CSS)
      .test {
        background: linear-gradient(180deg, rgba(255, 255, 255, 0.15), rgba(255, 255, 255, 0));
      }
    CSS

    # Should not raise an error - gradient values should be ignored
    sheet.convert_colors!(to: :hex)

    decls = Cataract::Declarations.new(sheet.rules.first.declarations)
    # Gradient should remain unchanged
    assert_match(/linear-gradient/, decls['background'])
  end

  def test_converts_standalone_colors_not_gradients
    # Should convert standalone color but ignore gradient
    sheet = Cataract.parse_css(<<~CSS)
      .test {
        color: rgb(255, 0, 0);
        background: linear-gradient(180deg, rgba(255, 255, 255, 0.15), rgba(255, 255, 255, 0));
      }
    CSS

    sheet.convert_colors!(to: :hex)

    decls = Cataract::Declarations.new(sheet.rules.first.declarations)
    assert_equal '#ff0000', decls['color']
    assert_match(/linear-gradient/, decls['background'])
  end

  # Multi-value color property tests

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

  def test_border_color_mixed_formats_to_hex
    decls = convert_and_get_declarations(
      '.test { border-color: rgb(255, 0, 0) #00ff00 hsl(240, 100%, 50%); }',
      to: :hex
    )
    assert_equal '#ff0000 #00ff00 #0000ff', decls['border-color']
  end

  def test_outline_color_single_value
    decls = convert_and_get_declarations(
      '.test { outline-color: #ff0000; }',
      to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['outline-color']
  end

  def test_box_shadow_with_color
    # box-shadow: 0 0 10px #ff0000
    decls = convert_and_get_declarations(
      '.test { box-shadow: 0 0 10px #ff0000; }',
      to: :rgb, variant: :modern
    )
    assert_equal '0 0 10px rgb(255 0 0)', decls['box-shadow']
  end

  def test_text_shadow_with_color
    # text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5)
    decls = convert_and_get_declarations(
      '.test { text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5); }',
      to: :hex
    )
    assert_equal '2px 2px 4px #00000080', decls['text-shadow']
  end

  def test_multiple_box_shadows
    # Multiple box-shadows separated by commas
    decls = convert_and_get_declarations(
      '.test { box-shadow: 0 0 10px #ff0000, 0 0 20px #00ff00; }',
      to: :rgb, variant: :modern
    )
    assert_equal '0 0 10px rgb(255 0 0), 0 0 20px rgb(0 255 0)', decls['box-shadow']
  end

  def test_ignores_colors_in_data_uri
    # Should not convert colors inside url() data URIs
    decls = convert_and_get_declarations(
      %q(.test { background-image: url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='rgba%280, 0, 0, 0.25%29'/%3e%3c/svg%3e"); }),
      to: :hex
    )
    # URL should remain unchanged
    assert_match(/url\("data:image\/svg/, decls['background-image'])
    assert_match(/rgba%280, 0, 0, 0.25%29/, decls['background-image'])
  end

  def test_converts_colors_outside_url_but_not_inside
    # Should convert standalone color but ignore colors in url()
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0); background-image: url("data:image/svg+xml,%3csvg fill=\'%23ff0000\'%3e%3c/svg%3e"); }',
      to: :hex
    )
    assert_equal '#ff0000', decls['color']
    # The %23ff0000 in the URL should NOT be converted
    assert_match(/%23ff0000/, decls['background-image'])
  end

  # Format alias tests

  def test_rgba_alias_uses_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :rgba
    )
    # :rgba should produce rgba() not rgb(... / alpha)
    assert_match(/^rgba\(255, 0, 0, 0\.50\d+\)$/, decls['color'])
  end

  def test_hsla_alias_uses_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :hsla
    )
    # :hsla should produce hsl() with alpha
    assert_match(/^hsl\(\d+, \d+%, \d+%, 0\.50/, decls['color'])
  end

  def test_hwba_alias_uses_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :hwba
    )
    # :hwba should produce hwb() with alpha
    assert_match(/^hwb\(\d+ \d+% \d+% \/ 0\.50/, decls['color'])
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
