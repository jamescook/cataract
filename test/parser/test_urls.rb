# frozen_string_literal: true

require_relative '../test_helper'

# Tests for URL parsing in CSS values
class TestUrls < Minitest::Test
  # ============================================================================
  # Basic URL parsing
  # ============================================================================

  def test_simple_url
    css = "body { background: url('image.png') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('image.png')" }, rule)
  end

  def test_url_with_double_quotes
    css = 'body { background: url("image.png") }'
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: 'url("image.png")' }, rule)
  end

  def test_url_without_quotes
    css = 'body { background: url(image.png) }'
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: 'url(image.png)' }, rule)
  end

  # ============================================================================
  # Data URIs with semicolons
  # ============================================================================

  def test_data_uri_with_semicolon_single_quotes
    css = "body { background: url('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property(
      { background: "url('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA')" },
      rule
    )
  end

  def test_data_uri_with_semicolon_double_quotes
    css = 'body { background: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA") }'
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property(
      { background: 'url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA")' },
      rule
    )
  end

  def test_data_uri_svg_with_semicolons
    # Real-world example from Bootstrap
    css = '.icon { background-image: url("data:image/svg+xml,%3csvg xmlns=\'http://www.w3.org/2000/svg\' viewBox=\'0 0 16 16\'%3e%3cpath fill=\'none\' stroke=\'%23343a40\' stroke-linecap=\'round\' stroke-linejoin=\'round\' stroke-width=\'2\' d=\'M2 5l6 6 6-6\'/%3e%3c/svg%3e") }'
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first
    decl = rule.declarations.find { |d| d.property == 'background-image' }

    # The entire data URI should be preserved
    assert decl, 'Expected to find background-image declaration'
    assert_equal 'background-image', decl.property
    assert decl.value.start_with?('url("data:image/svg+xml,'), "Expected value to start with url(), got: #{decl.value}"
    assert decl.value.end_with?('")'), "Expected value to end with \"), got: #{decl.value}"
  end

  def test_multiple_semicolons_in_data_uri
    css = "body { background: url('data:text/css;charset=utf-8;base64,Ym9keSB7IGNvbG9yOiByZWQ7IH0=') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property(
      { background: "url('data:text/css;charset=utf-8;base64,Ym9keSB7IGNvbG9yOiByZWQ7IH0=')" },
      rule
    )
  end

  # ============================================================================
  # Multiple declarations with URLs
  # ============================================================================

  def test_multiple_url_declarations
    css = <<~CSS
      .icon {
        background: url('data:image/png;base64,abc123');
        cursor: url('pointer.cur'), auto;
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('data:image/png;base64,abc123')" }, rule)
    assert_has_property({ cursor: "url('pointer.cur'), auto" }, rule)
  end

  def test_declaration_after_data_uri
    # Ensure the semicolon in data URI doesn't terminate the declaration early
    css = "body { background: url('data:image/png;base64,abc'); color: red }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_equal 2, rule.declarations.size, 'Expected 2 declarations'
    assert_has_property({ background: "url('data:image/png;base64,abc')" }, rule)
    assert_has_property({ color: 'red' }, rule)
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  def test_empty_url
    css = "body { background: url('') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('')" }, rule)
  end

  def test_url_with_spaces
    css = "body { background: url('path/to/my image.png') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('path/to/my image.png')" }, rule)
  end

  def test_url_with_parentheses_in_path
    # Parentheses must be escaped or quoted
    css = "body { background: url('image(1).png') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('image(1).png')" }, rule)
  end

  def test_multiple_urls_in_single_value
    css = ".icon { background-image: url('a.png'), url('b.png') }"
    sheet = Cataract::Stylesheet.parse(css)

    rule = sheet.rules.first

    assert_has_property({ 'background-image': "url('a.png'), url('b.png')" }, rule)
  end

  def test_url_in_font_face_src
    css = "@font-face { font-family: 'MyFont'; src: url('font.woff2') format('woff2'), url('font.woff') format('woff'); }"
    sheet = Cataract::Stylesheet.parse(css)

    font_rule = sheet.rules.first
    # @font-face is an AtRule, which stores declarations in content
    assert_has_property(
      { src: "url('font.woff2') format('woff2'), url('font.woff') format('woff')" },
      font_rule
    )
  end
end
