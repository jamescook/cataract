#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'

# Test serializing declarations back to CSS string
class TestDeclarationsToS < Minitest::Test
  def test_empty_array
    result = Cataract.declarations_to_s([])
    assert_equal '', result
  end

  def test_bootstrap
    sheet = Cataract.parse_css(File.read('test/fixtures/bootstrap.css'))
    # Get declarations from first rule
    first_rule = sheet.rules.first
    result = Cataract.declarations_to_s(first_rule.declarations)
    # Bootstrap's first rule should have some declarations
    assert result.length > 0
  end

  def test_single_declaration
    decl = Cataract::Declarations::Value.new('color', 'red', false)
    result = Cataract.declarations_to_s([decl])
    assert_equal 'color: red;', result
  end

  def test_single_declaration_with_important
    decl = Cataract::Declarations::Value.new('color', 'red', true)
    result = Cataract.declarations_to_s([decl])
    assert_equal 'color: red !important;', result
  end

  def test_multiple_declarations
    decls = [
      Cataract::Declarations::Value.new('color', 'red', false),
      Cataract::Declarations::Value.new('margin', '10px', false),
      Cataract::Declarations::Value.new('padding', '5px', false)
    ]
    result = Cataract.declarations_to_s(decls)
    assert_equal 'color: red; margin: 10px; padding: 5px;', result
  end

  def test_mixed_important_and_normal
    decls = [
      Cataract::Declarations::Value.new('color', 'red', true),
      Cataract::Declarations::Value.new('margin', '10px', false),
      Cataract::Declarations::Value.new('background', 'blue', true)
    ]
    result = Cataract.declarations_to_s(decls)
    assert_equal 'color: red !important; margin: 10px; background: blue !important;', result
  end

  def test_with_merged_declarations
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black; margin: 0px; }
      .test { padding: 5px; }
    CSS

    merged = Cataract.merge(rules)
    result = Cataract.declarations_to_s(merged)

    # Should contain all three properties
    assert_includes result, 'color: black'
    assert_includes result, 'margin: 0px'
    assert_includes result, 'padding: 5px'
  end

  def test_with_important_from_merge
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black !important; margin: 10px; }
    CSS

    merged = Cataract.merge(rules)
    result = Cataract.declarations_to_s(merged)

    assert_includes result, 'color: black !important'
    assert_includes result, 'margin: 10px;'
  end

  def test_complex_values
    decls = [
      Cataract::Declarations::Value.new('font', 'bold 14px/1.5 Arial, sans-serif', false),
      Cataract::Declarations::Value.new('background', 'url(image.png) no-repeat center', false)
    ]
    result = Cataract.declarations_to_s(decls)

    assert_includes result, 'font: bold 14px/1.5 Arial, sans-serif'
    assert_includes result, 'background: url(image.png) no-repeat center'
  end
end
