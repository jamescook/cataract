# frozen_string_literal: true

require 'test_helper'

class TestCssParserCompatibility < Minitest::Test
  def setup
    Cataract.mimic_CssParser!
  end

  def teardown
    Cataract.restore_CssParser!
  end

  def test_mimic_sets_constant
    assert defined?(CssParser), 'CssParser module should be defined'
    assert defined?(CssParser::CATARACT_SHIM), 'CssParser::CATARACT_SHIM constant should be set'
    assert CssParser::CATARACT_SHIM
  end

  def test_parser_class_aliased
    assert_equal Cataract::Parser, CssParser::Parser
  end

  def test_rule_set_class_aliased
    assert_equal Cataract::RuleSet, CssParser::RuleSet
  end

  def test_parser_instantiation
    parser = CssParser::Parser.new

    assert_instance_of Cataract::Parser, parser
  end

  def test_parser_load_string
    parser = CssParser::Parser.new
    parser.load_string!('div { color: red; }')

    found = false
    parser.each_selector do |selector, declarations, _specificity|
      if selector == 'div'
        assert_match(/color:\s*red/, declarations)
        found = true
      end
    end

    assert found, 'Should find div selector'
  end

  def test_rule_set_instantiation
    # Test with selectors (plural) - css_parser compatibility
    rule_set = CssParser::RuleSet.new(selectors: 'div', block: 'color: red;')

    assert_instance_of Cataract::RuleSet, rule_set
    assert_equal 'div', rule_set.selector
    assert_equal 'red;', rule_set['color'] # css_parser includes trailing semicolon
  end

  def test_rule_set_with_selector_singular
    # Test with selector (singular) - Cataract native
    rule_set = CssParser::RuleSet.new(selector: 'span', block: 'font-size: 12px;')

    assert_instance_of Cataract::RuleSet, rule_set
    assert_equal 'span', rule_set.selector
    assert_equal '12px;', rule_set['font-size'] # css_parser includes trailing semicolon
  end

  def test_add_rule_set
    parser = CssParser::Parser.new
    rule_set = CssParser::RuleSet.new(selectors: 'p', block: 'margin: 10px;')

    parser.add_rule_set!(rule_set)

    found = false
    parser.each_selector do |selector, declarations, _specificity|
      if selector == 'p'
        assert_match(/margin/, declarations)
        found = true
      end
    end

    assert found, 'Should find p selector after add_rule_set!'
  end

  def test_css_parser_merge
    rule1 = CssParser::RuleSet.new(selectors: 'div', block: 'color: red; font-size: 12px;')
    rule2 = CssParser::RuleSet.new(selectors: 'div', block: 'color: blue; margin: 10px;')

    merged = CssParser.merge(rule1, rule2)

    assert_instance_of Cataract::RuleSet, merged
    # Later rule wins for color
    assert_equal 'blue;', merged['color']
    # Margin is preserved
    assert_equal '10px;', merged['margin']
    # Font-size is preserved
    assert_equal '12px;', merged['font-size']
  end

  def test_css_parser_merge_with_array
    rule1 = CssParser::RuleSet.new(selectors: 'div', block: 'color: red;')
    rule2 = CssParser::RuleSet.new(selectors: 'div', block: 'color: blue;')

    # Test that merge accepts array (premailer sometimes does this)
    merged = CssParser.merge([rule1, rule2])

    assert_instance_of Cataract::RuleSet, merged
    assert_equal 'blue;', merged['color']
  end

  def test_expand_shorthand
    rule_set = CssParser::RuleSet.new(
      selectors: 'div',
      block: 'margin: 10px 20px; padding: 5px; border: 1px solid black;'
    )

    rule_set.expand_shorthand!

    # Should expand margin
    assert_equal '10px;', rule_set['margin-top']
    assert_equal '20px;', rule_set['margin-right']
    assert_equal '10px;', rule_set['margin-bottom']
    assert_equal '20px;', rule_set['margin-left']

    # Should expand padding
    assert_equal '5px;', rule_set['padding-top']
    assert_equal '5px;', rule_set['padding-right']

    # Should expand border
    assert_equal '1px;', rule_set['border-top-width']
    assert_equal 'solid;', rule_set['border-top-style']
    assert_equal 'black;', rule_set['border-top-color']
  end

  def test_each_selector_yields_correct_parameters
    parser = CssParser::Parser.new
    parser.load_string!('div { color: red; } @media print { p { font-size: 10pt; } }')

    selectors_found = []
    parser.each_selector(:all) do |selector, declarations, specificity, media_types|
      selectors_found << selector

      assert_kind_of String, selector
      assert_kind_of String, declarations
      assert_kind_of Integer, specificity
      assert_kind_of Array, media_types
    end

    assert_includes selectors_found, 'div'
    assert_includes selectors_found, 'p'
  end

  def test_premailer_workflow
    # Simulate typical premailer usage pattern
    parser = CssParser::Parser.new
    parser.load_string!(<<~CSS)
      div { color: red; font-size: 12px; }
      .button { padding: 10px 20px; background: blue; }
    CSS

    # Collect matching rules for a specific element
    declarations = []
    parser.each_selector(:all) do |selector, declaration, _specificity, _media_types|
      declarations << CssParser::RuleSet.new(selectors: selector, block: declaration) if selector == 'div'
    end

    # Merge declarations
    merged = CssParser.merge(declarations) unless declarations.empty?

    assert_instance_of Cataract::RuleSet, merged
    assert_equal 'red;', merged['color']
    assert_equal '12px;', merged['font-size']
  end

  def test_multiple_mimic_calls_safe
    # Calling mimic_CssParser! multiple times should be safe
    Cataract.mimic_CssParser!
    Cataract.mimic_CssParser!

    parser = CssParser::Parser.new

    assert_instance_of Cataract::Parser, parser
  end
end
