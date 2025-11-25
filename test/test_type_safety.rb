# frozen_string_literal: true

require_relative 'test_helper'

# Test type checking in C extension constructor and methods
# Ensures proper Check_Type usage and appropriate TypeError raising
class TestTypeSafety < Minitest::Test
  # ============================================================================
  # Stylesheet.parse / Stylesheet.new type validation
  # ============================================================================

  def test_parse_requires_string_css
    assert_raises(TypeError) { Cataract::Stylesheet.parse(nil) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(123) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse([]) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse({}) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(:symbol) }
  end

  def test_parse_accepts_valid_string
    # Should not raise
    sheet = Cataract::Stylesheet.parse('body { margin: 0; }')

    assert_instance_of Cataract::Stylesheet, sheet
  end

  def test_parse_accepts_empty_string
    # Should not raise
    sheet = Cataract::Stylesheet.parse('')

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Options hash type validation
  # ============================================================================

  def test_new_options_must_be_hash
    # Stylesheet.new validates options hash
    assert_raises(TypeError) { Cataract::Stylesheet.new('not a hash') }
    assert_raises(TypeError) { Cataract::Stylesheet.new(123) }
    assert_raises(TypeError) { Cataract::Stylesheet.new([]) }
    assert_raises(TypeError) { Cataract::Stylesheet.new(:symbol) }
  end

  def test_new_accepts_valid_options_hash
    # Should not raise
    sheet = Cataract::Stylesheet.new({})

    assert_instance_of Cataract::Stylesheet, sheet

    sheet = Cataract::Stylesheet.new

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Parser options type validation
  # ============================================================================

  def test_parser_selector_lists_option_type
    css = 'h1, h2 { color: red; }'

    # Should handle truthy/falsy values gracefully
    Cataract::Stylesheet.parse(css, parser: { selector_lists: true })
    Cataract::Stylesheet.parse(css, parser: { selector_lists: false })
    Cataract::Stylesheet.parse(css, parser: { selector_lists: nil })
    Cataract::Stylesheet.parse(css, parser: { selector_lists: 1 })
    Cataract::Stylesheet.parse(css, parser: { selector_lists: 'yes' })
  end

  def test_parser_raise_parse_errors_option_type
    css = 'body { margin: 0; }'

    # Boolean
    Cataract::Stylesheet.parse(css, parser: { raise_parse_errors: true })
    Cataract::Stylesheet.parse(css, parser: { raise_parse_errors: false })

    # Hash with granular options
    Cataract::Stylesheet.parse(css, parser: { raise_parse_errors: { empty_values: true } })

    # Invalid types should be handled gracefully (RTEST will check truthiness)
    Cataract::Stylesheet.parse(css, parser: { raise_parse_errors: nil })
    Cataract::Stylesheet.parse(css, parser: { raise_parse_errors: 1 })
    Cataract::Stylesheet.parse(css, parser: { raise_parse_errors: 'yes' })
  end

  # ============================================================================
  # Import fetcher option type validation
  # ============================================================================

  def test_import_fetcher_must_be_proc_or_nil
    css = "@import 'test.css';"

    # Nil should work (default behavior)
    Cataract::Stylesheet.parse(css, import_fetcher: nil)

    # Proc should work
    fetcher = proc { |_url| 'body { margin: 0; }' }
    Cataract::Stylesheet.parse(css, import_fetcher: fetcher)

    # Lambda should work
    fetcher = ->(_url) { 'body { margin: 0; }' }
    Cataract::Stylesheet.parse(css, import_fetcher: fetcher)

    # Invalid types should raise
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, import_fetcher: 'not a proc') }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, import_fetcher: 123) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, import_fetcher: {}) }
  end

  # ============================================================================
  # Base URI option type validation
  # ============================================================================

  def test_base_uri_must_be_string_or_nil
    css = "body { background: url('image.png'); }"

    # Nil should work (default behavior)
    Cataract::Stylesheet.parse(css, base_uri: nil)

    # String should work
    Cataract::Stylesheet.parse(css, base_uri: 'http://example.com/')

    # Invalid types should raise
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, base_uri: 123) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, base_uri: []) }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, base_uri: {}) }
  end

  # ============================================================================
  # URI resolver option type validation
  # ============================================================================

  def test_uri_resolver_must_be_proc_or_nil
    css = "body { background: url('image.png'); }"

    # Nil should work (default behavior)
    Cataract::Stylesheet.parse(css, uri_resolver: nil)

    # Proc should work
    resolver = proc { |_base, _relative| 'http://example.com/image.png' }
    Cataract::Stylesheet.parse(css, base_uri: 'http://example.com/', uri_resolver: resolver)

    # Invalid types should raise
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, uri_resolver: 'not a proc') }
    assert_raises(TypeError) { Cataract::Stylesheet.parse(css, uri_resolver: 123) }
  end

  # ============================================================================
  # add_block type validation
  # ============================================================================

  def test_add_block_requires_string
    sheet = Cataract::Stylesheet.parse('body { margin: 0; }')

    assert_raises(TypeError) { sheet.add_block(nil) }
    assert_raises(TypeError) { sheet.add_block(123) }
    assert_raises(TypeError) { sheet.add_block([]) }
    assert_raises(TypeError) { sheet.add_block({}) }
  end

  def test_add_block_accepts_valid_string
    sheet = Cataract::Stylesheet.parse('body { margin: 0; }')

    # Should not raise
    sheet.add_block('h1 { color: red; }')

    assert_equal 2, sheet.rules.count
  end

  # ============================================================================
  # flatten type validation
  # ============================================================================

  def test_flatten_requires_no_arguments
    sheet = Cataract::Stylesheet.parse('h1 { color: red; } h1 { margin: 0; }')

    # Should not raise
    flattened = sheet.flatten

    assert_instance_of Cataract::Stylesheet, flattened
  end

  # ============================================================================
  # to_s / serialize type validation
  # ============================================================================

  def test_to_s_requires_no_arguments
    sheet = Cataract::Stylesheet.parse('body { margin: 0; }')

    # Should not raise
    css = sheet.to_s

    assert_instance_of String, css
  end

  # ============================================================================
  # Encoding validation
  # ============================================================================

  def test_parse_handles_valid_encodings
    # UTF-8 (default)
    Cataract::Stylesheet.parse('body { margin: 0; }'.encode('UTF-8'))

    # ASCII (compatible with UTF-8)
    Cataract::Stylesheet.parse("\xEF\xBB\xBF" + 'body { margin: 0; }') # rubocop:disable Style/StringConcatenation

    # UTF-8 with BOM
    Cataract::Stylesheet.parse('﻿body { margin: 0; }')
  end

  def test_parse_handles_non_utf8_encodings
    # Should handle conversion internally
    css = 'body { margin: 0; }'.encode('ISO-8859-1')
    sheet = Cataract::Stylesheet.parse(css)

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  def test_parse_handles_frozen_strings
    css = 'body { margin: 0; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_instance_of Cataract::Stylesheet, sheet
  end

  def test_add_block_handles_frozen_strings
    sheet = Cataract::Stylesheet.parse('body { margin: 0; }')
    css = 'h1 { color: red; }'

    # Should not raise
    sheet.add_block(css)

    assert_equal 2, sheet.rules.count
  end

  # ============================================================================
  # Nil checks for options
  # ============================================================================

  def test_new_handles_nil_parser_options
    # Nil parser options should use defaults
    sheet = Cataract::Stylesheet.new(parser: nil)

    assert_instance_of Cataract::Stylesheet, sheet
  end
end
