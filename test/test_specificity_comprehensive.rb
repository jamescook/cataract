# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Comprehensive specificity tests based on W3C Selectors Level 3 spec
# https://www.w3.org/TR/selectors-3/#specificity
class TestSpecificityComprehensive < Minitest::Test
  def test_pseudo_class_specificity
    # Pseudo-classes count as class selectors (10 points)
    tests = {
      ':hover' => 10,                    # Just pseudo-class
      'a:hover' => 11,                   # Element + pseudo-class
      'div:first-child' => 11,           # Element + pseudo-class
      ':link' => 10,                     # Pseudo-class only
      ':visited' => 10,                  # Pseudo-class only
      'input:focus' => 11,               # Element + pseudo-class
      '.button:hover' => 20,             # Class + pseudo-class
      '#nav:hover' => 110,               # ID + pseudo-class
      'a:hover:focus' => 21 # Element + two pseudo-classes
    }

    tests.each do |selector, expected_specificity|
      actual = Cataract.calculate_specificity(selector)

      assert_equal expected_specificity, actual,
                   "#{selector} should have specificity #{expected_specificity}, got #{actual}"
    end
  end

  def test_pseudo_element_specificity
    # Pseudo-elements count as element selectors (1 point)
    tests = {
      '::before' => 1,                   # Just pseudo-element
      '::after' => 1,                    # Just pseudo-element
      'p::before' => 2,                  # Element + pseudo-element
      'div::after' => 2,                 # Element + pseudo-element
      '.intro::before' => 11,            # Class + pseudo-element
      '#header::after' => 101,           # ID + pseudo-element
      'p:first-child::before' => 12 # Element + pseudo-class + pseudo-element
    }

    tests.each do |selector, expected_specificity|
      actual = Cataract.calculate_specificity(selector)

      assert_equal expected_specificity, actual,
                   "#{selector} should have specificity #{expected_specificity}, got #{actual}"
    end
  end

  def test_complex_pseudo_combinations
    # Complex combinations of pseudo-classes and pseudo-elements
    tests = {
      'a:link::before' => 12,            # Element + pseudo-class + pseudo-element
      'a:hover:focus::after' => 22,      # Element + 2 pseudo-classes + pseudo-element
      '#nav a:hover' => 111,             # ID + element + pseudo-class
      '.menu a:hover::before' => 22,     # Class + element + pseudo-class + pseudo-element
      'ul#nav li:first-child a:hover' => 123 # ID + 3 elements + 2 pseudo-classes
    }

    tests.each do |selector, expected_specificity|
      actual = Cataract.calculate_specificity(selector)

      assert_equal expected_specificity, actual,
                   "#{selector} should have specificity #{expected_specificity}, got #{actual}"
    end
  end

  def test_attribute_and_pseudo_combinations
    # Attribute selectors + pseudo-classes both count as 10
    tests = {
      '[disabled]' => 10,                # Attribute selector
      '[type=text]' => 10,               # Attribute selector with value
      'input[disabled]' => 11,           # Element + attribute
      'input[type=text]:focus' => 21,    # Element + attribute + pseudo-class
      '[disabled]:hover' => 20,          # Attribute + pseudo-class
      '.button[disabled]:hover' => 30 # Class + attribute + pseudo-class
    }

    tests.each do |selector, expected_specificity|
      actual = Cataract.calculate_specificity(selector)

      assert_equal expected_specificity, actual,
                   "#{selector} should have specificity #{expected_specificity}, got #{actual}"
    end
  end

  def test_universal_selector_with_pseudos
    # Universal selector has 0 specificity, but pseudos still count
    tests = {
      '*' => 0,                          # Universal selector alone
      '*:hover' => 10,                   # Universal + pseudo-class
      '*::before' => 1,                  # Universal + pseudo-element
      '* > a:hover' => 11 # Universal + combinator + element + pseudo-class
    }

    tests.each do |selector, expected_specificity|
      actual = Cataract.calculate_specificity(selector)

      assert_equal expected_specificity, actual,
                   "#{selector} should have specificity #{expected_specificity}, got #{actual}"
    end
  end

  def test_w3c_examples
    # Examples directly from W3C Selectors Level 3 spec
    # https://www.w3.org/TR/selectors-3/#specificity
    tests = {
      '*' => 0,                          # a=0 b=0 c=0
      'li' => 1,                         # a=0 b=0 c=1
      'li:first-line' => 2,              # a=0 b=0 c=2 (pseudo-element)
      'ul li' => 2,                      # a=0 b=0 c=2
      'ul ol+li' => 3,                   # a=0 b=0 c=3
      'h1 + *[rel=up]' => 11,            # a=0 b=1 c=1
      'ul ol li.red' => 13,              # a=0 b=1 c=3
      'li.red.level' => 21,              # a=0 b=2 c=1
      '#x34y' => 100,                    # a=1 b=0 c=0
      '#s12:not(foo)' => 101 # a=1 b=0 c=1 (not itself doesn't count, but foo does)
    }

    tests.each do |selector, expected_specificity|
      actual = Cataract.calculate_specificity(selector)

      assert_equal expected_specificity, actual,
                   "W3C example: #{selector} should have specificity #{expected_specificity}, got #{actual}"
    end
  end
end
