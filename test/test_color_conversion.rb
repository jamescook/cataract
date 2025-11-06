# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversion < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Edge cases and format-agnostic tests

  # Error handling tests

  def test_hex_to_rgb_invalid_length
    stylesheet = Cataract.parse_css('.test { color: #ff }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_invalid_five_digit
    stylesheet = Cataract.parse_css('.test { color: #ffff0 }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_invalid_characters
    stylesheet = Cataract.parse_css('.test { color: #gggggg }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_just_hash_symbol
    stylesheet = Cataract.parse_css('.test { color: # }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_hex_to_rgb_malformed_with_spaces
    stylesheet = Cataract.parse_css('.test { color: #ff 00 00 }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :hex, to: :rgb)
    end
    assert_match(/invalid hex color/i, error.message)
  end

  def test_rgb_to_hex_out_of_range_high
    stylesheet = Cataract.parse_css('.test { color: rgb(300, 0, 0) }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :rgb, to: :hex)
    end
    assert_match(/invalid rgb|must be 0-255/i, error.message)
  end

  def test_rgb_to_hex_out_of_range_negative
    stylesheet = Cataract.parse_css('.test { color: rgb(-10, 0, 0) }')
    error = assert_raises(Cataract::ColorConversionError) do
      stylesheet.convert_colors!(from: :rgb, to: :hex)
    end
    assert_match(/invalid rgb|must be 0-255/i, error.message)
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

  def test_missing_to_argument
    stylesheet = Cataract.parse_css('.test { color: #fff }')
    error = assert_raises(ArgumentError) do
      stylesheet.convert_colors!
    end
    assert_match(/missing keyword.*:to/i, error.message)
  end

  # Format-agnostic behavior tests

  def test_hex_to_rgb_returns_self
    stylesheet = Cataract.parse_css('.test { color: #fff }')
    result = stylesheet.convert_colors!(from: :hex, to: :rgb)
    assert_equal stylesheet, result
  end

  def test_hex_to_rgb_preserves_non_hex_colors
    decls = convert_and_get_declarations(<<~CSS, from: :hex, to: :rgb, variant: :modern)
      .test {
        color: blue;
        background: #ff0000;
        border-color: hsl(120, 100%, 50%);
      }
    CSS
    # Should not convert non-hex colors
    assert_equal 'blue', decls['color']
    # background shorthand expands to background-color
    assert_equal 'rgb(255 0 0)', decls['background-color']
    assert_equal 'hsl(120, 100%, 50%)', decls['border-color']
  end

  def test_hex_to_rgb_mixed_hex_and_non_hex
    decls = convert_and_get_declarations(<<~CSS, from: :hex, to: :rgb, variant: :modern)
      .test {
        color: #ff0000;
        background-color: blue;
        border-color: rgb(0, 255, 0);
      }
    CSS

    assert_equal 'rgb(255 0 0)', decls['color']
    assert_equal 'blue', decls['background-color']
    assert_equal 'rgb(0, 255, 0)', decls['border-color']
  end

  def test_hex_to_rgb_in_shorthand_background
    decls = convert_and_get_declarations(
      '.test { background: #fff url(img.png) no-repeat }',
      from: :hex, to: :rgb, variant: :modern
    )
    # Should convert the hex color within the shorthand value
    assert_equal 'rgb(255 255 255) url(img.png) no-repeat', decls['background']
  end

  def test_convert_colors_with_media_queries
    sheet = Cataract.parse_css(<<~CSS)
      .test { color: #ff0000; }
      @media (min-width: 768px) {
        .test { color: #00ff00; }
      }
    CSS
    sheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)

    # Get rules from default media group
    default_rules = []
    sheet.rules.each { |rule| default_rules << rule }

    decls = Cataract::Declarations.new(default_rules[0].declarations)
    assert_equal 'rgb(255 0 0)', decls['color']

    # TODO: Add assertions for media query rules once we can access them
  end

  def test_explicit_any_format
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :any, to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['color']
  end

  # Multi-value property tests

  def test_outline_color_single_value
    decls = convert_and_get_declarations(
      '.test { outline-color: #ff0000; }',
      to: :rgb, variant: :modern
    )
    assert_equal 'rgb(255 0 0)', decls['outline-color']
  end

  def test_text_shadow_with_color
    # text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5)
    decls = convert_and_get_declarations(
      '.test { text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5); }',
      to: :hex
    )
    assert_equal '2px 2px 4px #00000080', decls['text-shadow']
  end

  # URL and gradient handling

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
end
