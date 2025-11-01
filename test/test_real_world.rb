# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Real-world CSS parsing tests using actual framework CSS files
class TestRealWorld < Minitest::Test
  def setup
    @bootstrap_css = File.read(File.expand_path('fixtures/bootstrap.css', __dir__))
  end

  def test_bootstrap_parses_successfully
    # Real-world CSS from Bootstrap 5
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    # Bootstrap 5.0.2 should have exactly 2807 rules (matches css_parser)
    # Note: Rules are split by selector, so "h1, h2 { }" becomes 2 rules
    assert_equal 2807, sheet.size, 'Should parse Bootstrap CSS with correct rule count'
  end

  def test_bootstrap_standalone_pseudo_elements
    # Bootstrap uses standalone pseudo-elements like ::-moz-focus-inner
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    # Find the ::-moz-focus-inner rule
    found = false
    sheet.each_selector do |selector, declarations, _specificity, _media_types|
      next unless selector == '::-moz-focus-inner'

      found = true

      assert_includes declarations, 'padding: 0', 'Should have padding declaration'
      assert_includes declarations, 'border-style: none', 'Should have border-style declaration'
    end

    assert found, 'Should find ::-moz-focus-inner selector'
  end

  def test_bootstrap_pseudo_class_after_pseudo_element
    # Bootstrap uses selectors like .form-range::-webkit-slider-thumb:active
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    # Find webkit slider thumb with :active pseudo-class
    found = false
    sheet.each_selector do |selector, declarations, _specificity, _media_types|
      next unless selector.include?('webkit-slider-thumb:active')

      found = true

      assert_includes declarations, 'background-color:', 'Should have background-color'
    end

    assert found, 'Should find ::-webkit-slider-thumb:active selector'
  end

  def test_bootstrap_vendor_prefixed_pseudo_elements
    # Bootstrap uses vendor-prefixed pseudo-elements
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    vendor_pseudo_elements = []
    sheet.each_selector do |selector, _declarations, _specificity, _media_types|
      vendor_pseudo_elements << selector if selector.include?('::-webkit-') || selector.include?('::-moz-')
    end

    assert_predicate vendor_pseudo_elements.length, :positive?, 'Should find vendor-prefixed pseudo-elements'

    # Check for specific ones we know are in Bootstrap
    assert vendor_pseudo_elements.any? { |s| s.include?('webkit-slider-thumb') },
           'Should find -webkit-slider-thumb'
    assert vendor_pseudo_elements.any? { |s| s.include?('moz-focus-inner') },
           'Should find -moz-focus-inner'
  end

  def test_bootstrap_media_queries
    # Bootstrap uses extensive media queries
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    # Count rules with media types
    media_rules = 0
    screen_rules = 0

    sheet.each_selector do |_selector, _declarations, _specificity, media_types|
      unless media_types == [:all]
        media_rules += 1
        screen_rules += 1 if media_types.include?(:screen)
      end
    end

    assert_predicate media_rules, :positive?, "Bootstrap should have media query rules (found #{media_rules})"
  end

  def test_bootstrap_complex_attribute_selectors
    # Bootstrap uses attribute selectors like [type=button]
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    attribute_selectors = []
    sheet.each_selector do |selector, _declarations, _specificity, _media_types|
      attribute_selectors << selector if selector.include?('[type=')
    end

    assert_predicate attribute_selectors.length, :positive?, 'Should find [type=...] attribute selectors'
  end

  def test_bootstrap_custom_properties
    # Bootstrap 5 uses CSS custom properties (--bs-*)
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    custom_props_found = false
    sheet.each_selector do |selector, declarations, _specificity, _media_types|
      next unless selector == ':root'

      # :root should have CSS custom properties
      custom_props_found = declarations.include?('--bs-')
      break if custom_props_found
    end

    assert custom_props_found, 'Should find CSS custom properties in :root'
  end

  def test_bootstrap_calc_functions
    # Bootstrap uses calc() for responsive sizing
    sheet = Cataract::Stylesheet.parse(@bootstrap_css)

    calc_found = false
    sheet.each_selector do |_selector, declarations, _specificity, _media_types|
      if declarations.include?('calc(')
        calc_found = true
        break
      end
    end

    assert calc_found, 'Should find calc() functions in declarations'
  end
end
