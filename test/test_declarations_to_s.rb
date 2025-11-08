#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'

# Test serializing declarations back to CSS string
class TestDeclarationsToS < Minitest::Test
  def test_empty_array
    result = Cataract::Declarations.new([]).to_s

    assert_equal '', result
  end

  def test_bootstrap
    sheet = Cataract.parse_css(File.read('test/fixtures/bootstrap.css'))
    # Get declarations from first rule
    first_rule = sheet.rules.first
    result = Cataract::Declarations.new(first_rule.declarations).to_s
    # Bootstrap's first rule should have some declarations
    assert_predicate result.length, :positive?
  end

  def test_single_declaration
    decl = Cataract::Declaration.new('color', 'red', false)
    result = Cataract::Declarations.new([decl]).to_s

    assert_equal 'color: red;', result
  end

  def test_single_declaration_with_important
    decl = Cataract::Declaration.new('color', 'red', true)
    result = Cataract::Declarations.new([decl]).to_s

    assert_equal 'color: red !important;', result
  end

  def test_multiple_declarations
    decls = [
      Cataract::Declaration.new('color', 'red', false),
      Cataract::Declaration.new('margin', '10px', false),
      Cataract::Declaration.new('padding', '5px', false)
    ]
    result = Cataract::Declarations.new(decls).to_s

    assert_equal 'color: red; margin: 10px; padding: 5px;', result
  end

  def test_mixed_important_and_normal
    decls = [
      Cataract::Declaration.new('color', 'red', true),
      Cataract::Declaration.new('margin', '10px', false),
      Cataract::Declaration.new('background', 'blue', true)
    ]
    result = Cataract::Declarations.new(decls).to_s

    assert_equal 'color: red !important; margin: 10px; background: blue !important;', result
  end

  def test_with_merged_declarations
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black; margin: 0px; }
      .test { padding: 5px; }
    CSS

    merged = rules.merge.rules.first.declarations
    result = Cataract::Declarations.new(merged).to_s

    # Should contain all three properties
    assert_includes result, 'color: black'
    assert_includes result, 'margin: 0px'
    assert_includes result, 'padding: 5px'
  end

  def test_with_important_from_merge
    rules = Cataract.parse_css(<<~CSS)
      .test { color: black !important; margin: 10px; }
    CSS

    merged = rules.merge.rules.first.declarations
    result = Cataract::Declarations.new(merged).to_s

    assert_includes result, 'color: black !important'
    assert_includes result, 'margin: 10px;'
  end

  def test_complex_values
    decls = [
      Cataract::Declaration.new('font', 'bold 14px/1.5 Arial, sans-serif', false),
      Cataract::Declaration.new('background', 'url(image.png) no-repeat center', false)
    ]
    result = Cataract::Declarations.new(decls).to_s

    assert_includes result, 'font: bold 14px/1.5 Arial, sans-serif'
    assert_includes result, 'background: url(image.png) no-repeat center'
  end
end
