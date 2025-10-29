#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'

class TestStylesheet < Minitest::Test
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

  # ============================================================================
  # each_selector - Iterator tests
  # ============================================================================

  def test_each_selector_basic
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector do |selector, declarations, specificity, media_types|
      selectors << selector
    end

    assert_equal ['body', 'div'], selectors
  end

  def test_each_selector_yields_all_components
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)

    sheet.each_selector do |selector, declarations, specificity, media_types|
      assert_equal 'body', selector
      assert_kind_of String, declarations
      assert_includes declarations, 'color: red'
      assert_includes declarations, 'margin: 10px'
      assert_kind_of Integer, specificity
      assert_equal [:all], media_types
    end
  end

  def test_each_selector_with_important
    css = 'div { color: blue !important; }'
    sheet = Cataract.parse_css(css)

    sheet.each_selector do |selector, declarations, specificity, media_types|
      assert_includes declarations, '!important'
    end
  end

  def test_each_selector_returns_enumerator
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    enum = sheet.each_selector
    assert_kind_of Enumerator, enum
    assert_equal 2, enum.count
  end

  def test_each_selector_with_media_all
    css = <<~CSS
      body { color: black; }
      @media print {
        body { color: white; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :all) do |selector, declarations, specificity, media_types|
      selectors << [selector, media_types]
    end

    # :all should return ALL rules
    assert_equal 2, selectors.length
    assert_equal ['body', [:all]], selectors[0]
    assert_equal ['body', [:print]], selectors[1]
  end

  def test_each_selector_with_media_print
    css = <<~CSS
      body { color: black; }
      @media print {
        body { color: white; }
      }
      @media screen {
        div { color: blue; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :print) do |selector, declarations, specificity, media_types|
      selectors << [selector, media_types]
    end

    # :print should return ONLY print-specific rules (not universal)
    assert_equal 1, selectors.length
    assert_equal ['body', [:print]], selectors[0]
  end

  def test_each_selector_with_media_screen
    css = <<~CSS
      body { color: black; }
      @media screen {
        div { color: blue; }
      }
      @media print {
        body { color: white; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :screen) do |selector, declarations, specificity, media_types|
      selectors << [selector, media_types]
    end

    # :screen should return ONLY screen-specific rules
    assert_equal 1, selectors.length
    assert_equal ['div', [:screen]], selectors[0]
  end

  def test_each_selector_with_multiple_media_types
    css = <<~CSS
      @media screen, print {
        .header { color: black; }
      }
      @media print {
        body { margin: 0; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    # Query for both screen and print
    selectors = []
    sheet.each_selector(media: [:screen, :print]) do |selector, declarations, specificity, media_types|
      selectors << selector
    end

    assert_equal 2, selectors.length
    assert_includes selectors, '.header'
    assert_includes selectors, 'body'
  end

  def test_each_selector_no_matches
    css = '@media print { body { color: black; } }'
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :screen) do |selector, declarations, specificity, media_types|
      selectors << selector
    end

    assert_equal [], selectors
  end

  # ============================================================================
  # each_selector with specificity filtering - New feature
  # ============================================================================

  def test_each_selector_with_specificity_exact
    css = <<~CSS
      body { color: red; }
      div { margin: 10px; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity = 1 (element selectors: body, div)
    matches = []
    sheet.each_selector(specificity: 1) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, 'div'
  end

  def test_each_selector_with_specificity_range
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
      #main .btn { margin: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity 10-100 (class and single ID)
    matches = []
    sheet.each_selector(specificity: 10..100) do |selector, declarations, specificity, media_types|
      matches << [selector, specificity]
    end

    assert_equal 2, matches.length
    assert_includes matches, ['.header', 10]
    assert_includes matches, ['#main', 100]
  end

  def test_each_selector_with_specificity_open_ended_range
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
      #main .btn { margin: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity >= 100 (high specificity)
    matches = []
    sheet.each_selector(specificity: 100..) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, '#main'
    assert_includes matches, '#main .btn'
  end

  def test_each_selector_with_specificity_upper_bound
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
      #main .btn { margin: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity <= 10 (low specificity)
    matches = []
    sheet.each_selector(specificity: ..10) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, '.header'
  end

  def test_each_selector_with_specificity_and_media
    css = <<~CSS
      body { color: black; }
      .header { padding: 5px; }
      @media screen {
        body { color: blue; }
        #main { font-size: 20px; }
      }
      @media print {
        .footer { margin: 0; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    # Find low-specificity rules (<=10) in screen media
    matches = []
    sheet.each_selector(specificity: ..10, media: :screen) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 1, matches.length
    assert_equal 'body', matches[0]
  end

  def test_each_selector_with_specificity_no_matches
    css = 'body { color: red; } .header { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    matches = []
    sheet.each_selector(specificity: 100..) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal [], matches
  end

  def test_each_selector_with_specificity_returns_enumerator
    css = 'body { color: red; } .header { margin: 10px; } #main { padding: 5px; }'
    sheet = Cataract.parse_css(css)

    enum = sheet.each_selector(specificity: 100..)
    assert_kind_of Enumerator, enum
    assert_equal 1, enum.count
  end

  # ============================================================================
  # each_selector with property filtering - New feature
  # ============================================================================

  def test_each_selector_with_property_filter
    css = <<~CSS
      body { color: red; margin: 0; }
      .header { padding: 5px; }
      #main { color: blue; font-size: 14px; }
      .footer { position: relative; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find any selector with 'color' property
    matches = []
    sheet.each_selector(property: 'color') do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, '#main'
  end

  def test_each_selector_with_property_value_filter
    css = <<~CSS
      body { position: absolute; }
      .header { position: relative; }
      #main { position: relative; z-index: 10; }
      .footer { display: relative; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find any selector with ANY property that has value 'relative'
    matches = []
    sheet.each_selector(property_value: 'relative') do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 3, matches.length
    assert_includes matches, '.header'
    assert_includes matches, '#main'
    assert_includes matches, '.footer'
  end

  def test_each_selector_with_property_and_value_filter
    css = <<~CSS
      body { position: absolute; }
      .header { position: relative; }
      #main { position: relative; z-index: 10; }
      .footer { display: relative; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find selectors with specifically 'position: relative'
    matches = []
    sheet.each_selector(property: 'position', property_value: 'relative') do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, '.header'
    assert_includes matches, '#main'
    refute_includes matches, '.footer'
  end

  def test_each_selector_with_property_filter_no_matches
    css = 'body { margin: 0; } .header { padding: 5px; }'
    sheet = Cataract.parse_css(css)

    matches = []
    sheet.each_selector(property: 'color') do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal [], matches
  end

  def test_each_selector_with_property_and_media_filter
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      @media screen {
        body { color: blue; }
        #main { font-size: 20px; }
      }
      @media print {
        .footer { color: black; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    # Find selectors with 'color' in screen media
    matches = []
    sheet.each_selector(property: 'color', media: :screen) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 1, matches.length
    assert_equal 'body', matches[0]
  end

  def test_each_selector_with_property_and_specificity_filter
    css = <<~CSS
      body { color: red; }
      .header { color: blue; }
      #main { color: green; font-size: 14px; }
      #main .btn { padding: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find high-specificity selectors (>= 100) with 'color' property
    matches = []
    sheet.each_selector(property: 'color', specificity: 100..) do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 1, matches.length
    assert_equal '#main', matches[0]
  end

  def test_each_selector_with_important_property_value
    css = <<~CSS
      body { color: red !important; }
      .header { color: blue; }
      #main { color: red; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find selectors with 'color: red' (should match both with and without !important)
    matches = []
    sheet.each_selector(property: 'color', property_value: 'red') do |selector, declarations, specificity, media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, '#main'
  end

  # ============================================================================
  # to_formatted_s - Formatted output tests
  # ============================================================================

  def test_to_formatted_s_basic
    input = 'div p { color: red }'
    expected = <<~CSS
      div p {
        color: red;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s
    assert_equal expected, output
  end

  def test_to_formatted_s_multiple_declarations
    input = 'body { color: red; margin: 0; padding: 10px }'
    expected = <<~CSS
      body {
        color: red; margin: 0; padding: 10px;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s
    assert_equal expected, output
  end

  def test_to_formatted_s_multiple_rules
    input = 'body { color: red } .btn { padding: 10px }'
    expected = <<~CSS
      body {
        color: red;
      }
      .btn {
        padding: 10px;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s
    assert_equal expected, output
  end

  def test_to_formatted_s_with_media_query
    input = '@media (min-width: 768px) { .container { width: 750px } }'
    expected = <<~CSS
      @media (min-width: 768px) {
        .container {
          width: 750px;
        }
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s
    assert_equal expected, output
  end

  def test_to_formatted_s_with_charset
    input = '@charset "UTF-8"; body { color: red }'
    expected = <<~CSS
      @charset "UTF-8";
      body {
        color: red;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s
    assert_equal expected, output
  end

  def test_to_formatted_s_mixed_media_and_universal
    input = 'body { margin: 0 } @media (min-width: 768px) { .container { width: 750px } .btn { padding: 10px } }'
    expected = <<~CSS
      body {
        margin: 0;
      }
      @media (min-width: 768px) {
        .container {
          width: 750px;
        }
        .btn {
          padding: 10px;
        }
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s
    assert_equal expected, output
  end
end
