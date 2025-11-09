# frozen_string_literal: true

require_relative 'test_helper'

# Test CSS3 structural pseudo-classes
# Based on W3C Selectors Level 3: https://www.w3.org/TR/selectors-3/#structural-pseudos
class TestStructuralPseudoClasses < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # :nth-child() tests
  def test_nth_child_simple_number
    @sheet.add_block('li:nth-child(3) { color: red; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'li:nth-child(3)', @sheet
  end

  def test_nth_child_odd
    @sheet.add_block('tr:nth-child(odd) { background: gray; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'tr:nth-child(odd)', @sheet
  end

  def test_nth_child_even
    @sheet.add_block('tr:nth-child(even) { background: white; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'tr:nth-child(even)', @sheet
  end

  def test_nth_child_formula_an_plus_b
    @sheet.add_block('li:nth-child(2n+1) { color: blue; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'li:nth-child(2n+1)', @sheet
  end

  def test_nth_child_formula_negative
    @sheet.add_block('li:nth-child(-n+3) { font-weight: bold; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'li:nth-child(-n+3)', @sheet
  end

  # :nth-of-type() tests
  def test_nth_of_type_simple
    @sheet.add_block('p:nth-of-type(2) { margin-top: 20px; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'p:nth-of-type(2)', @sheet
  end

  def test_nth_of_type_odd
    @sheet.add_block('div:nth-of-type(odd) { background: lightgray; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'div:nth-of-type(odd)', @sheet
  end

  # :first-of-type and :last-of-type
  def test_first_of_type
    @sheet.add_block('p:first-of-type { font-weight: bold; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'p:first-of-type', @sheet
  end

  def test_last_of_type
    @sheet.add_block('p:last-of-type { margin-bottom: 0; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'p:last-of-type', @sheet
  end

  # :last-child
  def test_last_child
    @sheet.add_block('li:last-child { border-bottom: none; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'li:last-child', @sheet
  end

  # :only-child and :only-of-type
  def test_only_child
    @sheet.add_block('p:only-child { text-align: center; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'p:only-child', @sheet
  end

  def test_only_of_type
    @sheet.add_block('img:only-of-type { display: block; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'img:only-of-type', @sheet
  end

  # :nth-last-child() and :nth-last-of-type()
  def test_nth_last_child
    @sheet.add_block('li:nth-last-child(2) { color: red; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'li:nth-last-child(2)', @sheet
  end

  def test_nth_last_of_type
    @sheet.add_block('p:nth-last-of-type(1) { font-style: italic; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'p:nth-last-of-type(1)', @sheet
  end

  # :empty
  def test_empty
    @sheet.add_block('div:empty { display: none; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'div:empty', @sheet
  end

  # Combinations with other selectors
  def test_structural_with_class
    @sheet.add_block('.item:nth-child(odd) { background: #f0f0f0; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector '.item:nth-child(odd)', @sheet
  end

  def test_multiple_structural_pseudo_classes
    @sheet.add_block('li:first-child:last-child { font-weight: bold; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'li:first-child:last-child', @sheet
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
    @sheet.add_block('input:enabled { background: white; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'input:enabled', @sheet
  end

  def test_disabled
    @sheet.add_block('input:disabled { opacity: 0.5; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'input:disabled', @sheet
  end

  def test_checked
    @sheet.add_block('input:checked { background: blue; }')

    assert_equal 1, @sheet.rules_count
    assert_has_selector 'input:checked', @sheet
  end

  def test_ui_pseudo_class_specificity
    # UI pseudo-classes count as class selectors (10 points)
    assert_equal 11, Cataract.calculate_specificity('input:enabled') # element(1) + pseudo-class(10)
    assert_equal 11, Cataract.calculate_specificity('input:disabled') # element(1) + pseudo-class(10)
    assert_equal 11, Cataract.calculate_specificity('input:checked') # element(1) + pseudo-class(10)
  end
end
