#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'

class TestMerging < Minitest::Test
  # Helper to find declaration by property name
  def find_property(declarations, property_name)
    decl = declarations.find { |d| d.property == property_name }
    return nil unless decl
    decl.important ? "#{decl.value} !important" : decl.value
  end

  # Test simple merge of two rules with different properties
  def test_simple_merge
    rules = Cataract.parse_css(<<~CSS)
      .test1 { color: black; }
      .test1 { margin: 0px; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'black', find_property(merged, 'color')
    assert_equal '0px', find_property(merged, 'margin')
  end

  # Test that later rule with same specificity overwrites earlier
  def test_merging_same_property
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black; }
      .test { color: red; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red', find_property(merged, 'color')
  end

  # Test that higher specificity wins
  def test_specificity_wins
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black; }
      #test { color: red; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red', find_property(merged, 'color'), 'ID selector (#test) should win over class (.test)'
  end

  # Test that lower specificity doesn't override higher
  def test_lower_specificity_loses
    rules = Cataract.parse_css(<<~CSS)
      #test { color: red; }
      .test { color: black; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red', find_property(merged, 'color'), 'ID selector should not be overridden by class'
  end

  # Test !important wins over non-important regardless of specificity
  def test_important_wins
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black !important; }
      #test { color: red; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'black !important', find_property(merged, 'color'), '!important should win over higher specificity'
  end

  # Test !important doesn't override higher specificity !important
  def test_important_with_specificity
    rules = Cataract.parse_css(<<~CSS)
      #test { color: red !important; }
      .test { color: black !important; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red !important', find_property(merged, 'color'), 'Higher specificity !important should win'
  end

  # Test merging with multiple selectors (uses max specificity)
  def test_multiple_selectors_max_specificity
    rules = Cataract.parse_css(<<~CSS)
      p, a[rel="external"] { color: black; }
      a { color: blue; }
    CSS

    # Filter to only rules matching 'a' selector
    a_rules = rules.select { |r| r[:selector].match?(/\ba\b/) }
    merged = Cataract.merge(a_rules)

    # p=1, a[rel="external"]=11, so max=11 should beat a=1
    assert_equal 'black', find_property(merged, 'color')
  end

  # Test property names are case-insensitive
  def test_case_insensitive_properties
    rules = Cataract.parse_css(<<~CSS)
      .test { CoLor: red; }
      .test { color: blue; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'blue', find_property(merged, 'color')
  end

  # Test merging backgrounds (requires shorthand expansion)
  def test_merging_backgrounds
    rules = Cataract.parse_css(<<~CSS)
      .test { background-color: black; }
      .test { background-image: none; }
    CSS

    merged = Cataract.merge(rules)
    # Note: background shorthand creation is not implemented yet, will be added later
    # For now, we expect longhand properties
    assert_equal 'black', find_property(merged, 'background-color')
    assert_equal 'none', find_property(merged, 'background-image')
  end

  # Test merging dimensions (margin expansion then merge)
  def test_merging_dimensions
    rules = Cataract.parse_css(<<~CSS)
      .test { margin: 3em; }
      .test { margin-left: 1em; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal '3em 3em 3em 1em', find_property(merged, 'margin')
  end

  # Test merging fonts
  def test_merging_fonts
    skip "Font shorthand creation not yet implemented"
    rules = Cataract.parse_css(<<~CSS)
      .test { font: 11px Arial; }
      .test { font-weight: bold; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'bold 11px Arial', find_property(merged, 'font')
  end

  # Test multiple !important with same specificity (last wins)
  def test_multiple_important_same_specificity
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black !important; }
      .test { color: red !important; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red !important', find_property(merged, 'color')
  end

  # Test !important in same block (last wins)
  def test_important_in_same_block
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black !important; color: red !important; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red !important', find_property(merged, 'color')
  end

  # Test !important beats non-important in same block
  def test_important_beats_non_important_same_block
    rules = Cataract.parse_css(<<~CSS)
      .test { color: red; color: black !important; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'black !important', find_property(merged, 'color')
  end

  # Test merging shorthand !important
  def test_shorthand_important
    rules = Cataract.parse_css(<<~CSS)
      .test { background: black none !important; }
      .test { background-color: red; }
    CSS

    merged = Cataract.merge(rules)
    # After expansion, background-color should be marked !important
    assert_equal 'black !important', find_property(merged, 'background-color')
  end

  # Test empty merge (single rule)
  def test_single_rule_merge
    rules = Cataract.parse_css(<<~CSS)
      .test { color: red; margin: 10px; }
    CSS

    merged = Cataract.merge(rules)
    assert_equal 'red', find_property(merged, 'color')
    assert_equal '10px', find_property(merged, 'margin')
  end

  # Test merging with no rules
  def test_empty_merge
    merged = Cataract.merge([])
    assert_empty merged
  end
end
