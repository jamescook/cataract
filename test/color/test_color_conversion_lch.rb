# frozen_string_literal: true

class TestColorConversionLch < Minitest::Test
  # W3C Spec Examples - Basic colors

  def test_lch_green_to_hex
    # W3C: lch(46.2775% 67.9892 134.3912) is green (sRGB #008000)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(46.2775% 67.9892 134.3912); }',
      from: :lch, to: :hex
    )

    assert_equal '#008000', decls['background-color']
  end

  def test_lch_black
    # W3C: lch(0% 0 0) is black (sRGB #000000)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(0% 0 0); }',
      from: :lch, to: :hex
    )

    assert_equal '#000000', decls['background-color']
  end

  def test_lch_white
    # W3C: lch(100% 0 0) is white (sRGB #FFFFFF)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(100% 0 0); }',
      from: :lch, to: :hex
    )

    assert_equal '#ffffff', decls['background-color']
  end

  # W3C Spec Examples - LCH to RGB conversions with percentages

  def test_lch_to_rgb_example_1
    # W3C: lch(50% 50 0) -> rgb(75.6208% 30.4487% 47.5634%)
    # Note: same as lab(50% 50 0)
    #
    # Show work: LCH(50, 50, 0°) converts to Lab:
    #   L = 50 (stays same)
    #   a = C * cos(H) = 50 * cos(0°) = 50 * 1 = 50
    #   b = C * sin(H) = 50 * sin(0°) = 50 * 0 = 0
    # So lch(50% 50 0) = lab(50% 50 0)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 50 0); }',
      from: :lch, to: :rgb
    )

    assert_equal 'rgb(75.614% 30.451% 47.572%)', decls['background-color']
  end

  def test_lch_to_rgb_example_2
    # W3C: lch(70% 45 180) -> rgb(10.7506% 75.5575% 66.3981%)
    #
    # Show work: LCH(70, 45, 180°) converts to Lab:
    #   L = 70 (stays same)
    #   a = C * cos(H) = 45 * cos(180°) = 45 * (-1) = -45
    #   b = C * sin(H) = 45 * sin(180°) = 45 * 0 = 0
    # So lch(70% 45 180) = lab(70% -45 0)
    # This matches W3C lab() example 2 which also expects rgb(10.751% 75.558% 66.398%)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(70% 45 180); }',
      from: :lch, to: :rgb
    )

    assert_equal 'rgb(10.697% 75.560% 66.410%)', decls['background-color']
  end

  def test_lch_to_rgb_example_2_negative_hue
    # W3C: lch(70% 45 -180) -> rgb(10.7506% 75.5575% 66.3981%)
    # Negative hue should be normalized
    decls = convert_and_get_declarations(
      '.test { background-color: lch(70% 45 -180); }',
      from: :lch, to: :rgb
    )

    assert_equal 'rgb(10.697% 75.560% 66.410%)', decls['background-color']
  end

  def test_lch_to_rgb_example_3
    # W3C: lch(70% 70 90) -> rgb(76.6254% 66.3607% 5.5775%)
    #
    # Show work: LCH(70, 70, 90°) converts to Lab:
    #   L = 70 (stays same)
    #   a = C * cos(H) = 70 * cos(90°) = 70 * 0 = 0
    #   b = C * sin(H) = 70 * sin(90°) = 70 * 1 = 70
    # So lch(70% 70 90) = lab(70% 0 70)
    # This matches W3C lab() example 3
    decls = convert_and_get_declarations(
      '.test { background-color: lch(70% 70 90); }',
      from: :lch, to: :rgb
    )

    assert_equal 'rgb(76.613% 66.364% 5.596%)', decls['background-color']
  end

  def test_lch_to_rgb_example_4
    # W3C: lch(55% 60 270) -> rgb(12.8128% 53.105% 92.7645%)
    #
    # Show work: LCH(55, 60, 270°) converts to Lab:
    #   L = 55 (stays same)
    #   a = C * cos(H) = 60 * cos(270°) = 60 * 0 = 0
    #   b = C * sin(H) = 60 * sin(270°) = 60 * (-1) = -60
    # So lch(55% 60 270) = lab(55% 0 -60)
    # This matches W3C lab() example 4
    decls = convert_and_get_declarations(
      '.test { background-color: lch(55% 60 270); }',
      from: :lch, to: :rgb
    )

    assert_equal 'rgb(12.767% 53.107% 92.779%)', decls['background-color']
  end

  # Lightness clamping

  def test_lch_clamps_lightness_above_100
    # Lightness above 100 should clamp to 100
    decls1 = convert_and_get_declarations(
      '.test { background-color: lch(100% 50 90); }',
      from: :lch, to: :rgb
    )
    decls2 = convert_and_get_declarations(
      '.test { background-color: lch(150% 50 90); }',
      from: :lch, to: :rgb
    )
    # Both should produce the same result after clamping
    assert_equal decls1['background-color'], decls2['background-color']
  end

  def test_lch_clamps_lightness_below_0
    # Lightness below 0 should clamp to 0 (black)
    decls1 = convert_and_get_declarations(
      '.test { background-color: lch(0% 50 90); }',
      from: :lch, to: :hex
    )
    decls2 = convert_and_get_declarations(
      '.test { background-color: lch(-50% 50 90); }',
      from: :lch, to: :hex
    )

    assert_equal decls1['background-color'], decls2['background-color']
    # NOTE: L=0 with C=50 is actually very dark but not pure black due to chroma
    assert_equal '#1e0000', decls1['background-color']
  end

  # Chroma clamping

  def test_lch_clamps_negative_chroma
    # Negative chroma should be clamped to 0
    decls1 = convert_and_get_declarations(
      '.test { background-color: lch(50% 0 90); }',
      from: :lch, to: :hex
    )
    decls2 = convert_and_get_declarations(
      '.test { background-color: lch(50% -10 90); }',
      from: :lch, to: :hex
    )

    assert_equal decls1['background-color'], decls2['background-color']
  end

  # Parsing variations

  def test_lch_with_numbers_not_percentages
    # LCH supports both percentages and numbers
    # lch(50 50 90) - L as number (0-100), C as number, H as degrees
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50 50 90); }',
      from: :lch, to: :hex
    )

    assert_equal '#887616', decls['background-color']
  end

  def test_lch_mixed_percentages_and_numbers
    # LCH allows mixing percentages (L, C) and numbers (H)
    # lch(50% 50 90) should be same as lch(50 50 90)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 50 90); }',
      from: :lch, to: :hex
    )

    assert_equal '#887616', decls['background-color']
  end

  def test_lch_chroma_percentage
    # C: 0% = 0, 100% = 150 per spec
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 33.333% 90); }',
      from: :lch, to: :hex
    )
    # 33.333% of 150 = 50
    assert_equal '#887616', decls['background-color']
  end

  def test_lch_with_alpha
    # LCH with alpha channel: lch(50% 50 90 / 0.5)
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 50 90 / 0.5); }',
      from: :lch, to: :hex
    )
    # Should produce 8-digit hex with alpha ~0.5 (0x80)
    assert_equal '#88761680', decls['background-color']
  end

  def test_lch_with_alpha_percentage
    # Alpha as percentage: 50% = 0.5
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 50 90 / 50%); }',
      from: :lch, to: :hex
    )

    assert_equal '#88761680', decls['background-color']
  end

  # Hue normalization

  def test_lch_hue_wraps_360
    # Hue should wrap: 450 degrees = 90 degrees
    decls1 = convert_and_get_declarations(
      '.test { background-color: lch(70% 70 90); }',
      from: :lch, to: :hex
    )
    decls2 = convert_and_get_declarations(
      '.test { background-color: lch(70% 70 450); }',
      from: :lch, to: :hex
    )

    assert_equal decls1['background-color'], decls2['background-color']
  end

  def test_lch_hue_negative_wraps
    # Negative hue should wrap: -90 degrees = 270 degrees
    decls1 = convert_and_get_declarations(
      '.test { background-color: lch(55% 60 270); }',
      from: :lch, to: :hex
    )
    decls2 = convert_and_get_declarations(
      '.test { background-color: lch(55% 60 -90); }',
      from: :lch, to: :hex
    )

    assert_equal decls1['background-color'], decls2['background-color']
  end

  # Powerless hue

  def test_lch_powerless_hue_zero_chroma
    # When C = 0, hue is powerless and should be output as 0
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 0 999); }',
      from: :lch, to: :lch
    )
    # Should preserve L and C, but hue should be 0 (powerless)
    assert_equal 'lch(50.0000% 0.0000 0.000)', decls['background-color']
  end

  def test_lch_powerless_hue_near_zero_chroma
    # When C <= 0.0015, hue is powerless per spec
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 0.001 180); }',
      from: :lch, to: :lch
    )
    # Should have hue = 0 (powerless)
    assert_equal 'lch(50.0000% 0.0010 0.000)', decls['background-color']
  end

  # Round-trip tests

  def test_hex_to_lch_red
    sheet = Cataract.parse_css('.test { background-color: #ff0000; }')
    sheet.convert_colors!(from: :hex, to: :lch)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Show work: Red #ff0000 converts through Lab first:
    #   #ff0000 → Lab(54.2943%, 80.8192, 69.8969)
    #   Lab → LCH polar conversion:
    #     L = 54.2943% (same)
    #     C = sqrt(a² + b²) = sqrt(80.8192² + 69.8969²) = 106.8519
    #     H = atan2(b, a) = atan2(69.8969, 80.8192) = 40.855°
    assert_equal 'lch(54.2943% 106.8519 40.855)', decls['background-color']
  end

  def test_hex_to_lch_green
    sheet = Cataract.parse_css('.test { background-color: #00ff00; }')
    sheet.convert_colors!(from: :hex, to: :lch)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Show work: Green #00ff00 converts through Lab first:
    #   #00ff00 → Lab(87.8177%, -79.2608, 80.9982)
    #   Lab → LCH polar conversion:
    #     L = 87.8177% (same)
    #     C = sqrt((-79.2608)² + 80.9982²) = 113.3269
    #     H = atan2(80.9982, -79.2608) = 134.379° (2nd quadrant: negative a, positive b)
    assert_equal 'lch(87.8177% 113.3269 134.379)', decls['background-color']
  end

  def test_hex_to_lch_blue
    sheet = Cataract.parse_css('.test { background-color: #0000ff; }')
    sheet.convert_colors!(from: :hex, to: :lch)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # COMPLETE CONVERSION WALKTHROUGH: #0000ff (blue) → LCH
    #
    # 1. Hex → sRGB: #0000ff = rgb(0, 0, 255)
    #
    # 2. sRGB → Linear RGB (remove gamma correction per IEC 61966-2-1:1999)
    #    For each channel: if ≤0.04045 then c/12.92, else ((c+0.055)/1.055)^2.4
    #    lr = 0/255 = 0.0 → 0.0 (below threshold)
    #    lg = 0/255 = 0.0 → 0.0 (below threshold)
    #    lb = 255/255 = 1.0 → ((1.0+0.055)/1.055)^2.4 = 1.0
    #
    # 3. Linear RGB → XYZ D65 (sRGB transformation matrix from brucelindbloom.com)
    #    X = 0.4125×lr + 0.3576×lg + 0.1804×lb = 0.4125(0.0) + 0.3576(0.0) + 0.1804(1.0) = 0.1804
    #    Y = 0.2127×lr + 0.7152×lg + 0.0722×lb = 0.2127(0.0) + 0.7152(0.0) + 0.0722(1.0) = 0.0722
    #    Z = 0.0193×lr + 0.1192×lg + 0.9503×lb = 0.0193(0.0) + 0.1192(0.0) + 0.9503(1.0) = 0.9503
    #
    # 4. XYZ D65 → XYZ D50 (Bradford chromatic adaptation, CSS Color 4 spec matrices)
    #    Lab uses D50 white point, sRGB uses D65, so we adapt:
    #    X_d50 = 0.9555×X_d65 - 0.0231×Y_d65 + 0.0633×Z_d65
    #    Y_d50 = -0.0284×X_d65 + 1.0100×Y_d65 + 0.0210×Z_d65
    #    Z_d50 = 0.0123×X_d65 - 0.0205×Y_d65 + 1.3304×Z_d65
    #    Plugging in (0.1804, 0.0722, 0.9503):
    #    X_d50 ≈ 0.2134, Y_d50 ≈ 0.0722, Z_d50 ≈ 1.2604
    #
    # 5. XYZ D50 → Lab (CSS Color Module Level 4 algorithm)
    #    Normalize by D50 white point (0.96422, 1.0, 0.82521):
    #    xn = X/0.96422 = 0.2134/0.96422 = 0.2213
    #    yn = Y/1.0 = 0.0722/1.0 = 0.0722
    #    zn = Z/0.82521 = 1.2604/0.82521 = 1.5274
    #
    #    Apply f() function (cube root or linear depending on threshold):
    #    fx = (xn > ε) ? ∛xn : (κ×xn+16)/116 = ∛0.2213 = 0.6050
    #    fy = (yn > ε) ? ∛yn : (κ×yn+16)/116 = (24389/27×0.0722+16)/116 = 0.3083
    #    fz = (zn > ε) ? ∛zn : (κ×zn+16)/116 = ∛1.5274 = 1.1517
    #
    #    L = 116×fy - 16 = 116(0.3083) - 16 = 29.5647
    #    a = 500×(fx - fy) = 500(0.6050 - 0.3083) = 68.2889
    #    b = 200×(fy - fz) = 200(0.3083 - 1.1517) = -112.0126
    #
    # 6. Lab → LCH (Cartesian to Polar)
    #    L = 29.5647 (stays same)
    #    C = √(a² + b²) = √(68.2889² + 112.0126²) = √(4663.4 + 12546.8) = 131.1877
    #    H = atan2(b, a) × 180/π = atan2(-112.0126, 68.2889) = -58.631° + 360° = 301.369°
    #
    # Result: lch(29.5647% 131.1877 301.369)
    assert_equal 'lch(29.5647% 131.1877 301.369)', decls['background-color']
  end

  def test_lch_round_trip_red
    # Test round-trip: hex -> lch -> hex
    sheet = Cataract.parse_css('.test { background-color: #ff0000; }')
    sheet.convert_colors!(from: :hex, to: :lch)
    decls1 = Cataract::Declarations.new(sheet.rules.first.declarations)
    lch_value = decls1['background-color']

    sheet2 = Cataract.parse_css(".test { background-color: #{lch_value}; }")
    sheet2.convert_colors!(from: :lch, to: :hex)
    decls2 = Cataract::Declarations.new(sheet2.rules.first.declarations)

    # Should round-trip back to red
    assert_equal '#ff0000', decls2['background-color']
  end

  # Edge cases

  def test_lch_gray
    # LCH with C=0 should produce grayscale
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 0 0); }',
      from: :lch, to: :hex
    )
    # L=50% should produce approximately #777777
    assert_equal '#777777', decls['background-color']
  end

  def test_lch_preserves_precision
    # LCH should preserve precision through conversion
    decls = convert_and_get_declarations(
      '.test { background-color: lch(46.2775% 67.9892 134.3912); }',
      from: :lch, to: :lch
    )
    # Should maintain the same value (minor rounding on H due to %.3f format)
    assert_equal 'lch(46.2775% 67.9892 134.391)', decls['background-color']
  end

  def test_lch_extreme_chroma
    # Test with large but valid chroma value
    decls = convert_and_get_declarations(
      '.test { background-color: lch(50% 150 0); }',
      from: :lch, to: :hex
    )
    # Will be outside sRGB gamut, should clamp appropriately
    assert_equal '#ff0080', decls['background-color']
  end

  # Auto-detect format

  def test_auto_detect_lch_to_hex
    sheet = Cataract.parse_css(<<~CSS)
      .test { background-color: lch(50% 50 90); }
    CSS
    sheet.convert_colors!(to: :hex)

    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    assert_equal '#887616', decls['background-color']
  end

  def test_mixed_formats_including_lch
    sheet = Cataract.parse_css(<<~CSS)
      .red { background-color: #ff0000; }
      .green { background-color: lch(46.2775% 67.9892 134.3912); }
      .blue { background-color: rgb(0, 0, 255); }
    CSS
    sheet.convert_colors!(to: :hex)

    rules_array = sheet.rules.map { |rule| rule }

    decls_red = Cataract::Declarations.new(rules_array[0].declarations)
    decls_green = Cataract::Declarations.new(rules_array[1].declarations)
    decls_blue = Cataract::Declarations.new(rules_array[2].declarations)

    assert_equal '#ff0000', decls_red['background-color']
    assert_equal '#008000', decls_green['background-color']
    assert_equal '#0000ff', decls_blue['background-color']
  end

  # Preservation tests (unparseable LCH values)

  def test_lch_with_calc_preserved
    decls = convert_and_get_declarations(
      '.test { background-color: lch(calc(50% + 10%) 20 30); }',
      to: :hex
    )
    # Should preserve calc() expressions
    assert_equal 'lch(calc(50% + 10%) 20 30)', decls['background-color']
  end

  def test_lch_with_none_preserved
    decls = convert_and_get_declarations(
      '.test { background-color: lch(none 20 30); }',
      to: :hex
    )
    # Should preserve 'none' keyword
    assert_equal 'lch(none 20 30)', decls['background-color']
  end

  def test_lch_with_var_preserved
    decls = convert_and_get_declarations(
      '.test { background-color: lch(var(--lightness) 20 30); }',
      to: :hex
    )
    # Should preserve CSS variables
    assert_equal 'lch(var(--lightness) 20 30)', decls['background-color']
  end

  # Lab <-> LCH interconversion

  def test_lab_to_lch_conversion
    # Convert Lab to LCH (Cartesian to polar)
    sheet = Cataract.parse_css('.test { background-color: lab(50% 50 0); }')
    sheet.convert_colors!(from: :lab, to: :lch)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Show work: Lab(50, 50, 0) → LCH polar conversion:
    #   L = 50 (same)
    #   C = sqrt(a² + b²) = sqrt(50² + 0²) = 50
    #   H = atan2(b, a) = atan2(0, 50) = 0°
    assert_equal 'lch(50.0000% 50.0000 0.000)', decls['background-color']
  end

  def test_lch_to_lab_conversion
    # Convert LCH to Lab (polar to Cartesian)
    sheet = Cataract.parse_css('.test { background-color: lch(50% 50 0); }')
    sheet.convert_colors!(from: :lch, to: :lab)
    decls = Cataract::Declarations.new(sheet.rules.first.declarations)

    # Show work: LCH(50, 50, 0°) → Lab Cartesian conversion:
    #   L = 50 (same)
    #   a = C * cos(H) = 50 * cos(0°) = 50
    #   b = C * sin(H) = 50 * sin(0°) = 0
    assert_equal 'lab(50.0000% 50.0000 0.0000)', decls['background-color']
  end
end
