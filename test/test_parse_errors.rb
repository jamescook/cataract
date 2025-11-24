# frozen_string_literal: true

require_relative 'test_helper'

class TestParseErrors < Minitest::Test
  # ============================================================================
  # Test that parse errors are NOT raised by default (lenient mode)
  # ============================================================================

  def test_lenient_mode_by_default
    # All these should parse without raising errors (default lenient behavior)
    css = <<~CSS
      h1 { color: ; }
      h2 { color: !important; }
      h3 { background red; }
      h4 { }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    assert_instance_of Cataract::Stylesheet, sheet
  end

  def test_lenient_mode_explicit
    css = 'h1 { color: ; }'
    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: false)

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Test empty_values errors
  # ============================================================================

  def test_empty_value_missing_value_with_semicolon
    css = 'h1 { color: ; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/empty value/i, error.message)
    assert_match(/property 'color'/i, error.message)
    assert_equal 1, error.line
    assert_equal :empty_value, error.error_type
  end

  def test_empty_value_only_important
    css = 'h1 { color: !important; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/empty value/i, error.message)
    assert_match(/property 'color'/i, error.message)
    assert_equal 1, error.line
    assert_equal :empty_value, error.error_type
  end

  def test_empty_value_whitespace_only
    css = 'h1 { color:    ; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/empty value/i, error.message)
    assert_equal :empty_value, error.error_type
  end

  def test_empty_value_multiline
    css = <<~CSS
      body { margin: 10px; }
      h1 {
        color: red;
        background: ;
        padding: 5px;
      }
    CSS

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/empty value/i, error.message)
    assert_match(/property 'background'/i, error.message)
    assert_equal 4, error.line # background: ; is on line 4
    assert_equal :empty_value, error.error_type
  end

  def test_empty_value_granular_control
    css = 'h1 { color: ; }'

    # Error when empty_values: true
    assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: { empty_values: true })
    end

    # No error when empty_values: false
    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: { empty_values: false })

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Test malformed_declarations errors
  # ============================================================================

  def test_malformed_declaration_missing_colon
    css = 'h1 { color red; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/malformed declaration/i, error.message)
    assert_equal 1, error.line
    assert_equal :malformed_declaration, error.error_type
  end

  def test_malformed_declaration_missing_value_and_semicolon
    css = 'h1 { color: }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/malformed declaration|empty value/i, error.message)
    assert_equal 1, error.line
  end

  def test_malformed_declaration_only_property_name
    css = 'h1 { color }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/malformed declaration/i, error.message)
    assert_equal :malformed_declaration, error.error_type
  end

  def test_malformed_declaration_granular_control
    css = 'h1 { color red; }'

    # Error when malformed_declarations: true
    assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: { malformed_declarations: true })
    end

    # No error when malformed_declarations: false
    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: { malformed_declarations: false })

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Test invalid_selectors errors
  # ============================================================================

  def test_invalid_selector_empty
    css = '{ color: red; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/invalid selector/i, error.message)
    assert_equal 1, error.line
    assert_equal :invalid_selector, error.error_type
  end

  def test_invalid_selector_starts_with_combinator
    css = '> div { color: red; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/invalid selector/i, error.message)
    assert_match(/combinator/i, error.message)
    assert_equal :invalid_selector, error.error_type
  end

  def test_invalid_selector_only_whitespace
    css = '   { color: red; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/invalid selector/i, error.message)
    assert_equal :invalid_selector, error.error_type
  end

  def test_invalid_selector_granular_control
    css = '{ color: red; }'

    # Error when invalid_selectors: true
    assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: { invalid_selectors: true })
    end

    # No error when invalid_selectors: false
    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: { invalid_selectors: false })

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Test malformed_at_rules errors
  # ============================================================================

  def test_malformed_at_rule_media_missing_query
    css = '@media { body { color: red; } }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/malformed @media/i, error.message)
    assert_match(/missing.*query|condition/i, error.message)
    assert_equal 1, error.line
    assert_equal :malformed_at_rule, error.error_type
  end

  def test_malformed_at_rule_supports_missing_condition
    css = '@supports { body { color: red; } }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/malformed @supports/i, error.message)
    assert_match(/missing.*condition/i, error.message)
    assert_equal :malformed_at_rule, error.error_type
  end

  def test_malformed_at_rule_granular_control
    css = '@media { body { color: red; } }'

    # Error when malformed_at_rules: true
    assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: { malformed_at_rules: true })
    end

    # No error when malformed_at_rules: false
    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: { malformed_at_rules: false })

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Test unclosed_blocks errors (do this last - most complex)
  # ============================================================================

  def test_unclosed_block_missing_closing_brace
    css = 'h1 { color: red;'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/unclosed block|missing closing brace/i, error.message)
    assert_equal 1, error.line
    assert_equal :unclosed_block, error.error_type
  end

  def test_unclosed_block_nested_media
    css = '@media screen { h1 { color: red; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_match(/unclosed block|missing closing brace/i, error.message)
    # Note: error_type not set for unclosed blocks (simple rb_raise for performance)
  end

  def test_unclosed_block_granular_control
    css = 'h1 { color: red;'

    # Error when unclosed_blocks: true
    assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: { unclosed_blocks: true })
    end

    # No error when unclosed_blocks: false
    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: { unclosed_blocks: false })

    assert_instance_of Cataract::Stylesheet, sheet
  end

  # ============================================================================
  # Test multiple errors (should raise first encountered)
  # ============================================================================

  def test_multiple_errors_raises_first
    css = <<~CSS
      h1 { color: ; }
      h2 { background red; }
    CSS

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    # Should raise error from line 1 (first error encountered)
    assert_equal 1, error.line
  end

  # ============================================================================
  # Test that valid CSS still works with strict mode
  # ============================================================================

  def test_valid_css_with_strict_mode
    css = <<~CSS
      h1 { color: red; background: blue; }
      @media screen and (min-width: 768px) {
        body { margin: 0; }
      }
      .custom { --my-var: 10px; }
    CSS

    sheet = Cataract::Stylesheet.parse(css, raise_parse_errors: true)

    assert_instance_of Cataract::Stylesheet, sheet
    assert_equal 3, sheet.rules.count
  end

  # ============================================================================
  # Test ParseError attributes
  # ============================================================================

  def test_parse_error_has_attributes
    css = 'h1 { color: ; }'

    error = assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.parse(css, raise_parse_errors: true)
    end

    assert_respond_to error, :line
    assert_respond_to error, :column
    assert_respond_to error, :error_type

    assert_equal 1, error.line
    assert_equal :empty_value, error.error_type
    # column may be nil if not tracked yet
  end
end
