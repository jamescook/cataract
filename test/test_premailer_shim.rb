# frozen_string_literal: true

require_relative 'test_helper'
require 'css_parser'

class TestPremailerShim < Minitest::Test
  def setup
    # Suppress method redefinition warnings during shim setup
    # The shim intentionally redefines methods on CssParser classes
    # We only suppress warnings during setup, not during the actual tests
    suppress_warnings { Cataract.mimic_CssParser! }
  end

  def teardown
    suppress_warnings { Cataract.restore_CssParser! }
  end

  def test_mimic_sets_constant
    assert defined?(CssParser), 'CssParser module should be defined'
    assert defined?(CssParser::CATARACT_SHIM), 'CssParser::CATARACT_SHIM constant should be set'
    assert CssParser::CATARACT_SHIM
  end

  def test_parser_class_aliased
    # CssParser::Parser is now a subclass of Cataract::Stylesheet
    assert_operator CssParser::Parser, :<, Cataract::Stylesheet, 'CssParser::Parser should inherit from Cataract::Stylesheet'
  end

  def test_rule_set_class_aliased
    assert_equal Cataract::RuleSet, CssParser::RuleSet
  end

  def test_parser_instantiation
    parser = CssParser::Parser.new

    # Should be an instance of the CssParser::Parser subclass, which inherits from Stylesheet
    assert_kind_of Cataract::Stylesheet, parser
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
    parser.each_selector(media: :all) do |selector, declarations, specificity, media_types|
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
    parser.each_selector(media: :all) do |selector, declaration, _specificity, _media_types|
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

    assert_kind_of Cataract::Stylesheet, parser
  end

  def test_import_support_with_file_scheme
    # Test that shim automatically enables file:// imports when import: true is passed
    # This is critical for Premailer compatibility
    fixtures_dir = File.expand_path('../benchmarks/premailer_fixtures', __dir__)
    email_css_path = File.join(fixtures_dir, 'email.css')

    skip 'Premailer fixtures not found' unless File.exist?(email_css_path)

    # Create parser with import: true (what Premailer does)
    parser = CssParser::Parser.new(import: true)
    parser.load_file!(email_css_path)

    # Should have resolved @import 'imports.css' and included those rules
    selectors = parser.selectors

    assert_includes selectors, '.imported-style', 'Should include .imported-style from imports.css'
    assert_includes selectors, '.highlight', 'Should include .highlight from imports.css'
    assert_includes selectors, '.header', 'Should include .header from email.css'
  end

  def test_import_disabled_by_default
    # Without import: true, @import statements should be ignored
    fixtures_dir = File.expand_path('../benchmarks/premailer_fixtures', __dir__)
    email_css_path = File.join(fixtures_dir, 'email.css')

    skip 'Premailer fixtures not found' unless File.exist?(email_css_path)

    parser = CssParser::Parser.new
    parser.load_file!(email_css_path)

    selectors = parser.selectors

    refute_includes selectors, '.imported-style', 'Should NOT include .imported-style when imports disabled'
    assert_includes selectors, '.header', 'Should still include .header from email.css'
  end

  def test_shim_does_not_mutate_cataract_stylesheet
    # Verify that Cataract::Stylesheet.new is NOT affected by the shim
    # CssParser::Parser is a subclass, so only it should have the import handling

    # Create a stylesheet directly through Cataract
    sheet = Cataract::Stylesheet.new(import: true)
    options = sheet.instance_variable_get(:@options)

    # Should NOT upgrade import: true to full config hash
    assert options[:import], 'Cataract::Stylesheet should receive import: true as-is'

    # Create through CssParser::Parser alias
    parser = CssParser::Parser.new(import: true)
    parser_options = parser.instance_variable_get(:@options)

    # SHOULD upgrade import: true to full config hash
    assert_kind_of Hash, parser_options[:import], 'CssParser::Parser should upgrade import: true to config hash'
    assert_equal %w[https file], parser_options[:import][:allowed_schemes],
                 'CssParser::Parser should enable file:// scheme'
  end

  def test_cssparser_parser_is_subclass_not_alias
    # Verify CssParser::Parser is a proper subclass, not an alias
    assert_operator CssParser::Parser, :<, Cataract::Stylesheet, 'CssParser::Parser should be a subclass'
    assert_equal Cataract::Stylesheet, CssParser::Parser.superclass, 'Superclass should be Stylesheet'
    refute_equal Cataract::Stylesheet, CssParser::Parser, 'Should not be the same class (should be subclass)'
  end

  def test_each_selector_accepts_positional_media_argument
    # css_parser API uses positional argument: each_selector(:all)
    # Cataract API uses keyword argument: each_selector(media: :all)
    # The shim should support both
    parser = CssParser::Parser.new
    parser.add_block!('body { color: red; } @media print { div { margin: 10px; } }')

    # Test with positional argument (css_parser style)
    all_selectors = []
    parser.each_selector(:all) do |selector, _decls, _spec, _media|
      all_selectors << selector
    end

    assert_equal 2, all_selectors.length
    assert_includes all_selectors, 'body'
    assert_includes all_selectors, 'div'

    # Test with keyword argument (Cataract style)
    print_selectors = []
    parser.each_selector(media: :print) do |selector, _decls, _spec, _media|
      print_selectors << selector
    end

    assert_equal 1, print_selectors.length
    assert_includes print_selectors, 'div'
  end

  private

  def suppress_warnings
    original_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original_verbose
  end
end
