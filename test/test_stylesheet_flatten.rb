require_relative 'test_helper'

class TestStylesheetFlatten < Minitest::Test
  # ============================================================================
  # Stylesheet flattening tests (flatten, cascade)
  # ============================================================================

  def test_flatten_applies_cascade
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.flatten

    assert_equal 1, result.rules.size
    assert result.rules.first.has_property?('color', 'blue'), 'Should apply cascade (last rule wins)'
  end

  def test_flatten_returns_new_stylesheet
    sheet = Cataract.parse_css('.box { color: red; }')

    result = sheet.flatten

    refute_same sheet, result, 'flatten should return new stylesheet'
  end

  def test_flatten_bang_mutates_stylesheet
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')
    original_object_id = sheet.object_id

    result = sheet.flatten!

    assert_same sheet, result, 'flatten! should return self'
    assert_equal original_object_id, sheet.object_id, 'flatten! should mutate in place'
    assert_equal 1, sheet.rules.size
  end

  def test_cascade_alias_for_flatten
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.cascade

    assert_equal 1, result.rules.size
    assert result.rules.first.has_property?('color', 'blue')
  end

  def test_cascade_bang_alias_for_flatten_bang
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.cascade!

    assert_same sheet, result
    assert_equal 1, sheet.rules.size
  end

  def test_merge_alias_still_works
    # Keep for backwards compatibility
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    silence_warnings do
      result = sheet.merge

      assert_equal 1, result.rules.size
      assert result.rules.first.has_property?('color', 'blue')
    end
  end

  def test_merge_bang_alias_still_works
    # Keep for backwards compatibility
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    silence_warnings do
      result = sheet.merge!

      assert_same sheet, result
      assert_equal 1, sheet.rules.size
    end
  end

  # ============================================================================
  # Flatten with media queries (from recursive imports)
  # ============================================================================

  def test_flatten_preserves_media_constraints_with_recursive_imports
    # Tests that flatten preserves media query boundaries when rules come from
    # recursive imports with different media conditions

    fixtures_dir = File.join(__dir__, 'fixtures')
    sheet = Cataract::Stylesheet.load_file(
      'recursive_import_base.css',
      fixtures_dir,
      import: { allowed_schemes: ['file'], extensions: ['css'] }
    )

    flattened = sheet.flatten

    # After flatten, we should still have separate body rules for different media contexts:
    # - body for screen+mobile (font-size: 14px)
    # - body for print (background: white !important)
    # - body for base/all (color: black, background: white)

    body_rules = flattened.rules.select { |r| r.selector == 'body' }

    # Should have at least 2 separate body rules (print and base)
    # They should NOT be merged because they're in different media contexts
    assert_operator body_rules.length, :>=, 2, 'Should have at least 2 separate body rules after flatten (different media contexts)'

    # Test observable behavior: Query rules by media type
    # Rules with .print-only should only appear in print media
    print_rules = flattened.with_media(:print).to_a
    print_selectors = print_rules.map(&:selector)

    assert_includes print_selectors, '.print-only', 'Print media should include .print-only'

    # Rules with .screen-only should only appear in screen media
    screen_rules = flattened.with_media(:screen).to_a
    screen_selectors = screen_rules.map(&:selector)

    assert_includes screen_selectors, '.screen-only', 'Screen media should include .screen-only'

    # Base body rule should be queryable without media filter
    all_rules = flattened.to_a

    assert_includes all_rules.map(&:selector), 'body', 'Should have body rules'
  end

  def test_rule_ids_are_sequential_after_flatten
    # Tests that flatten assigns sequential rule IDs starting from 0

    fixtures_dir = File.join(__dir__, 'fixtures')
    sheet = Cataract::Stylesheet.load_file(
      'recursive_import_base.css',
      fixtures_dir,
      import: { allowed_schemes: ['file'], extensions: ['css'] }
    )

    flattened = sheet.flatten

    # After flatten, rule IDs should be sequential from 0
    rule_ids = flattened.rules.map(&:id).sort

    assert_equal (0...flattened.rules.length).to_a, rule_ids,
                 'Rule IDs should be sequential from 0 after flatten'
  end

  def test_cascade_respects_media_query_boundaries
    # Tests that cascade does not merge rules across different media query contexts

    fixtures_dir = File.join(__dir__, 'fixtures')
    sheet = Cataract::Stylesheet.load_file(
      'recursive_import_base.css',
      fixtures_dir,
      import: { allowed_schemes: ['file'], extensions: ['css'] }
    )

    flattened = sheet.flatten

    # The base body rule has background: white
    # The print body rule has background: white !important
    # These should remain separate - print body should not cascade into base body

    # Find body rules and check their declarations
    body_rules = flattened.rules.select { |r| r.selector == 'body' }

    # Look for a body rule with !important background
    important_bg_rule = body_rules.find do |r|
      r.declarations.any? { |d| d.property == 'background' && d.important }
    end

    refute_nil important_bg_rule, 'Should have body rule with !important background (from print media)'

    # Look for a body rule with regular (non-important) background
    regular_bg_rule = body_rules.find do |r|
      r.declarations.any? { |d| d.property == 'background' && !d.important }
    end

    refute_nil regular_bg_rule, 'Should have body rule with regular background (from base CSS)'

    # These should be different rules (different IDs)
    refute_equal important_bg_rule.id, regular_bg_rule.id,
                 'Print and base body rules should not be merged'
  end
end
