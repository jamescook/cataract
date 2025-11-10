# frozen_string_literal: true

class TestColorConversionHsl < Minitest::Test
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

  def test_rgb_to_hsl
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      from: :rgb, to: :hsl
    )

    assert_equal 'hsl(0, 100%, 50%)', decls['color']
  end

  def test_hwb_to_hsl
    decls = convert_and_get_declarations(
      '.test { color: hwb(0 0% 0%) }',
      from: :hwb, to: :hsl
    )

    assert_equal 'hsl(0, 100%, 50%)', decls['color']
  end

  def test_auto_detect_mixed_to_hsl
    sheet = Cataract.parse_css(<<~CSS)
      .red { color: #ff0000 }
      .green { color: rgb(0, 255, 0) }
      .blue { color: hwb(240 0% 0%) }
    CSS
    sheet.convert_colors!(to: :hsl)

    rules_array = sheet.rules.map { |rule| rule }

    decls_red = Cataract::Declarations.new(rules_array[0].declarations)
    decls_green = Cataract::Declarations.new(rules_array[1].declarations)
    decls_blue = Cataract::Declarations.new(rules_array[2].declarations)

    assert_equal 'hsl(0, 100%, 50%)', decls_red['color']
    assert_equal 'hsl(120, 100%, 50%)', decls_green['color']
    assert_equal 'hsl(240, 100%, 50%)', decls_blue['color']
  end

  def test_hsla_alias_uses_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :hsla
    )
    # :hsla should produce hsl() with alpha
    assert_match(/^hsl\(\d+, \d+%, \d+%, 0\.50/, decls['color'])
  end
end
