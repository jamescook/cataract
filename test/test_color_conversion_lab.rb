# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionLab < Minitest::Test
  # W3C Spec Examples - Basic colors

  def test_lab_green_to_hex
    # W3C: lab(46.2775% -47.5621 48.5837) is green (#008000)
    decls = convert_and_get_declarations(
      '.test { color: lab(46.2775% -47.5621 48.5837); }',
      from: :lab, to: :hex
    )

    assert_equal '#008000', decls['color']
  end

  def test_lab_black
    # W3C: lab(0% 0 0) is black
    decls = convert_and_get_declarations(
      '.test { color: lab(0% 0 0); }',
      from: :lab, to: :hex
    )

    assert_equal '#000000', decls['color']
  end

  def test_lab_white
    # W3C: lab(100% 0 0) is white
    decls = convert_and_get_declarations(
      '.test { color: lab(100% 0 0); }',
      from: :lab, to: :hex
    )

    assert_equal '#ffffff', decls['color']
  end

  # W3C Spec Examples - Lab to RGB conversions with percentages

  def test_lab_to_rgb_example_1
    # W3C: lab(50% 50 0) -> rgb(~75.6% ~30.4% ~47.6%)
    decls = convert_and_get_declarations(
      '.test { color: lab(50% 50 0); }',
      from: :lab, to: :rgb
    )

    assert_equal 'rgb(75.614% 30.451% 47.572%)', decls['color']
  end

  def test_lab_to_rgb_example_2
    # W3C: lab(70% -45 0) -> rgb(~10.7% ~75.6% ~66.4%)
    decls = convert_and_get_declarations(
      '.test { color: lab(70% -45 0); }',
      from: :lab, to: :rgb
    )

    assert_equal 'rgb(10.697% 75.560% 66.410%)', decls['color']
  end

  def test_lab_to_rgb_example_3
    # W3C: lab(70% 0 70) -> rgb(~76.6% ~66.4% ~5.6%)
    decls = convert_and_get_declarations(
      '.test { color: lab(70% 0 70); }',
      from: :lab, to: :rgb
    )

    assert_equal 'rgb(76.613% 66.364% 5.596%)', decls['color']
  end

  def test_lab_to_rgb_example_4
    # W3C: lab(55% 0 -60) -> rgb(~12.8% ~53.1% ~92.8%)
    decls = convert_and_get_declarations(
      '.test { color: lab(55% 0 -60); }',
      from: :lab, to: :rgb
    )

    assert_equal 'rgb(12.767% 53.107% 92.779%)', decls['color']
  end

  # W3C Spec Example - Lightness clamping

  def test_lab_clamps_lightness_above_100
    # W3C: lab(150 150 20) should clamp L to 100
    decls1 = convert_and_get_declarations(
      '.test { color: lab(100 150 20); }',
      from: :lab, to: :rgb
    )
    decls2 = convert_and_get_declarations(
      '.test { color: lab(150 150 20); }',
      from: :lab, to: :rgb
    )
    # Both should produce the same result after clamping
    assert_equal decls1['color'], decls2['color']
  end

  def test_lab_clamps_lightness_below_0
    # Lightness below 0 should clamp to 0 (black)
    decls1 = convert_and_get_declarations(
      '.test { color: lab(0 0 0); }',
      from: :lab, to: :hex
    )
    decls2 = convert_and_get_declarations(
      '.test { color: lab(-50 0 0); }',
      from: :lab, to: :hex
    )

    assert_equal decls1['color'], decls2['color']
    assert_equal '#000000', decls1['color']
  end

  # Additional tests - Parsing variations

  def test_lab_with_numbers_not_percentages
    # Lab supports both percentages and numbers
    # lab(50 25 -25) - L as number (0-100), a and b as numbers
    decls = convert_and_get_declarations(
      '.test { color: lab(50 25 -25); }',
      from: :lab, to: :hex
    )

    assert_equal '#9168a2', decls['color']
  end

  def test_lab_mixed_percentages_and_numbers
    # Lab allows mixing percentages (L) and numbers (a, b)
    # lab(50% 25 -25) should be same as lab(50 25 -25)
    decls = convert_and_get_declarations(
      '.test { color: lab(50% 25 -25); }',
      from: :lab, to: :hex
    )

    assert_equal '#9168a2', decls['color']
  end

  def test_lab_with_alpha
    # Lab with alpha channel: lab(50% 25 -25 / 0.5)
    decls = convert_and_get_declarations(
      '.test { color: lab(50% 25 -25 / 0.5); }',
      from: :lab, to: :hex
    )
    # Should produce 8-digit hex with alpha ~0.5 (0x80)
    assert_equal '#9168a280', decls['color']
  end

  def test_lab_with_alpha_percentage
    # Alpha as percentage: 50% = 0.5
    decls = convert_and_get_declarations(
      '.test { color: lab(50% 25 -25 / 50%); }',
      from: :lab, to: :hex
    )

    assert_equal '#9168a280', decls['color']
  end

  # Round-trip tests

  def test_hex_to_lab_red
    sheet = Cataract.parse_css('.test { color: #ff0000; }')
    sheet.convert_colors!(from: :hex, to: :lab)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Red (#ff0000) in Lab
    assert_equal 'lab(54.2943% 80.8192 69.8969)', decls['color']
  end

  def test_hex_to_lab_green
    sheet = Cataract.parse_css('.test { color: #00ff00; }')
    sheet.convert_colors!(from: :hex, to: :lab)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Green (#00ff00) in Lab
    assert_equal 'lab(87.8177% -79.2608 80.9982)', decls['color']
  end

  def test_hex_to_lab_blue
    sheet = Cataract.parse_css('.test { color: #0000ff; }')
    sheet.convert_colors!(from: :hex, to: :lab)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Blue (#0000ff) in Lab
    assert_equal 'lab(29.5647% 68.2889 -112.0126)', decls['color']
  end

  def test_lab_round_trip_red
    # Test round-trip: hex -> lab -> hex
    sheet = Cataract.parse_css('.test { color: #ff0000; }')
    sheet.convert_colors!(from: :hex, to: :lab)
    decls1 = Cataract::Declarations.new(sheet.rules.first.declarations)
    lab_value = decls1['color']

    sheet2 = Cataract.parse_css(".test { color: #{lab_value}; }")
    sheet2.convert_colors!(from: :lab, to: :hex)
    decls2 = Cataract::Declarations.new(sheet2.rules.first.declarations)

    # Should round-trip back to red
    assert_equal '#ff0000', decls2['color']
  end

  # Edge cases

  def test_lab_gray
    # Lab with a=0, b=0 should produce grayscale
    decls = convert_and_get_declarations(
      '.test { color: lab(50% 0 0); }',
      from: :lab, to: :hex
    )
    # L=50% should produce approximately #777777
    assert_equal '#777777', decls['color']
  end

  def test_lab_preserves_precision
    # Lab should preserve precision through conversion
    decls = convert_and_get_declarations(
      '.test { color: lab(46.2775% -47.5621 48.5837); }',
      from: :lab, to: :lab
    )
    # Should maintain the same value
    assert_equal 'lab(46.2775% -47.5621 48.5837)', decls['color']
  end

  def test_lab_extreme_values_positive
    # Test with extreme but valid a and b values (near max ±125)
    decls = convert_and_get_declarations(
      '.test { color: lab(50% 125 125); }',
      from: :lab, to: :hex
    )
    # Will be outside sRGB gamut, should clamp appropriately
    assert_equal '#ff0000', decls['color']
  end

  def test_lab_extreme_values_negative
    # Both a and b can be negative
    decls = convert_and_get_declarations(
      '.test { color: lab(50% -50 -50); }',
      from: :lab, to: :hex
    )
    # Negative a (green), negative b (blue) = cyan-ish
    assert_equal '#008ecc', decls['color']
  end

  # Auto-detect format

  def test_auto_detect_lab_to_hex
    sheet = Cataract.parse_css(<<~CSS)
      .test { color: lab(50% 25 -25); }
    CSS
    sheet.convert_colors!(to: :hex)

    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    assert_equal '#9168a2', decls['color']
  end

  def test_mixed_formats_including_lab
    sheet = Cataract.parse_css(<<~CSS)
      .red { color: #ff0000; }
      .green { color: lab(46.2775% -47.5621 48.5837); }
      .blue { color: rgb(0, 0, 255); }
    CSS
    sheet.convert_colors!(to: :hex)

    rules_array = sheet.rules.map { |rule| rule }

    decls_red = Cataract::Declarations.new(rules_array[0].declarations)
    decls_green = Cataract::Declarations.new(rules_array[1].declarations)
    decls_blue = Cataract::Declarations.new(rules_array[2].declarations)

    assert_equal '#ff0000', decls_red['color']
    assert_equal '#008000', decls_green['color']
    assert_equal '#0000ff', decls_blue['color']
  end

  # Preservation tests (unparseable Lab values)

  def test_lab_with_calc_preserved
    decls = convert_and_get_declarations(
      '.test { color: lab(calc(50% + 10%) 20 30); }',
      to: :hex
    )
    # Should preserve calc() expressions
    assert_equal 'lab(calc(50% + 10%) 20 30)', decls['color']
  end

  def test_lab_with_none_preserved
    decls = convert_and_get_declarations(
      '.test { color: lab(none 20 30); }',
      to: :hex
    )
    # Should preserve 'none' keyword
    assert_equal 'lab(none 20 30)', decls['color']
  end

  def test_lab_with_var_preserved
    decls = convert_and_get_declarations(
      '.test { color: lab(var(--lightness) 20 30); }',
      to: :hex
    )
    # Should preserve CSS variables
    assert_equal 'lab(var(--lightness) 20 30)', decls['color']
  end
end
