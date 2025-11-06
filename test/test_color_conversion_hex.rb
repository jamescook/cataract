# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionHex < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Tests targeting hex output

  def test_rgb_to_hex_white
    decls = convert_and_get_declarations(
      '.test { color: rgb(255 255 255) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ffffff', decls['color']
  end

  def test_rgb_to_hex_black
    decls = convert_and_get_declarations(
      '.test { color: rgb(0, 0, 0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#000000', decls['color']
  end

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
      '.test { color: rgb(128 64 192 / 0.75) }',
      from: :rgb, to: :hex
    )
    # 0.75 * 255 = 191.25 ≈ 191 = 0xbf
    assert_equal '#8040c0bf', decls['color']
  end

  def test_rgb_to_hex_with_alpha_legacy
    decls = convert_and_get_declarations(
      '.test { color: rgba(255, 0, 0, 0.5) }',
      from: :rgb, to: :hex
    )
    # 0.5 * 255 = 127.5 ≈ 128 = 0x80
    assert_equal '#ff000080', decls['color']
  end

  def test_rgb_to_hex_zero_alpha
    decls = convert_and_get_declarations(
      '.test { color: rgba(255, 0, 0, 0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff000000', decls['color']
  end

  def test_rgb_to_hex_full_opacity
    decls = convert_and_get_declarations(
      '.test { color: rgba(255, 0, 0, 1.0) }',
      from: :rgb, to: :hex
    )
    assert_equal '#ff0000ff', decls['color']
  end

  def test_rgb_to_hex_partial_alpha
    decls = convert_and_get_declarations(
      '.test { color: rgba(255, 128, 64, 0.25) }',
      from: :rgb, to: :hex
    )
    # 0.25 * 255 = 63.75 ≈ 64 = 0x40
    assert_equal '#ff804040', decls['color']
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

  def test_hsl_with_alpha_to_hex
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%, 0.5) }',
      from: :hsl, to: :hex
    )
    assert_equal '#ff000080', decls['color']
  end

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

  def test_hwb_with_alpha_to_hex
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0% / 0.5) }',
      from: :hwb, to: :hex
    )
    assert_equal '#ff000080', decls['color']
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

  def test_border_color_mixed_formats_to_hex
    decls = convert_and_get_declarations(
      '.test { border-color: rgb(255, 0, 0) #00ff00 hsl(240, 100%, 50%); }',
      to: :hex
    )
    assert_equal '#ff0000 #00ff00 #0000ff', decls['border-color']
  end
end
