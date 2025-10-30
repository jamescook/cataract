# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'
require 'set'

# RuleSet functionality tests
# Based on css_parser gem's test_rule_set.rb
class TestRuleSet < Minitest::Test
  def test_setting_property_values
    rs = Cataract::RuleSet.new(selectors: 'body')

    rs['background-color'] = 'red'

    assert_equal 'red;', rs['background-color']

    rs['background-color'] = 'blue !important;'

    assert_equal 'blue !important;', rs['background-color']
  end

  def test_getting_property_values
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: 'color: #fff;')

    assert_equal '#fff;', rs['color']
  end

  def test_getting_property_value_ignoring_case
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: 'color: #fff;')

    assert_equal '#fff;', rs['  ColoR ']
  end

  def test_each_selector
    expected = [
      { selector: '#content p', declarations: 'color: #fff;', specificity: 101 },
      { selector: 'a', declarations: 'color: #fff;', specificity: 1 }
    ]

    actual = []
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: 'color: #fff;')
    rs.each_selector do |sel, decs, spec|
      actual << { selector: sel, declarations: decs, specificity: spec }
    end

    assert_equal expected, actual
  end

  def test_each_declaration
    expected = Set[
      { property: 'margin', value: '1px -0.25em', is_important: false },
      { property: 'background', value: 'white none no-repeat', is_important: true },
      { property: 'color', value: '#fff', is_important: false }
    ]

    actual = Set.new
    rs = Cataract::RuleSet.new(selectors: 'body',
                               block: 'color: #fff; Background: white none no-repeat !important; margin: 1px -0.25em;')
    rs.each_declaration do |prop, val, imp|
      actual << { property: prop, value: val, is_important: imp }
    end

    assert_equal expected, actual
  end

  def test_each_declaration_respects_order
    css_fragment = 'margin: 0; padding: 20px; margin-bottom: 28px;'
    rs = Cataract::RuleSet.new(selectors: 'body', block: css_fragment)
    expected = %w[margin padding margin-bottom]
    actual = []
    rs.each_declaration { |prop, _val, _imp| actual << prop }

    assert_equal expected, actual
  end

  def test_each_declaration_containing_semicolons
    rs = Cataract::RuleSet.new(selectors: 'div', block: 'background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAiCAMAAAB7);' \
                                                        'background-repeat: no-repeat')

    assert_equal 'url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAiCAMAAAB7);', rs['background-image']
    assert_equal 'no-repeat;', rs['background-repeat']
  end

  def test_each_declaration_with_newlines
    expected = Set[
      { property: 'background-image', value: 'url(foo;bar)', is_important: false },
      { property: 'font-weight', value: 'bold', is_important: true }
    ]
    rs = Cataract::RuleSet.new(selectors: 'body',
                               block: "background-image\n:\nurl(foo;bar);\n\n\n\n\n;;font-weight\n\n\n:bold\n\n\n!important")
    actual = Set.new
    rs.each_declaration do |prop, val, imp|
      actual << { property: prop, value: val, is_important: imp }
    end

    assert_equal expected, actual
  end

  def test_selector_sanitization
    selectors = "h1, h2,\nh3 "
    rs = Cataract::RuleSet.new(selectors: selectors, block: 'color: #fff;')

    assert_includes rs.selectors, 'h3'
  end

  def test_multiple_selectors_to_s
    selectors = '#content p, a'
    rs = Cataract::RuleSet.new(selectors: selectors, block: 'color: #fff;')
    # Should output both selectors separately (our implementation keeps them together)
    assert_match(/#content p/, rs.to_s)
    assert_match(/color: #fff/, rs.to_s)
  end

  def test_declarations_to_s
    declarations = 'color: #fff; font-weight: bold;'
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: declarations)

    assert_equal declarations.split.sort, rs.declarations_to_s.split.sort
  end

  def test_important_declarations_to_s
    declarations = 'color: #fff; font-weight: bold !important;'
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: declarations)

    assert_equal declarations.split.sort, rs.declarations_to_s.split.sort
  end

  def test_overriding_specificity
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: 'color: white', specificity: 1000)

    rs.each_selector do |_sel, _decs, spec|
      assert_equal 1000, spec
    end
  end

  def test_important_without_value
    declarations = 'color: !important; background-color: #fff'
    rs = Cataract::RuleSet.new(selectors: '#content p, a', block: declarations)
    # Malformed "color: !important" should be ignored, only background-color remains
    assert_equal 'background-color: #fff;', rs.declarations_to_s
  end

  def test_not_raised_issue68
    # Regression test: should not raise an error
    ok = true
    begin
      Cataract::RuleSet.new(selectors: 'td', block: 'border-top: 5px solid; border-color: #fffff0;')
    rescue StandardError
      ok = false
    end

    assert ok
  end

  def test_ruleset_with_braces
    # css_parser allows passing declarations with braces
    new_rule = Cataract::RuleSet.new(selectors: 'div', block: '{ background-color: black !important; }')

    assert_equal 'div { background-color: black !important; }', new_rule.to_s
  end

  def test_content_with_data
    # Data URIs with embedded content should work
    rule = Cataract::RuleSet.new(selectors: 'div', block: '{content: url(data:image/png;base64,LOTSOFSTUFF)}')

    assert_includes rule.to_s, 'image/png;base64,LOTSOFSTUFF'
  end

  def test_merge
    rule1 = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red', 'margin' => '10px' }
    )

    rule2 = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'blue', 'padding' => '5px' }
    )

    # Non-mutating merge
    merged = rule1.merge(rule2)

    assert_equal 'blue;', merged['color']
    assert_equal '10px;', merged['margin']
    assert_equal '5px;', merged['padding']

    # Original unchanged (returns empty string for missing properties)
    assert_equal 'red;', rule1['color']
    assert_equal '', rule1['padding']
  end

  def test_merge_bang
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    rule['background'] = 'blue'

    # Should mutate original
    assert_equal 'red;', rule['color']
    assert_equal 'blue;', rule['background']
  end

  def test_merge_with_declarations
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    decl = Cataract::Declarations.new({ 'margin' => '10px' })
    merged = rule.merge(decl)

    assert_equal 'red;', merged['color']
    assert_equal '10px;', merged['margin']
  end

  def test_equality
    rule1 = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    rule2 = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    rule3 = Cataract::RuleSet.new(
      selector: '#btn',
      declarations: { 'color' => 'red' }
    )

    assert_equal rule1, rule2
    refute_equal rule1, rule3
  end

  def test_dup
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    duped = rule.dup
    duped['background'] = 'blue'

    # Original unchanged (returns empty string for missing properties)
    assert_equal '', rule['background']
    assert_equal 'blue;', duped['background']
  end

  def test_to_h
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red', 'margin' => '10px' },
      media_types: [:print]
    )

    hash = rule.to_h

    assert_equal '.btn', hash[:selector]
    assert_equal({ 'color' => 'red', 'margin' => '10px' }, hash[:declarations])
    assert_equal [:print], hash[:media_types]
    assert_equal 10, hash[:specificity]
  end

  def test_has_property?
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    assert rule.has_property?('color')
    refute rule.has_property?('background')
  end

  def test_delete_property
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red', 'margin' => '10px' }
    )

    rule.delete_property('margin')

    refute rule.has_property?('margin')
    assert_equal 'red;', rule['color']
  end

  def test_empty?
    rule = Cataract::RuleSet.new(
      selector: '.btn',
      declarations: { 'color' => 'red' }
    )

    refute_empty rule

    rule.delete_property('color')

    assert_empty rule
  end

  def test_expand_shorthand!
    rule = Cataract::RuleSet.new(
      selector: 'div',
      block: 'margin: 10px 20px; padding: 5px; border: 1px solid black;'
    )

    rule.expand_shorthand!

    # Should expand margin
    assert_equal '10px;', rule['margin-top']
    assert_equal '20px;', rule['margin-right']
    assert_equal '10px;', rule['margin-bottom']
    assert_equal '20px;', rule['margin-left']

    # Should expand padding
    assert_equal '5px;', rule['padding-top']
    assert_equal '5px;', rule['padding-right']
    assert_equal '5px;', rule['padding-bottom']
    assert_equal '5px;', rule['padding-left']

    # Should expand border
    assert_equal '1px;', rule['border-top-width']
    assert_equal 'solid;', rule['border-top-style']
    assert_equal 'black;', rule['border-top-color']

    # Original shorthands should be removed (returns empty string for missing properties)
    assert_equal '', rule['margin']
    assert_equal '', rule['padding']
    assert_equal '', rule['border']
  end
end
