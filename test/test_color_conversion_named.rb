# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionNamed < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Tests for named color conversions - selected favorites

  def test_named_to_hex_red
    decls = convert_and_get_declarations(
      '.test { color: red; }',
      from: :named, to: :hex
    )

    assert_equal '#ff0000', decls['color']
  end

  def test_named_to_hex_blue
    decls = convert_and_get_declarations(
      '.test { color: blue; }',
      from: :named, to: :hex
    )

    assert_equal '#0000ff', decls['color']
  end

  def test_named_to_hex_green
    decls = convert_and_get_declarations(
      '.test { color: green; }',
      from: :named, to: :hex
    )
    # green is #008000, not #00ff00 (that's lime)
    assert_equal '#008000', decls['color']
  end

  def test_named_to_hex_rebeccapurple
    decls = convert_and_get_declarations(
      '.test { color: rebeccapurple; }',
      from: :named, to: :hex
    )
    # rebeccapurple was added in CSS4 to honor Eric Meyer's daughter
    assert_equal '#663399', decls['color']
  end

  def test_named_to_hex_cornflowerblue
    decls = convert_and_get_declarations(
      '.test { color: cornflowerblue; }',
      from: :named, to: :hex
    )

    assert_equal '#6495ed', decls['color']
  end

  def test_named_to_hex_hotpink
    decls = convert_and_get_declarations(
      '.test { color: hotpink; }',
      from: :named, to: :hex
    )

    assert_equal '#ff69b4', decls['color']
  end

  def test_named_to_hex_teal
    decls = convert_and_get_declarations(
      '.test { color: teal; }',
      from: :named, to: :hex
    )

    assert_equal '#008080', decls['color']
  end

  def test_named_to_hex_lime
    decls = convert_and_get_declarations(
      '.test { color: lime; }',
      from: :named, to: :hex
    )
    # lime is #00ff00 (pure green in RGB)
    assert_equal '#00ff00', decls['color']
  end

  def test_named_to_hex_papayawhip
    decls = convert_and_get_declarations(
      '.test { color: papayawhip; }',
      from: :named, to: :hex
    )

    assert_equal '#ffefd5', decls['color']
  end

  def test_named_to_hex_darkslateblue
    decls = convert_and_get_declarations(
      '.test { color: darkslateblue; }',
      from: :named, to: :hex
    )

    assert_equal '#483d8b', decls['color']
  end

  # Test case insensitivity
  def test_named_case_insensitive
    decls = convert_and_get_declarations(
      '.test { color: DarkSlateBlue; }',
      from: :named, to: :hex
    )

    assert_equal '#483d8b', decls['color']
  end

  # Test gray vs grey aliases
  def test_gray_grey_alias
    decls1 = convert_and_get_declarations(
      '.test { color: gray; }',
      from: :named, to: :hex
    )
    decls2 = convert_and_get_declarations(
      '.test { color: grey; }',
      from: :named, to: :hex
    )

    assert_equal '#808080', decls1['color']
    assert_equal '#808080', decls2['color']
  end

  # Test conversion to RGB
  def test_named_to_rgb
    decls = convert_and_get_declarations(
      '.test { color: red; }',
      from: :named, to: :rgb
    )

    assert_equal 'rgb(255 0 0)', decls['color']
  end

  # Test conversion to HSL
  def test_named_to_hsl
    decls = convert_and_get_declarations(
      '.test { color: red; }',
      from: :named, to: :hsl
    )

    assert_equal 'hsl(0, 100%, 50%)', decls['color']
  end

  # Test conversion to Oklab
  def test_named_to_oklab
    decls = convert_and_get_declarations(
      '.test { color: red; }',
      from: :named, to: :oklab
    )

    assert_equal 'oklab(0.6280 0.2249 0.1258)', decls['color']
  end

  # Test auto-detection and conversion
  def test_auto_detect_named_to_hex
    decls = convert_and_get_declarations(
      '.test { color: teal; }',
      to: :hex
    )

    assert_equal '#008080', decls['color']
  end

  # Test multiple named colors in one value
  def test_multiple_named_colors
    decls = convert_and_get_declarations(
      '.test { border-color: red blue green yellow; }',
      from: :named, to: :hex
    )

    assert_equal '#ff0000 #0000ff #008000 #ffff00', decls['border-color']
  end

  # Test invalid color name - should remain unchanged
  def test_invalid_color_name_not_converted
    decls = convert_and_get_declarations(
      '.test { color: vomitgreen; }',
      from: :named, to: :hex
    )
    # Invalid color names are not converted, remain as-is
    assert_equal 'vomitgreen', decls['color']
  end

  # Test that malformed color names remain unchanged
  def test_malformed_color_name_safe
    decls = convert_and_get_declarations(
      '.test { color: notacolor; }',
      from: :named, to: :hex
    )
    # Invalid color names are not converted, remain as-is
    assert_equal 'notacolor', decls['color']
  end
end
