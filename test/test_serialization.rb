#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'

class TestSerialization < Minitest::Test
  def test_stylesheet_to_s
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    assert_includes result, 'body'
    assert_includes result, 'color: red'
    assert_includes result, 'margin: 10px'
  end

  def test_stylesheet_to_s_with_important
    css = 'div { color: blue !important; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    assert_includes result, 'div'
    assert_includes result, 'color: blue !important'
  end

  def test_stylesheet_add_block
    css1 = 'body { color: red; }'
    sheet = Cataract.parse_css(css1)

    assert_equal 1, sheet.size

    sheet.add_block!('div { margin: 10px; }')
    assert_equal 2, sheet.size

    result = sheet.to_s
    assert_includes result, 'body'
    assert_includes result, 'color: red'
    assert_includes result, 'div'
    assert_includes result, 'margin: 10px'
  end

  def test_stylesheet_declarations
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)
    declarations = sheet.declarations

    assert_kind_of Array, declarations
    assert declarations.all? { |d| d.is_a?(Cataract::Declarations::Value) }
  end

  def test_stylesheet_inspect
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    inspect_str = sheet.inspect
    assert_includes inspect_str, 'Stylesheet'
    assert_includes inspect_str, '2 rules'
  end

  def test_round_trip
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # Parse the result again
    sheet2 = Cataract.parse_css(result)
    assert_equal sheet.size, sheet2.size
  end

  def test_round_trip_bootstrap
    css = File.read('test/fixtures/bootstrap.css')
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # Should be able to parse the result
    sheet2 = Cataract.parse_css(result)
    assert sheet2.size > 0
  end

  def test_charset_parsing
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_equal 'UTF-8', sheet.charset
    assert_equal 1, sheet.size
  end

  def test_charset_serialization
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # @charset should be first line
    assert_match(/\A@charset "UTF-8";/, result)
    assert_includes result, 'body'
    assert_includes result, 'color: red'
  end

  def test_no_charset
    css = 'body { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_nil sheet.charset
    refute_includes sheet.to_s, '@charset'
  end

  def test_charset_round_trip
    css = '@charset "UTF-8";
.test { margin: 5px; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # Parse again and verify charset preserved
    sheet2 = Cataract.parse_css(result)
    assert_equal 'UTF-8', sheet2.charset
    assert_equal 1, sheet2.size
  end

  def test_bootstrap_charset
    css = File.read('test/fixtures/bootstrap.css')
    sheet = Cataract.parse_css(css)

    # Bootstrap starts with @charset "UTF-8"
    assert_equal 'UTF-8', sheet.charset

    # Verify it's preserved in serialization
    result = sheet.to_s
    assert_match(/\A@charset "UTF-8";/, result)
  end
end
