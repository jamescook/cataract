# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionPreserve < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Test that unsupported/modern CSS color syntax is preserved unchanged
  # This ensures the converter doesn't break on CSS it doesn't understand

  def test_preserve_calc_expression
    decls = convert_and_get_declarations(
      '.test { color: calc(255 * 0.5); }',
      to: :hex
    )

    assert_equal 'calc(255 * 0.5)', decls['color']
  end

  def test_preserve_lab_with_calc
    decls = convert_and_get_declarations(
      '.test { color: lab(calc(50% + 10%) 20 30); }',
      to: :hex
    )

    assert_equal 'lab(calc(50% + 10%) 20 30)', decls['color']
  end

  def test_preserve_lab_with_none
    decls = convert_and_get_declarations(
      '.test { color: lab(none 20 30); }',
      to: :hex
    )

    assert_equal 'lab(none 20 30)', decls['color']
  end

  def test_preserve_oklch_with_none
    decls = convert_and_get_declarations(
      '.test { color: oklch(none none none); }',
      to: :hex
    )

    assert_equal 'oklch(none none none)', decls['color']
  end

  def test_preserve_currentcolor
    decls = convert_and_get_declarations(
      '.test { color: currentcolor; }',
      to: :hex
    )

    assert_equal 'currentcolor', decls['color']
  end

  def test_preserve_transparent
    decls = convert_and_get_declarations(
      '.test { color: transparent; }',
      to: :hex
    )

    assert_equal 'transparent', decls['color']
  end

  def test_color_mix_converts_nested_colors
    # color-mix() itself is preserved, but named colors inside are converted
    decls = convert_and_get_declarations(
      '.test { color: color-mix(in lch, peru 40%, palegoldenrod); }',
      to: :hex
    )
    # Named colors inside get converted to hex
    assert_equal 'color-mix(in lch, #cd853f 40%, #eee8aa)', decls['color']
  end

  def test_preserve_relative_color_syntax
    # CSS Color 5 relative color syntax
    decls = convert_and_get_declarations(
      '.test { color: rgb(from blue r g b / 0.5); }',
      to: :hex
    )
    # The "from" keyword makes this unsupported, should preserve
    assert_equal 'rgb(from blue r g b / 0.5)', decls['color']
  end

  def test_preserve_unknown_function
    decls = convert_and_get_declarations(
      '.test { color: future-color-function(1 2 3); }',
      to: :hex
    )

    assert_equal 'future-color-function(1 2 3)', decls['color']
  end

  def test_preserve_multiple_calc_in_value
    decls = convert_and_get_declarations(
      '.test { border-color: calc(100% - 10%) transparent #ff0000 calc(50px + 2em); }',
      to: :hex
    )
    # Should convert #ff0000 and transparent, preserve calc()
    assert_equal 'calc(100% - 10%) transparent #ff0000 calc(50px + 2em)', decls['border-color']
  end
end
