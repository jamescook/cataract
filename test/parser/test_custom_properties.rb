# frozen_string_literal: true

require 'test_helper'

class TestParserCustomProperties < Minitest::Test
  def test_custom_properties_preserve_case
    # CSS custom properties are case-sensitive per spec
    css = '.btn { --myColor: red; }'
    sheet = Cataract::Stylesheet.parse(css)
    rule = sheet.rules.first
    decl = rule.declarations.first

    assert_equal '--myColor', decl.property
    assert_equal 'red', decl.value
  end

  def test_custom_properties_with_uppercase
    css = '.btn { --PRIMARY-COLOR: blue; }'
    sheet = Cataract::Stylesheet.parse(css)
    rule = sheet.rules.first
    decl = rule.declarations.first

    assert_equal '--PRIMARY-COLOR', decl.property
    assert_equal 'blue', decl.value
  end

  def test_different_cased_custom_properties_are_distinct
    # --Color and --color should be treated as different properties
    css = ':root { --Color: red; --color: blue; }'
    sheet = Cataract::Stylesheet.parse(css)
    rule = sheet.rules.first

    assert_equal 2, rule.declarations.size
    assert_equal '--Color', rule.declarations[0].property
    assert_equal 'red', rule.declarations[0].value
    assert_equal '--color', rule.declarations[1].property
    assert_equal 'blue', rule.declarations[1].value
  end

  def test_regular_properties_still_lowercased
    # Regular CSS properties should still be normalized to lowercase
    css = '.btn { Color: red; MARGIN: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)
    rule = sheet.rules.first

    assert_equal 2, rule.declarations.size
    assert_equal 'color', rule.declarations[0].property
    assert_equal 'margin', rule.declarations[1].property
  end

  def test_custom_property_with_mixed_case_in_value
    # Values should preserve case
    css = '.btn { --font: MyCustomFont; }'
    sheet = Cataract::Stylesheet.parse(css)
    rule = sheet.rules.first
    decl = rule.declarations.first

    assert_equal '--font', decl.property
    assert_equal 'MyCustomFont', decl.value
  end

  def test_custom_properties_unicode_normalization_distinct
    # Per W3C spec: custom properties use direct codepoint comparison
    # U+00F3 (LATIN SMALL LETTER O WITH ACUTE) vs
    # U+006F U+0301 (LATIN SMALL LETTER O + COMBINING ACUTE ACCENT)
    # These should be treated as DISTINCT properties
    prop1 = "--fo\u{00F3}" # Precomposed ó
    prop2 = "--foo\u{0301}" # o + combining accent

    css = ":root { #{prop1}: red; #{prop2}: blue; }"
    sheet = Cataract::Stylesheet.parse(css)
    rule = sheet.rules.first

    assert_equal 2, rule.declarations.size, 'Should have 2 distinct properties'
    assert_equal prop1, rule.declarations[0].property
    assert_equal 'red', rule.declarations[0].value
    assert_equal prop2, rule.declarations[1].property
    assert_equal 'blue', rule.declarations[1].value

    # Verify they are actually different at the byte level
    refute_equal rule.declarations[0].property, rule.declarations[1].property
  end
end
