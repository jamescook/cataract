# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Comprehensive CSS Specificity Calculation Tests
# Migrated from css_parser gem's test_css_parser_misc.rb
class TestSpecificity < Minitest::Test
  def test_calculating_specificity
    # from http://www.w3.org/TR/CSS21/cascade.html#specificity
    assert_equal 0,   Cataract.calculate_specificity('*')
    assert_equal 1,   Cataract.calculate_specificity('li')
    assert_equal 2,   Cataract.calculate_specificity('li:first-line')
    assert_equal 2,   Cataract.calculate_specificity('ul li')
    assert_equal 3,   Cataract.calculate_specificity('ul ol+li')
    assert_equal 11,  Cataract.calculate_specificity('h1 + *[rel=up]')
    assert_equal 13,  Cataract.calculate_specificity('ul ol li.red')
    assert_equal 21,  Cataract.calculate_specificity('li.red.level')
    assert_equal 100, Cataract.calculate_specificity('#x34y')

    # from http://www.hixie.ch/tests/adhoc/css/cascade/specificity/003.html
    assert_equal Cataract.calculate_specificity('div *'), Cataract.calculate_specificity('p')
    assert_operator Cataract.calculate_specificity('body div *'), :>, Cataract.calculate_specificity('div *')

    # other tests
    assert_equal 11, Cataract.calculate_specificity('h1[id|=123]')
  end

  def test_specificity_with_pseudo_classes
    # Pseudo-classes count as class selectors
    assert_equal 10, Cataract.calculate_specificity(':hover')
    assert_equal 11, Cataract.calculate_specificity('a:hover')
    assert_equal 21, Cataract.calculate_specificity('a:link:visited')
  end

  def test_specificity_with_pseudo_elements
    # Pseudo-elements count as element selectors
    assert_equal 1, Cataract.calculate_specificity('::before')
    assert_equal 2, Cataract.calculate_specificity('p::first-line')
  end

  def test_specificity_with_attribute_selectors
    # Attribute selectors count as class selectors
    assert_equal 10, Cataract.calculate_specificity('[href]')
    assert_equal 11, Cataract.calculate_specificity('a[href]')
    assert_equal 20, Cataract.calculate_specificity('[type][required]')

    # CSS2 attribute operators
    assert_equal 11, Cataract.calculate_specificity('a[href="https://example.com"]')  # Exact match =
    assert_equal 11, Cataract.calculate_specificity('p[lang|="en"]')                  # Hyphen-separated |=
    assert_equal 11, Cataract.calculate_specificity('div[class~="button"]')           # Space-separated ~=

    # CSS3 attribute operators
    assert_equal 11, Cataract.calculate_specificity('a[href^="https"]')   # Starts with ^=
    assert_equal 11, Cataract.calculate_specificity('a[href$=".pdf"]')    # Ends with $=
    assert_equal 11, Cataract.calculate_specificity('a[href*="example"]') # Contains *=

    # Numeric attribute values
    assert_equal 11, Cataract.calculate_specificity('input[tabindex=0]')
    assert_equal 11, Cataract.calculate_specificity('div[data-id=123]')
  end

  def test_specificity_with_id_selectors
    # ID selectors have highest specificity
    assert_equal 100, Cataract.calculate_specificity('#main')
    assert_equal 101, Cataract.calculate_specificity('#main p')
    assert_equal 200, Cataract.calculate_specificity('#header #nav')
  end

  def test_specificity_with_combinators
    # Combinators don't affect specificity
    assert_equal 2, Cataract.calculate_specificity('div p')
    assert_equal 2, Cataract.calculate_specificity('div > p')
    assert_equal 2, Cataract.calculate_specificity('div + p')
    assert_equal 2, Cataract.calculate_specificity('div ~ p')
  end

  def test_specificity_complex_selectors
    # Complex real-world selectors
    assert_equal 111, Cataract.calculate_specificity('#content .post a')
    assert_equal 121, Cataract.calculate_specificity('#content .post a.external')
    assert_equal 103, Cataract.calculate_specificity('#sidebar ul li a') # #sidebar(100) + ul(1) + li(1) + a(1) = 103
    assert_equal 121, Cataract.calculate_specificity('#nav .menu-item:hover a') # #nav(100) + .menu-item(10) + :hover(10) + a(1) = 121
  end
end
