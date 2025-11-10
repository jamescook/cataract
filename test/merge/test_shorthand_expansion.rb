# frozen_string_literal: true

# Test CSS shorthand/longhand behavior through merge operations
# Verifies that merge correctly expands shorthands when cascading,
# and recreates optimized shorthands in the final output
class TestShorthandExpansion < Minitest::Test
  # Helper to parse CSS and merge rules
  def parse_and_merge(css)
    sheet = Cataract.parse_css(css)
    merged = sheet.merge

    # The merged stylesheet should have exactly one rule with all declarations
    # (or no rules for empty input)
    return Cataract::Declarations.new([]) if merged.rules_count.zero?

    Cataract::Declarations.new(merged.rules.first.declarations)
  end

  # ===========================================================================
  # Margin - Cascading and Override Behavior
  # ===========================================================================

  def test_margin_shorthand_overrides_longhand
    # Shorthand declared after longhand should win
    decls = parse_and_merge('.test { margin-top: 5px; margin: 10px }')

    assert_equal '10px', decls['margin']
    assert_nil decls['margin-top']
  end

  def test_margin_longhand_overrides_shorthand
    # Longhand after shorthand should override that side only
    decls = parse_and_merge('.test { margin: 10px; margin-top: 20px }')

    # Should have optimized shorthand with top overridden
    assert_equal '20px 10px 10px', decls['margin']
    assert_nil decls['margin-top']
  end

  def test_margin_partial_override
    # Override two sides
    decls = parse_and_merge('.test { margin: 10px; margin-top: 20px; margin-bottom: 30px }')

    # Should create shorthand from mixed values
    assert_equal '20px 10px 30px', decls['margin']
  end

  def test_margin_all_different_sides
    # Four different values stay as 4-value shorthand
    decls = parse_and_merge('.test { margin-top: 1px; margin-right: 2px; margin-bottom: 3px; margin-left: 4px }')

    assert_equal '1px 2px 3px 4px', decls['margin']
  end

  def test_margin_important_prevents_override
    # !important longhand should not be overridden by normal shorthand
    decls = parse_and_merge('.test { margin-top: 5px !important; margin: 10px }')

    # Should keep longhand important, others from shorthand
    assert_equal '5px !important', decls['margin-top']
    assert_equal '10px', decls['margin-right']
    assert_equal '10px', decls['margin-bottom']
    assert_equal '10px', decls['margin-left']
  end

  def test_margin_all_important_creates_shorthand
    # All sides with same !important should create shorthand
    decls = parse_and_merge('.test { margin-top: 10px !important; margin-right: 10px !important; margin-bottom: 10px !important; margin-left: 10px !important }')

    assert_equal '10px !important', decls['margin']
  end

  # ===========================================================================
  # Padding - Verify Same Behavior
  # ===========================================================================

  def test_padding_longhand_overrides_shorthand
    decls = parse_and_merge('.test { padding: 5px; padding-left: 10px }')

    assert_equal '5px 5px 5px 10px', decls['padding']
  end

  def test_padding_all_same
    decls = parse_and_merge('.test { padding-top: 8px; padding-right: 8px; padding-bottom: 8px; padding-left: 8px }')

    assert_equal '8px', decls['padding']
  end

  # ===========================================================================
  # Border - Complex Multi-Property Shorthand
  # ===========================================================================

  def test_border_width_override
    decls = parse_and_merge('.test { border: 1px solid red; border-top-width: 3px }')

    # Should have border-width/style/color but not full border
    assert_equal '3px 1px 1px', decls['border-width']
    assert_equal 'solid', decls['border-style']
    assert_equal 'red', decls['border-color']
    assert_nil decls['border']
  end

  def test_border_all_sides_same
    decls = parse_and_merge('.test { border-top: 2px dashed blue; border-right: 2px dashed blue; border-bottom: 2px dashed blue; border-left: 2px dashed blue }')

    # Should create full border shorthand
    assert_equal '2px dashed blue', decls['border']
  end

  def test_border_mixed_sides
    decls = parse_and_merge('.test { border-top: 1px solid red; border-bottom: 2px dotted blue }')

    # Side shorthands are expanded to individual properties
    assert_equal '1px', decls['border-top-width']
    assert_equal 'solid', decls['border-top-style']
    assert_equal 'red', decls['border-top-color']
    assert_equal '2px', decls['border-bottom-width']
    assert_equal 'dotted', decls['border-bottom-style']
    assert_equal 'blue', decls['border-bottom-color']
  end

  # ===========================================================================
  # Font - Requires Minimum Properties
  # ===========================================================================

  def test_font_override_family
    decls = parse_and_merge('.test { font: 12px Arial; font-family: Helvetica }')

    # Should recreate font with new family
    assert_equal '12px Helvetica', decls['font']
  end

  def test_font_incomplete_properties
    # Only size, no family - should not create shorthand
    decls = parse_and_merge('.test { font-size: 14px; font-weight: bold }')

    assert_equal '14px', decls['font-size']
    assert_equal 'bold', decls['font-weight']
    assert_nil decls['font']
  end

  # ===========================================================================
  # List-Style - Multiple Properties
  # ===========================================================================

  def test_list_style_override
    decls = parse_and_merge('.test { list-style: square inside; list-style-type: circle }')

    # Should recreate with new type
    assert_equal 'circle inside', decls['list-style']
  end

  def test_list_style_single_property
    # Single property should not create shorthand
    decls = parse_and_merge('.test { list-style-type: disc }')

    assert_equal 'disc', decls['list-style-type']
    assert_nil decls['list-style']
  end

  # ===========================================================================
  # Background - Multiple Properties
  # ===========================================================================

  def test_background_override
    decls = parse_and_merge('.test { background: red; background-image: url(img.png) }')

    # Should recreate with both
    assert_equal 'red url(img.png)', decls['background']
  end

  def test_background_single_property
    # Single property should not create shorthand
    decls = parse_and_merge('.test { background-color: blue }')

    assert_equal 'blue', decls['background-color']
    assert_nil decls['background']
  end

  # ===========================================================================
  # Specificity - Different Selectors Stay Separate
  # ===========================================================================

  def test_different_selectors_separate
    # Different selectors should not merge - this tests correct CSS semantics
    sheet = Cataract.parse_css('.test { margin: 10px } #id { margin-top: 20px }')
    merged = sheet.merge

    # Should have 2 separate rules
    assert_equal 2, merged.rules_count

    # .test rule should have margin shorthand
    test_rule = merged.rules.find { |r| r.selector == '.test' }
    test_decls = Cataract::Declarations.new(test_rule.declarations)

    assert_equal '10px', test_decls['margin']

    # #id rule should have margin-top
    id_rule = merged.rules.find { |r| r.selector == '#id' }
    id_decls = Cataract::Declarations.new(id_rule.declarations)

    assert_equal '20px', id_decls['margin-top']
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  def test_calc_values
    decls = parse_and_merge('.test { margin: 10px calc(100% - 20px) }')

    # Should preserve calc() in shorthand
    assert_equal '10px calc(100% - 20px)', decls['margin']
  end

  def test_empty_input
    decls = parse_and_merge('.test { }')

    assert_equal 0, decls.to_a.length
  end
end
