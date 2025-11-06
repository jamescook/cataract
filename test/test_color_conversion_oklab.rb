# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionOklab < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Tests targeting oklab output

  def test_hex_to_oklab_red
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :hex, to: :oklab
    )
    # Red in sRGB: rgb(255, 0, 0)
    # Red in Oklab: oklab(0.6280 0.2249 0.1258)
    assert_equal 'oklab(0.6280 0.2249 0.1258)', decls['color']
  end

  def test_hex_to_oklab_green
    decls = convert_and_get_declarations(
      '.test { color: #00ff00 }',
      from: :hex, to: :oklab
    )
    # Green in sRGB: rgb(0, 255, 0)
    # Green in Oklab: oklab(0.8664 -0.2339 0.1795)
    assert_equal 'oklab(0.8664 -0.2339 0.1795)', decls['color']
  end

  def test_hex_to_oklab_blue
    decls = convert_and_get_declarations(
      '.test { color: #0000ff }',
      from: :hex, to: :oklab
    )
    # Blue in sRGB: rgb(0, 0, 255)
    # Blue in Oklab: oklab(0.4520 -0.0325 -0.3115)
    assert_equal 'oklab(0.4520 -0.0325 -0.3115)', decls['color']
  end

  def test_hex_to_oklab_white
    decls = convert_and_get_declarations(
      '.test { color: #ffffff }',
      from: :hex, to: :oklab
    )
    # White: oklab(1.0 0.0 0.0)
    assert_equal 'oklab(1.0000 0.0000 0.0000)', decls['color']
  end

  def test_hex_to_oklab_black
    decls = convert_and_get_declarations(
      '.test { color: #000000 }',
      from: :hex, to: :oklab
    )
    # Black: oklab(0.0 0.0 0.0)
    assert_equal 'oklab(0.0000 0.0000 0.0000)', decls['color']
  end

  def test_hex_to_oklab_gray
    decls = convert_and_get_declarations(
      '.test { color: #808080 }',
      from: :hex, to: :oklab
    )
    # Gray (#808080 = rgb(128, 128, 128))
    assert_equal 'oklab(0.5999 0.0000 0.0000)', decls['color']
  end

  def test_rgb_to_oklab
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      from: :rgb, to: :oklab
    )

    assert_equal 'oklab(0.6280 0.2249 0.1258)', decls['color']
  end

  def test_hsl_to_oklab
    decls = convert_and_get_declarations(
      '.test { color: hsl(0, 100%, 50%) }',
      from: :hsl, to: :oklab
    )

    assert_equal 'oklab(0.6280 0.2249 0.1258)', decls['color']
  end

  def test_hwb_to_oklab
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      from: :hwb, to: :oklab
    )

    assert_equal 'oklab(0.6280 0.2249 0.1258)', decls['color']
  end

  def test_oklab_to_hex
    decls = convert_and_get_declarations(
      '.test { color: oklab(0.628 0.225 0.126) }',
      from: :oklab, to: :hex
    )
    # Should convert back to red #ff0000
    assert_equal '#ff0000', decls['color']
  end

  def test_oklab_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: oklab(0.628 0.225 0.126) }',
      from: :oklab, to: :rgb
    )
    # Should convert to rgb(100% 0% 0%) preserving precision (≈ rgb(255 0 0))
    assert_equal 'rgb(100.000% 0.000% 0.000%)', decls['color']
  end

  def test_oklab_round_trip_red
    # Test round-trip: hex -> oklab -> hex
    sheet = Cataract.parse_css('.test { color: #ff0000 }')
    sheet.convert_colors!(from: :hex, to: :oklab)
    decls1 = Cataract::Declarations.new(sheet.declarations)
    oklab_value = decls1['color']

    sheet2 = Cataract.parse_css(".test { color: #{oklab_value} }")
    sheet2.convert_colors!(from: :oklab, to: :hex)
    decls2 = Cataract::Declarations.new(sheet2.declarations)

    assert_equal '#ff0000', decls2['color']
  end

  def test_oklab_with_alpha
    decls = convert_and_get_declarations(
      '.test { color: #ff000080 }',
      from: :hex, to: :oklab
    )
    # Should have alpha in the oklab output: oklab(L a b / alpha)
    assert_equal 'oklab(0.6280 0.2249 0.1258 / 0.5019607843)', decls['color']
  end

  def test_auto_detect_mixed_to_oklab
    sheet = Cataract.parse_css(<<~CSS)
      .red { color: #ff0000 }
      .green { color: rgb(0, 255, 0) }
      .blue { color: hsl(240, 100%, 50%) }
    CSS
    sheet.convert_colors!(to: :oklab)

    rules_array = sheet.rules.map { |rule| rule }

    decls_red = Cataract::Declarations.new(rules_array[0].declarations)
    decls_green = Cataract::Declarations.new(rules_array[1].declarations)
    decls_blue = Cataract::Declarations.new(rules_array[2].declarations)

    assert_equal 'oklab(0.6280 0.2249 0.1258)', decls_red['color']
    assert_equal 'oklab(0.8664 -0.2339 0.1795)', decls_green['color']
    assert_equal 'oklab(0.4520 -0.0325 -0.3115)', decls_blue['color']
  end

  def test_oklab_preserves_negative_values
    # a and b can be negative in Oklab - test precision preservation
    decls = convert_and_get_declarations(
      '.test { color: oklab(0.5 -0.1 -0.2) }',
      from: :oklab, to: :oklab
    )
    # Should preserve exact values with 4 decimal places
    assert_equal 'oklab(0.5000 -0.1000 -0.2000)', decls['color']
  end
end
