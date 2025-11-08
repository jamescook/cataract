# frozen_string_literal: true

require_relative 'test_helper'

# Real-world CSS parsing tests using actual framework CSS files
class TestNewRealWorld < Minitest::Test
  def setup
    @bootstrap_css = File.read(File.expand_path('fixtures/bootstrap.css', __dir__))
  end

  def test_bootstrap_parses_successfully
    # Real-world CSS from Bootstrap 5
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    # Bootstrap 5.0.2 should have exactly 2807 rules (matches css_parser)
    # Note: Rules are split by selector, so "h1, h2 { }" becomes 2 rules
    assert_equal 2807, sheet.size, 'Should parse Bootstrap CSS with correct rule count'
  end

  def test_bootstrap_standalone_pseudo_elements
    # Bootstrap uses standalone pseudo-elements like ::-moz-focus-inner
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    # Find the ::-moz-focus-inner rule
    found = false
    sheet.each_selector do |rule|
      next unless rule.selector == '::-moz-focus-inner'

      found = true

      assert_has_property({ padding: '0' }, rule)
      assert_has_property({ 'border-style': 'none' }, rule)
    end

    assert found, 'Should find ::-moz-focus-inner selector'
  end

  def test_bootstrap_pseudo_class_after_pseudo_element
    # Bootstrap uses selectors like .form-range::-webkit-slider-thumb:active
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    # Find webkit slider thumb with :active pseudo-class
    found = false
    sheet.each_selector do |rule|
      next unless rule.selector.include?('webkit-slider-thumb:active')

      found = true

      # Check that it has a background-color property
      has_bg = rule.declarations.any? { |d| d.property == 'background-color' }

      assert has_bg, 'Should have background-color'
    end

    assert found, 'Should find ::-webkit-slider-thumb:active selector'
  end

  def test_bootstrap_vendor_prefixed_pseudo_elements
    # Bootstrap uses vendor-prefixed pseudo-elements
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    vendor_pseudo_elements = []
    sheet.each_selector do |rule|
      vendor_pseudo_elements << rule.selector if rule.selector.include?('::-webkit-') || rule.selector.include?('::-moz-')
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
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    # Count rules with media types (any media that's not :all)
    media_rules = sheet.media_index.except(:all).values.flatten.uniq.size

    assert_predicate media_rules, :positive?, "Bootstrap should have media query rules (found #{media_rules})"
  end

  def test_bootstrap_complex_attribute_selectors
    # Bootstrap uses attribute selectors like [type=button]
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    attribute_selectors = []
    sheet.each_selector do |rule|
      attribute_selectors << rule.selector if rule.selector.include?('[type=')
    end

    assert_predicate attribute_selectors.length, :positive?, 'Should find [type=...] attribute selectors'
  end

  def test_bootstrap_custom_properties
    # Bootstrap 5 uses CSS custom properties (--bs-*)
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    custom_props_found = false
    sheet.each_selector do |rule|
      next unless rule.selector == ':root'

      # :root should have CSS custom properties (check if any property starts with '--bs-')
      custom_props_found = rule.declarations.any? { |d| d.property.start_with?('--bs-') }
      break if custom_props_found
    end

    assert custom_props_found, 'Should find CSS custom properties in :root'
  end

  def test_bootstrap_calc_functions
    # Bootstrap uses calc() for responsive sizing
    sheet = Cataract::NewStylesheet.parse(@bootstrap_css)

    calc_found = false
    sheet.each_selector do |rule|
      # Check if any declaration value contains 'calc('
      if rule.declarations.any? { |d| d.value.to_s.include?('calc(') }
        calc_found = true
        break
      end
    end

    assert calc_found, 'Should find calc() functions in declarations'
  end
end
