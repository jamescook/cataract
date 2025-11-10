# frozen_string_literal: true

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
    @sheet.add_block(css)

    assert_equal 1, @sheet.rules.size
    assert_equal 1, @sheet.rules.first.declarations.size

    assert_has_selector '[href^="http"]', @sheet
  end

  def test_attribute_ends_with
    # $= matches if attribute value ends with specified string
    css = '[href$=".pdf"] { text-decoration: none }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.rules.size
    assert_equal 1, @sheet.rules.first.declarations.size
    assert_has_selector '[href$=".pdf"]', @sheet
  end

  def test_attribute_contains
    # *= matches if attribute value contains specified substring
    css = '[class*="button"] { cursor: pointer }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.rules.size
    assert_equal 1, @sheet.rules.first.declarations.size
    assert_has_selector '[class*="button"]', @sheet
  end
end
