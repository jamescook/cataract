# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Tests for CSS3 features
class TestCSS3Features < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # ============================================================================
  # CSS3 Attribute Selectors
  # ============================================================================

  def test_attribute_starts_with
    # ^= matches if attribute value starts with specified string
    css = '[href^="http"] { color: blue }'
    @sheet.parse(css)

    assert_includes @sheet.selectors, '[href^="http"]'
  end

  def test_attribute_ends_with
    # $= matches if attribute value ends with specified string
    css = '[href$=".pdf"] { text-decoration: none }'
    @sheet.parse(css)

    assert_includes @sheet.selectors, '[href$=".pdf"]'
  end

  def test_attribute_contains
    # *= matches if attribute value contains specified substring
    css = '[class*="button"] { cursor: pointer }'
    @sheet.parse(css)

    assert_includes @sheet.selectors, '[class*="button"]'
  end
end
