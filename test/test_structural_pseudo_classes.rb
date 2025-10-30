# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Test CSS3 structural pseudo-classes
# Based on W3C Selectors Level 3: https://www.w3.org/TR/selectors-3/#structural-pseudos
class TestStructuralPseudoClasses < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
  end

  # :nth-child() tests
  def test_nth_child_simple_number
    @parser.parse('li:nth-child(3) { color: red; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'li:nth-child(3)'
  end

  def test_nth_child_odd
    @parser.parse('tr:nth-child(odd) { background: gray; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'tr:nth-child(odd)'
  end

  def test_nth_child_even
    @parser.parse('tr:nth-child(even) { background: white; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'tr:nth-child(even)'
  end

  def test_nth_child_formula_an_plus_b
    @parser.parse('li:nth-child(2n+1) { color: blue; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'li:nth-child(2n+1)'
  end

  def test_nth_child_formula_negative
    @parser.parse('li:nth-child(-n+3) { font-weight: bold; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'li:nth-child(-n+3)'
  end

  # :nth-of-type() tests
  def test_nth_of_type_simple
    @parser.parse('p:nth-of-type(2) { margin-top: 20px; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'p:nth-of-type(2)'
  end

  def test_nth_of_type_odd
    @parser.parse('div:nth-of-type(odd) { background: lightgray; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'div:nth-of-type(odd)'
  end

  # :first-of-type and :last-of-type
  def test_first_of_type
    @parser.parse('p:first-of-type { font-weight: bold; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'p:first-of-type'
  end

  def test_last_of_type
    @parser.parse('p:last-of-type { margin-bottom: 0; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'p:last-of-type'
  end

  # :last-child
  def test_last_child
    @parser.parse('li:last-child { border-bottom: none; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'li:last-child'
  end

  # :only-child and :only-of-type
  def test_only_child
    @parser.parse('p:only-child { text-align: center; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'p:only-child'
  end

  def test_only_of_type
    @parser.parse('img:only-of-type { display: block; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'img:only-of-type'
  end

  # :nth-last-child() and :nth-last-of-type()
  def test_nth_last_child
    @parser.parse('li:nth-last-child(2) { color: red; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'li:nth-last-child(2)'
  end

  def test_nth_last_of_type
    @parser.parse('p:nth-last-of-type(1) { font-style: italic; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'p:nth-last-of-type(1)'
  end

  # :empty
  def test_empty
    @parser.parse('div:empty { display: none; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'div:empty'
  end

  # Combinations with other selectors
  def test_structural_with_class
    @parser.parse('.item:nth-child(odd) { background: #f0f0f0; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, '.item:nth-child(odd)'
  end

  def test_multiple_structural_pseudo_classes
    @parser.parse('li:first-child:last-child { font-weight: bold; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'li:first-child:last-child'
  end

  # Specificity tests
  def test_nth_child_specificity
    # Structural pseudo-classes count as class selectors (10 points)
    assert_equal 11, Cataract.calculate_specificity('li:nth-child(2)') # element(1) + pseudo-class(10)
    assert_equal 20, Cataract.calculate_specificity('.item:nth-child(odd)') # class(10) + pseudo-class(10)
    assert_equal 21, Cataract.calculate_specificity('li.item:nth-child(odd)') # element(1) + class(10) + pseudo-class(10)
  end

  def test_first_of_type_specificity
    assert_equal 11, Cataract.calculate_specificity('p:first-of-type') # element(1) + pseudo-class(10)
  end

  # UI pseudo-classes (CSS3)
  def test_enabled
    @parser.parse('input:enabled { background: white; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'input:enabled'
  end

  def test_disabled
    @parser.parse('input:disabled { opacity: 0.5; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'input:disabled'
  end

  def test_checked
    @parser.parse('input:checked { background: blue; }')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'input:checked'
  end

  def test_ui_pseudo_class_specificity
    # UI pseudo-classes count as class selectors (10 points)
    assert_equal 11, Cataract.calculate_specificity('input:enabled') # element(1) + pseudo-class(10)
    assert_equal 11, Cataract.calculate_specificity('input:disabled') # element(1) + pseudo-class(10)
    assert_equal 11, Cataract.calculate_specificity('input:checked') # element(1) + pseudo-class(10)
  end
end
