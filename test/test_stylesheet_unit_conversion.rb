# frozen_string_literal: true

require_relative 'test_helper'
require 'cataract/unit_conversion'

class TestStylesheetUnitConversion < Minitest::Test
  # ============================================================================
  # Basic px to rem conversion
  # ============================================================================

  def test_convert_units_px_to_rem_basic
    css = '.box { font-size: 16px; margin: 32px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { font-size: 1rem; margin: 2rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_bang_mutates_original
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    sheet.convert_units!(from: :px, to: :rem)

    expected = '.box { font-size: 1rem; }'

    assert_equal expected, sheet.to_s.chomp
  end

  def test_convert_units_non_mutating_preserves_original
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # Original unchanged
    assert_equal '.box { font-size: 16px; }', sheet.to_s.chomp
    # Result is converted
    assert_equal '.box { font-size: 1rem; }', result.to_s.chomp
  end

  def test_convert_units_with_custom_base_font_size
    css = '.box { font-size: 20px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem, base_font_size: 10)

    expected = '.box { font-size: 2rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_default_base_font_size_is_16
    css = '.box { font-size: 32px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { font-size: 2rem; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # rem to px conversion
  # ============================================================================

  def test_convert_units_rem_to_px
    css = '.box { font-size: 2rem; margin: 1.5rem; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :rem, to: :px)

    expected = '.box { font-size: 32px; margin: 24px; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_rem_to_px_custom_base
    css = '.box { font-size: 2rem; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :rem, to: :px, base_font_size: 10)

    expected = '.box { font-size: 20px; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Absolute unit conversions (px, cm, mm, in, pt, pc)
  # ============================================================================

  def test_convert_units_px_to_cm
    css = '.box { width: 96px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :cm)

    # 96px = 1in = 2.54cm
    expected = '.box { width: 2.54cm; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_px_to_in
    css = '.box { width: 96px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :in)

    expected = '.box { width: 1in; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_px_to_pt
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :pt)

    # 1in = 96px = 72pt, so 16px = 12pt
    expected = '.box { font-size: 12pt; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_cm_to_px
    css = '.box { width: 2.54cm; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :cm, to: :px)

    expected = '.box { width: 96px; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_in_to_px
    css = '.box { width: 1in; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :in, to: :px)

    expected = '.box { width: 96px; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_pt_to_px
    css = '.box { font-size: 12pt; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :pt, to: :px)

    expected = '.box { font-size: 16px; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Properties to convert by default
  # ============================================================================

  def test_convert_units_margin_properties
    css = '.box { margin: 16px; margin-top: 8px; margin-left: 24px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { margin: 1rem; margin-top: 0.5rem; margin-left: 1.5rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_padding_properties
    css = '.box { padding: 32px; padding-right: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { padding: 2rem; padding-right: 1rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_border_width_properties
    css = '.box { border-width: 2px; border-top-width: 4px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { border-width: 0.125rem; border-top-width: 0.25rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_typography_properties
    css = '.text { font-size: 16px; letter-spacing: 2px; word-spacing: 4px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.text { font-size: 1rem; letter-spacing: 0.125rem; word-spacing: 0.25rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_text_indent
    css = '.paragraph { text-indent: 32px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.paragraph { text-indent: 2rem; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Properties excluded by default
  # ============================================================================

  def test_convert_units_skips_line_height_by_default
    css = '.text { font-size: 16px; line-height: 24px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # font-size converted, line-height skipped
    expected = '.text { font-size: 1rem; line-height: 24px; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_can_include_line_height_explicitly
    css = '.text { font-size: 16px; line-height: 24px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem, properties: %w[font-size line-height])

    # Both converted when explicitly included
    expected = '.text { font-size: 1rem; line-height: 1.5rem; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Property filtering options
  # ============================================================================

  def test_convert_units_with_specific_properties_list
    css = '.box { margin: 16px; padding: 16px; font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem, properties: %w[margin font-size])

    # Only margin and font-size converted
    expected = '.box { margin: 1rem; padding: 16px; font-size: 1rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_with_exclude_properties
    css = '.box { margin: 16px; padding: 16px; font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem, exclude_properties: ['padding'])

    # padding excluded, others converted
    expected = '.box { margin: 1rem; padding: 16px; font-size: 1rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_properties_all_converts_everything
    css = '.box { margin: 16px; line-height: 24px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem, properties: :all)

    # Even line-height is converted when properties: :all
    expected = '.box { margin: 1rem; line-height: 1.5rem; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  def test_convert_units_preserves_zero_without_units
    css = '.box { margin: 0; padding: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # 0 stays as 0 (unitless)
    expected = '.box { margin: 0; padding: 1rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_preserves_zero_with_units
    css = '.box { margin: 0px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # 0px can be converted to 0rem or stay as 0 (both valid)
    # Implementation should normalize to unitless 0
    expected = '.box { margin: 0; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_preserves_negative_values
    css = '.box { margin: -16px; margin-top: -8px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { margin: -1rem; margin-top: -0.5rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_skips_calc_expressions
    css = '.box { width: calc(100% - 16px); }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # calc() expressions not modified (too complex)
    expected = '.box { width: calc(100% - 16px); }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_skips_var_expressions
    css = '.box { margin: var(--spacing, 16px); }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # var() expressions not modified
    expected = '.box { margin: var(--spacing, 16px); }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_skips_min_max_clamp
    css = '.box { width: min(100px, 50%); height: max(200px, 10rem); font-size: clamp(12px, 2vw, 24px); }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # min/max/clamp expressions not modified (too complex)
    expected = '.box { width: min(100px, 50%); height: max(200px, 10rem); font-size: clamp(12px, 2vw, 24px); }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_skips_values_without_matching_units
    css = '.box { width: 100%; font-size: 16px; color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # Only font-size converted (has px), width and color unchanged
    expected = '.box { width: 100%; font-size: 1rem; color: red; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Precision handling
  # ============================================================================

  def test_convert_units_default_precision
    css = '.box { font-size: 13px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # 13 / 16 = 0.8125 (default precision should handle this cleanly)
    expected = '.box { font-size: 0.8125rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_with_custom_precision
    css = '.box { font-size: 13px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem, precision: 2)

    # Round to 2 decimal places
    expected = '.box { font-size: 0.81rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_strips_trailing_zeros
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # 16 / 16 = 1.0000 -> should be "1rem" not "1.0000rem"
    expected = '.box { font-size: 1rem; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Multiple values in single property
  # ============================================================================

  def test_convert_units_with_multiple_values
    css = '.box { margin: 16px 32px 8px 24px; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    expected = '.box { margin: 1rem 2rem 0.5rem 1.5rem; }'

    assert_equal expected, result.to_s.chomp
  end

  def test_convert_units_with_mixed_units_in_value
    css = '.box { padding: 16px 2rem; }'
    sheet = Cataract::Stylesheet.parse(css)

    result = sheet.convert_units(from: :px, to: :rem)

    # Only px values converted, rem stays as-is
    expected = '.box { padding: 1rem 2rem; }'

    assert_equal expected, result.to_s.chomp
  end

  # ============================================================================
  # Complex scenarios
  # ============================================================================

  def test_convert_units_across_multiple_rules
    css = <<~CSS
      .header { font-size: 24px; margin: 16px; }
      .body { font-size: 16px; padding: 32px; }
      .footer { font-size: 14px; margin: 8px; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.convert_units(from: :px, to: :rem)

    header = result.rules.find { |r| r.selector == '.header' }
    body = result.rules.find { |r| r.selector == '.body' }
    footer = result.rules.find { |r| r.selector == '.footer' }

    assert_has_property({ 'font-size' => '1.5rem' }, header)
    assert_has_property({ 'margin' => '1rem' }, header)
    assert_has_property({ 'font-size' => '1rem' }, body)
    assert_has_property({ 'padding' => '2rem' }, body)
    assert_has_property({ 'font-size' => '0.875rem' }, footer)
    assert_has_property({ 'margin' => '0.5rem' }, footer)
  end

  def test_convert_units_with_media_queries
    css = <<~CSS
      .box { font-size: 16px; }
      @media screen { .box { font-size: 20px; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.convert_units(from: :px, to: :rem)

    # Get .box rule in base context (media: :all means no @media wrapper)
    base_box = result.with_selector('.box').first

    assert_has_property({ 'font-size' => '1rem' }, base_box)

    # Get .box rule in @media screen context
    screen_box = result.with_media(:screen).with_selector('.box').first

    assert_has_property({ 'font-size' => '1.25rem' }, screen_box)
  end

  def test_convert_units_with_nested_selectors
    css = <<~CSS
      .parent {
        font-size: 16px;
        .child {
          font-size: 14px;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.convert_units(from: :px, to: :rem)

    # Nested selectors are resolved to full selectors
    parent = result.with_selector('.parent').first
    child = result.with_selector('.parent .child').first

    assert_has_property({ 'font-size' => '1rem' }, parent)
    assert_has_property({ 'font-size' => '0.875rem' }, child)
  end

  # ============================================================================
  # Error cases
  # ============================================================================

  def test_convert_units_requires_from_parameter
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_raises(ArgumentError) do
      sheet.convert_units(to: :rem)
    end
  end

  def test_convert_units_requires_to_parameter
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_raises(ArgumentError) do
      sheet.convert_units(from: :px)
    end
  end

  def test_convert_units_rejects_unsupported_units
    css = '.box { font-size: 16px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_raises(ArgumentError) do
      sheet.convert_units(from: :px, to: :unsupported)
    end
  end

  def test_convert_units_rejects_context_dependent_conversions
    css = '.box { width: 50%; }'
    sheet = Cataract::Stylesheet.parse(css)

    # % to px requires parent context - not supported
    assert_raises(ArgumentError) do
      sheet.convert_units(from: :percent, to: :px)
    end
  end
end
