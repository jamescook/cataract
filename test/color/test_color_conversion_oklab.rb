# frozen_string_literal: true

class TestColorConversionOklab < Minitest::Test
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

    # COMPLETE CONVERSION WALKTHROUGH: #0000ff (blue) → Oklab
    #
    # 1. Hex → sRGB: #0000ff = rgb(0, 0, 255)
    #
    # 2. sRGB → Linear RGB (remove gamma correction per IEC 61966-2-1:1999)
    #    For each channel: if ≤0.04045 then c/12.92, else ((c+0.055)/1.055)^2.4
    #    lr = 0/255 = 0.0 → 0.0 (below threshold)
    #    lg = 0/255 = 0.0 → 0.0 (below threshold)
    #    lb = 255/255 = 1.0 → ((1.0+0.055)/1.055)^2.4 = 1.0
    #
    # 3. Linear RGB → LMS cone response (matrix M₁ from Oklab spec)
    #    This approximates human cone cell response to light
    #    l = 0.4122×lr + 0.5363×lg + 0.0514×lb = 0.4122(0.0) + 0.5363(0.0) + 0.0514(1.0) = 0.0514
    #    m = 0.2119×lr + 0.6807×lg + 0.1074×lb = 0.2119(0.0) + 0.6807(0.0) + 0.1074(1.0) = 0.1074
    #    s = 0.0883×lr + 0.2817×lg + 0.6300×lb = 0.0883(0.0) + 0.2817(0.0) + 0.6300(1.0) = 0.6300
    #
    # 4. Apply cube root nonlinearity (makes space more perceptually uniform)
    #    l' = ∛l = ∛0.0514 = 0.3718
    #    m' = ∛m = ∛0.1074 = 0.4753
    #    s' = ∛s = ∛0.6300 = 0.8570
    #
    # 5. Transform to Lab coordinates (matrix M₂ from Oklab spec)
    #    This gives us the final perceptually uniform Oklab coordinates
    #    L = 0.2105×l' + 0.7936×m' - 0.0041×s' = 0.2105(0.3718) + 0.7936(0.4753) - 0.0041(0.8570)
    #      = 0.0783 + 0.3771 - 0.0035 = 0.4520
    #    a = 1.9780×l' - 2.4286×m' + 0.4506×s' = 1.9780(0.3718) - 2.4286(0.4753) + 0.4506(0.8570)
    #      = 0.7354 - 1.1542 + 0.3862 = -0.0325
    #    b = 0.0259×l' + 0.7828×m' - 0.8087×s' = 0.0259(0.3718) + 0.7828(0.4753) - 0.8087(0.8570)
    #      = 0.0096 + 0.3720 - 0.6930 = -0.3115
    #
    # Result: oklab(0.4520 -0.0325 -0.3115)
    # - L=0.452: Blue is moderately dark (lighter than Lab's 0.296)
    # - a=-0.033: Very slightly greenish (near neutral)
    # - b=-0.312: Strongly blue (negative b = blue direction)
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
    decls1 = Cataract::Declarations.new(sheet.rules.first.declarations)
    oklab_value = decls1['color']

    sheet2 = Cataract.parse_css(".test { color: #{oklab_value} }")
    sheet2.convert_colors!(from: :oklab, to: :hex)
    decls2 = Cataract::Declarations.new(sheet2.rules.first.declarations)

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
