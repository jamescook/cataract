# frozen_string_literal: true

require_relative 'test_helper'

class TestEncoding < Minitest::Test
  def test_property_names_are_us_ascii
    css = '* { color: red; font-family: Arial; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    sheet.rules.each do |rule|
      rule.declarations.each do |decl|
        assert_equal Encoding::US_ASCII, decl.property.encoding,
                     "Property '#{decl.property}' should be US-ASCII encoded"
      end
    end
  end

  def test_ascii_property_values_are_utf8
    css = '* { color: red; margin: 10px; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    sheet.rules.each do |rule|
      rule.declarations.each do |decl|
        assert_equal Encoding::UTF_8, decl.value.encoding,
                     "Value '#{decl.value}' should be UTF-8 encoded (even if ASCII-compatible)"
      end
    end
  end

  def test_utf8_property_values_are_utf8
    css = '* { content: "Hello 世界"; font-family: "ＭＳ ゴシック"; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    sheet.rules.each do |rule|
      rule.declarations.each do |decl|
        assert_equal Encoding::UTF_8, decl.value.encoding,
                     "UTF-8 value '#{decl.value}' should be UTF-8 encoded"

        # Verify the UTF-8 content is correct
        if decl.property == 'content'
          assert_includes decl.value, '世界', 'UTF-8 characters should be preserved'
        elsif decl.property == 'font-family'
          assert_includes decl.value, 'ゴシック', 'UTF-8 characters should be preserved'
        end
      end
    end
  end

  def test_emoji_in_content_property
    css = '* { content: "👍 ✨ 🎉"; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    decl = sheet.rules.first.declarations.first

    assert_equal Encoding::UTF_8, decl.value.encoding
    assert_includes decl.value, '👍'
    assert_includes decl.value, '✨'
    assert_includes decl.value, '🎉'
  end

  def test_selectors_with_utf8_are_utf8
    css = '.日本語 { color: red; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_equal Encoding::UTF_8, rule.selector.encoding,
                 'Selector with UTF-8 should be UTF-8 encoded'
    assert_includes rule.selector, '日本語'
  end

  def test_ascii_selectors_are_utf8
    # Selectors should be UTF-8 even if they're ASCII-compatible
    # (to allow concatenation without encoding errors)
    css = '.my-class { color: red; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_equal Encoding::UTF_8, rule.selector.encoding,
                 'ASCII selector should still be UTF-8 encoded for compatibility'
  end

  def test_flatten_property_names_are_us_ascii
    # Property names created by flatten operations should be US-ASCII
    css = '.a { margin-top: 1px; margin-right: 2px; margin-bottom: 3px; margin-left: 4px; }'
    sheet = Cataract::Stylesheet.parse(css)

    flattened_sheet = sheet.flatten

    # Check all declarations in the flattened result
    flattened_sheet.rules.first.declarations.each do |decl|
      assert_equal Encoding::US_ASCII, decl.property.encoding,
                   "Flattened property '#{decl.property}' should be US-ASCII"
    end
  end

  def test_string_concatenation_compatibility
    # This tests that we can safely concatenate our strings with Ruby UTF-8 strings
    css = '* { color: red; }'
    sheet = Cataract::Stylesheet.new
    sheet.add_block(css)

    decl = sheet.rules.first.declarations.first

    # Should not raise Encoding::CompatibilityError
    result = "Property: #{decl.property}, Value: #{decl.value} (日本語)"

    assert_equal Encoding::UTF_8, result.encoding
  end
end
