# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Tests for CSS3 features
class TestCSS3Features < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
  end

  # ============================================================================
  # CSS3 Attribute Selectors
  # ============================================================================

  def test_attribute_starts_with
    # ^= matches if attribute value starts with specified string
    css = '[href^="http"] { color: blue }'
    @parser.parse(css)

    assert_includes @parser.selectors, '[href^="http"]'
  end

  def test_attribute_ends_with
    # $= matches if attribute value ends with specified string
    css = '[href$=".pdf"] { text-decoration: none }'
    @parser.parse(css)

    assert_includes @parser.selectors, '[href$=".pdf"]'
  end

  def test_attribute_contains
    # *= matches if attribute value contains specified substring
    css = '[class*="button"] { cursor: pointer }'
    @parser.parse(css)

    assert_includes @parser.selectors, '[class*="button"]'
  end
end
