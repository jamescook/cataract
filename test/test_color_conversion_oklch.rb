# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionOklch < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # W3C reference tests from CSS Color 4 spec

  def test_oklch_green_to_hex
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(51.975% 0.17686 142.495); }',
      from: :oklch, to: :hex
    )
    # green (sRGB #008000) converted to OKLCh
    assert_equal '#008000', decls['background-color']
  end

  def test_oklch_black_to_hex
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(0% 0 0); }',
      from: :oklch, to: :hex
    )
    # black (sRGB #000000)
    assert_equal '#000000', decls['background-color']
  end

  def test_oklch_white_to_hex
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(100% 0 0); }',
      from: :oklch, to: :hex
    )
    # white (sRGB #FFFFFF)
    assert_equal '#ffffff', decls['background-color']
  end

  def test_oklch_to_rgb_hue_0
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(50% 0.2 0); }',
      from: :oklch, to: :rgb
    )
    # oklch(50% 0.2 0) -> purplish red direction (W3C: rgb(70.492% 2.351% 37.073%))
    assert_equal 'rgb(70.492% 2.351% 37.073%)', decls['background-color']
  end

  def test_oklch_to_rgb_hue_270
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(50% 0.2 270); }',
      from: :oklch, to: :rgb
    )
    # oklch(50% 0.2 270) -> sky blue direction (W3C: rgb(23.056% 31.73% 82.628%))
    assert_equal 'rgb(23.056% 31.730% 82.628%)', decls['background-color']
  end

  def test_oklch_to_rgb_hue_160
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(80% 0.15 160); }',
      from: :oklch, to: :rgb
    )
    # oklch(80% 0.15 160) -> greenish cyan (W3C: rgb(32.022% 85.805% 61.147%))
    assert_equal 'rgb(32.022% 85.805% 61.147%)', decls['background-color']
  end

  def test_oklch_to_rgb_hue_345
    decls = convert_and_get_declarations(
      '.test { background-color: oklch(55% 0.15 345); }',
      from: :oklch, to: :rgb
    )
    # oklch(55% 0.15 345) -> reddish (W3C: rgb(67.293% 27.791% 52.28%))
    assert_equal 'rgb(67.293% 27.791% 52.280%)', decls['background-color']
  end

  # Conversion from other formats to OKLCh

  def test_hex_to_oklch_red
    decls = convert_and_get_declarations(
      '.test { color: #ff0000; }',
      from: :hex, to: :oklch
    )
    assert_equal 'oklch(0.6280 0.2577 29.234)', decls['color']
  end

  def test_rgb_to_oklch
    decls = convert_and_get_declarations(
      '.test { color: rgb(0 128 0); }',
      from: :rgb, to: :oklch
    )
    # green -> oklch
    assert_equal 'oklch(0.5198 0.1769 142.495)', decls['color']
  end

  def test_hsl_to_oklch
    decls = convert_and_get_declarations(
      '.test { color: hsl(240, 100%, 50%); }',
      from: :hsl, to: :oklch
    )
    # blue -> oklch
    assert_equal 'oklch(0.4520 0.3132 264.052)', decls['color']
  end

  # Alpha channel support

  def test_oklch_with_alpha
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 0 / 0.5); }',
      from: :oklch, to: :rgb
    )
    assert_match(/rgba?\(.* \/ 0\.5\)/, decls['color'])
  end

  def test_oklch_alpha_percentage
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 0 / 50%); }',
      from: :oklch, to: :rgb
    )
    assert_match(/rgba?\(.* \/ 0\.5\)/, decls['color'])
  end

  # Edge cases

  def test_oklch_zero_chroma_powerless_hue
    # When C=0, hue is powerless and should serialize as 0 or none
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 0 180); }',
      from: :oklch, to: :oklch
    )
    # Should normalize hue to 0 or none when chroma is 0
    assert_match(/oklch\(0\.5000 0\.0000 0/, decls['color'])
  end

  def test_oklch_negative_chroma_clamped
    # Negative chroma should be clamped to 0
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% -0.1 0); }',
      from: :oklch, to: :oklch
    )
    assert_match(/oklch\(0\.5000 0\.0000/, decls['color'])
  end

  def test_oklch_hue_normalization
    # Hue angles should normalize: 360deg = 0deg, 450deg = 90deg, etc.
    decls1 = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 360); }',
      from: :oklch, to: :rgb
    )
    decls2 = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 0); }',
      from: :oklch, to: :rgb
    )
    assert_equal decls1['color'], decls2['color']
  end

  def test_oklch_hue_450_equals_90
    decls1 = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 450); }',
      from: :oklch, to: :rgb
    )
    decls2 = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 90); }',
      from: :oklch, to: :rgb
    )
    assert_equal decls1['color'], decls2['color']
  end

  def test_oklch_negative_hue_normalization
    # -90deg should equal 270deg
    decls1 = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 -90); }',
      from: :oklch, to: :rgb
    )
    decls2 = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 270); }',
      from: :oklch, to: :rgb
    )
    assert_equal decls1['color'], decls2['color']
  end

  # Percentage syntax tests

  def test_oklch_lightness_percentage
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 0); }',
      from: :oklch, to: :oklch
    )
    assert_match(/oklch\(0\.5000/, decls['color'])
  end

  def test_oklch_chroma_percentage
    # C percentage: 0% = 0.0, 100% = 0.4
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 50% 0); }',
      from: :oklch, to: :oklch
    )
    # 50% of 0.4 = 0.2
    assert_match(/oklch\(0\.5000 0\.2000/, decls['color'])
  end

  # Auto-detection

  def test_auto_detect_oklch
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 0); }',
      to: :hex
    )
    assert_match(/^#[0-9a-f]{6}$/, decls['color'])
  end

  # Round-trip tests

  def test_oklch_round_trip
    original = '.test { color: oklch(0.6280 0.2577 29.234); }'
    sheet = Cataract.parse_css(original)
    sheet.convert_colors!(from: :oklch, to: :rgb)
    sheet.convert_colors!(from: :rgb, to: :oklch)
    decls = Cataract::Declarations.new(sheet.declarations)
    # Should be close to original (allow for rounding)
    assert_match(/oklch\(0\.628/, decls['color'])
  end

  # Multiple colors in one value

  def test_multiple_oklch_colors
    decls = convert_and_get_declarations(
      '.test { border-color: oklch(50% 0.2 0) oklch(50% 0.2 90) oklch(50% 0.2 180) oklch(50% 0.2 270); }',
      from: :oklch, to: :hex
    )
    colors = decls['border-color'].split(' ')
    assert_equal 4, colors.length
    colors.each { |color| assert_match(/^#[0-9a-f]{6}$/, color) }
  end

  # Modern vs legacy syntax

  def test_oklch_modern_syntax
    decls = convert_and_get_declarations(
      '.test { color: oklch(50% 0.2 0); }',
      from: :oklch, to: :rgb, variant: :modern
    )
    # Modern syntax: rgb(r g b) or rgb(r g b / a)
    assert_match(/rgb\(\d+\.?\d*% \d+\.?\d*% \d+\.?\d*%\)/, decls['color'])
  end

  # Invalid input handling

  def test_invalid_oklch_missing_values
    # Missing required values should keep original or raise error
    assert_raises(ArgumentError) do
      convert_and_get_declarations(
        '.test { color: oklch(50%); }',
        from: :oklch, to: :hex
      )
    end
  end

  def test_invalid_oklch_syntax
    assert_raises(ArgumentError) do
      convert_and_get_declarations(
        '.test { color: oklch(not a color); }',
        from: :oklch, to: :hex
      )
    end
  end
end
