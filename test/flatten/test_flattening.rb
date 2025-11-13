# frozen_string_literal: true

class TestFlattening < Minitest::Test
  # Test simple flatten of two rules with different properties
  def test_simple_flatten
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test1 { color: black; }
      .test1 { margin: 0px; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'black' }, flattened.rules.first)
    assert_has_property({ margin: '0px' }, flattened.rules.first)
  end

  # Test that later rule with same specificity overwrites earlier
  def test_merging_same_property
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black; }
      .test { color: red; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'red' }, flattened.rules.first)
  end

  # Test that different selectors stay separate (not flattened based on specificity)
  def test_different_selectors_stay_separate
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black; }
      #test { color: red; }
    CSS

    flattened = sheet.flatten

    # Different selectors should stay as separate rules
    assert_equal 2, flattened.rules_count, 'Different selectors should not flatten'

    class_rule = flattened.rules.find { |r| r.selector == '.test' }
    id_rule = flattened.rules.find { |r| r.selector == '#test' }

    assert class_rule, 'Should have .test rule'
    assert id_rule, 'Should have #test rule'
    assert_has_property({ color: 'black' }, class_rule)
    assert_has_property({ color: 'red' }, id_rule)
  end

  # Test that same selector with higher specificity later still flattens (source order matters)
  def test_same_selector_later_wins
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      #test { color: red; }
      #test { color: blue; }
    CSS

    flattened = sheet.flatten

    # Same selector, so should flatten into one rule (later wins)
    assert_equal 1, flattened.rules_count
    assert_equal '#test', flattened.rules.first.selector
    assert_has_property({ color: 'blue' }, flattened.rules.first, 'Later declaration with same selector should win')
  end

  # Test !important within same selector
  def test_important_wins_same_selector
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black !important; }
      .test { color: red; }
    CSS

    flattened = sheet.flatten

    # Same selector, !important should win
    assert_equal 1, flattened.rules_count
    assert_equal '.test', flattened.rules.first.selector
    assert_has_property({ color: 'black !important' }, flattened.rules.first, '!important should win within same selector')
  end

  # Test !important with same selector (later !important wins)
  def test_important_later_wins_same_selector
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: red !important; }
      .test { color: black !important; }
    CSS

    flattened = sheet.flatten

    # Same selector, later !important wins
    assert_equal 1, flattened.rules_count
    assert_equal '.test', flattened.rules.first.selector
    assert_has_property({ color: 'black !important' }, flattened.rules.first, 'Later !important should win with same selector')
  end

  # Test merging with multiple selectors (comma-separated)
  def test_multiple_selectors_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      p, a[rel="external"] { color: black; }
      a { color: blue; }
    CSS

    flattened = sheet.flatten

    # Different selectors should stay separate
    # Note: Parser might split "p, a[rel='external']" into separate rules
    assert_operator flattened.rules_count, :>=, 2, 'Should have multiple rules for different selectors'

    # Find the 'a' rule (should have blue)
    a_rule = flattened.rules.find { |r| r.selector == 'a' }

    assert a_rule, 'Should have rule for "a" selector'
    assert_has_property({ color: 'blue' }, a_rule)
  end

  # Test property names are case-insensitive
  def test_case_insensitive_properties
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { CoLor: red; }
      .test { color: blue; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'blue' }, flattened.rules.first)
  end

  # Test merging backgrounds (requires shorthand expansion)
  def test_merging_backgrounds
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { background-color: black; }
      .test { background-image: none; }
    CSS

    flattened = sheet.flatten

    # background shorthand should be created from multiple properties
    assert_has_property({ background: 'black none' }, flattened.rules.first)
  end

  # Test flattening dimensions (margin expansion then flatten)
  def test_merging_dimensions
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { margin: 3em; }
      .test { margin-left: 1em; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ margin: '3em 3em 3em 1em' }, flattened.rules.first)
  end

  # Test merging fonts
  def test_merging_fonts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { font: 11px Arial; }
      .test { font-weight: bold; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ font: 'bold 11px Arial' }, flattened.rules.first)
  end

  # Test multiple !important with same specificity (last wins)
  def test_multiple_important_same_specificity
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black !important; }
      .test { color: red !important; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'red !important' }, flattened.rules.first)
  end

  # Test !important in same block (last wins)
  def test_important_in_same_block
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black !important; color: red !important; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'red !important' }, flattened.rules.first)
  end

  # Test !important beats non-important in same block
  def test_important_beats_non_important_same_block
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: red; color: black !important; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'black !important' }, flattened.rules.first)
  end

  # Test merging shorthand !important
  def test_shorthand_important
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { background: black none !important; }
      .test { background-color: red; }
    CSS

    flattened = sheet.flatten

    # After expansion and re-creation, background shorthand should be marked !important
    # Normal background-color cannot override !important
    # Note: "black !important" is semantically equivalent to "black none !important"
    # (our optimizer omits default values)
    assert_has_property({ background: 'black !important' }, flattened.rules.first)
    # The !important background wins, normal background-color is ignored
    refute(flattened.rules.first.declarations.any? { |d| d.property == 'background-color' })
  end

  # Test empty flatten (single rule)
  def test_single_rule_flatten
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: red; margin: 10px; }
    CSS

    flattened = sheet.flatten

    assert_has_property({ color: 'red' }, flattened.rules.first)
    assert_has_property({ margin: '10px' }, flattened.rules.first)
  end

  # Test merging with no rules
  def test_empty_flatten
    sheet = Cataract::Stylesheet.new
    flattened = sheet.flatten

    assert_empty flattened.rules
  end

  # Test that uppercase property names are handled correctly
  # Properties should already be lowercase from parser, but test edge cases
  def test_uppercase_properties_are_lowercased
    # Parse CSS with uppercase properties (parser should lowercase them)
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { COLOR: red; MARGIN-TOP: 10px; }
      .test { color: blue; margin-top: 20px; }
    CSS

    flattened = sheet.flatten

    # Should flatten correctly (case-insensitive property matching)
    assert_has_property({ color: 'blue' }, flattened.rules.first)
    assert_has_property({ 'margin-top': '20px' }, flattened.rules.first)

    # Verify properties in flattened result are lowercase
    flattened.rules.first.declarations.each do |decl|
      assert_equal decl.property, decl.property.downcase,
                   "Property '#{decl.property}' should be lowercase in flattened result"
    end
  end

  # Test that shorthand expansion produces lowercase properties
  def test_shorthand_expansion_lowercase
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { margin: 10px 20px; }
    CSS

    flattened = sheet.flatten

    # Shorthand should be expanded to lowercase longhand properties
    flattened.rules.first.declarations.each do |decl|
      assert_equal decl.property, decl.property.downcase,
                   "Expanded property '#{decl.property}' should be lowercase"
    end

    # Should have margin shorthand (or expanded longhands, both lowercase)
    # Just verify all properties are lowercase
    properties = flattened.rules.first.declarations.map(&:property)

    assert properties.all? { |p| p == p.downcase },
           "All properties should be lowercase: #{properties.inspect}"
  end

  # ============================================================================
  # Nested CSS merging tests
  # ============================================================================

  def test_flatten_with_implicit_nesting_flattens
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        color: red;
        .child {
          color: blue;
        }
      }
    CSS

    flattened = sheet.flatten

    # Per W3C spec: parent and child are separate rules with different selectors
    # Nesting should be flattened - all rules are top-level with resolved selectors
    assert_equal 2, flattened.rules_count

    parent_rule = flattened.rules.find { |r| r.selector == '.parent' }
    child_rule = flattened.rules.find { |r| r.selector == '.parent .child' }

    assert parent_rule, 'Should have .parent rule'
    assert child_rule, 'Should have .parent .child rule'

    assert_has_property({ color: 'red' }, parent_rule)
    assert_has_property({ color: 'blue' }, child_rule)
  end

  def test_flatten_with_explicit_nesting_flattens
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .button {
        color: black;
        &:hover {
          color: red;
        }
      }
    CSS

    flattened = sheet.flatten

    # Per W3C spec: .button and .button:hover are different selectors
    # Should have 2 separate rules
    assert_equal 2, flattened.rules_count

    button_rule = flattened.rules.find { |r| r.selector == '.button' }
    hover_rule = flattened.rules.find { |r| r.selector == '.button:hover' }

    assert button_rule, 'Should have .button rule'
    assert hover_rule, 'Should have .button:hover rule'

    assert_has_property({ color: 'black' }, button_rule)
    assert_has_property({ color: 'red' }, hover_rule)
  end

  def test_flatten_multiple_nested_rules_same_resolved_selector
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        .child {
          color: blue;
        }
        .child {
          margin: 10px;
        }
      }
    CSS

    flattened = sheet.flatten

    # Should flatten into single rule with both properties
    assert_equal 1, flattened.rules_count

    flattened_rule = flattened.rules.first

    assert_equal '.parent .child', flattened_rule.selector
    assert_has_property({ color: 'blue' }, flattened_rule)
    assert_has_property({ margin: '10px' }, flattened_rule)
  end

  def test_flatten_nested_with_cascade_rules
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        .child {
          color: blue;
        }
      }
      .parent .child {
        color: red;
      }
    CSS

    flattened = sheet.flatten

    # Later declaration should win (same specificity, later in source)
    assert_equal 1, flattened.rules_count

    flattened_rule = flattened.rules.first

    assert_equal '.parent .child', flattened_rule.selector
    assert_has_property({ color: 'red' }, flattened_rule)
  end

  def test_flatten_deep_nesting_flattens
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .a {
        .b {
          .c {
            color: green;
          }
        }
      }
    CSS

    flattened = sheet.flatten

    # Should fully flatten to .a .b .c
    assert_equal 1, flattened.rules_count

    flattened_rule = flattened.rules.first

    assert_equal '.a .b .c', flattened_rule.selector
    assert_has_property({ color: 'green' }, flattened_rule)
  end

  def test_flatten_mixed_nested_and_flat_rules
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        color: red;
        .child {
          color: blue;
        }
      }
      .other {
        color: green;
      }
    CSS

    flattened = sheet.flatten

    # Per W3C spec: parent and child are separate rules with different selectors
    # Should have 3 rules: .parent, .parent .child, and .other
    assert_equal 3, flattened.rules_count

    parent_rule = flattened.rules.find { |r| r.selector == '.parent' }
    child_rule = flattened.rules.find { |r| r.selector == '.parent .child' }
    other_rule = flattened.rules.find { |r| r.selector == '.other' }

    assert parent_rule, 'Should have .parent rule'
    assert child_rule, 'Should have .parent .child rule'
    assert other_rule, 'Should have .other rule'

    assert_has_property({ color: 'red' }, parent_rule)
    assert_has_property({ color: 'blue' }, child_rule)
    assert_has_property({ color: 'green' }, other_rule)
  end

  def test_flatten_nested_with_important
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        .child {
          color: blue !important;
        }
      }
      .parent .child {
        color: red;
      }
    CSS

    flattened = sheet.flatten

    # !important should win
    assert_equal 1, flattened.rules_count

    flattened_rule = flattened.rules.first

    assert_has_property({ color: 'blue !important' }, flattened_rule)
  end

  def test_flatten_nested_preserves_specificity
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      #parent {
        .child {
          color: blue;
        }
      }
      .parent .child {
        color: red;
      }
    CSS

    flattened = sheet.flatten

    # Different selectors: #parent .child (higher specificity) and .parent .child (lower)
    # Should have 2 separate rules with different selectors
    assert_equal 2, flattened.rules_count

    high_spec_rule = flattened.rules.find { |r| r.selector == '#parent .child' }
    low_spec_rule = flattened.rules.find { |r| r.selector == '.parent .child' }

    assert high_spec_rule, 'Should have #parent .child rule'
    assert low_spec_rule, 'Should have .parent .child rule'

    assert_has_property({ color: 'blue' }, high_spec_rule)
    assert_has_property({ color: 'red' }, low_spec_rule)
  end

  def test_flatten_nested_no_parent_declarations
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        .child {
          color: blue;
        }
      }
    CSS

    flattened = sheet.flatten

    # Should only have the child rule, parent had no declarations
    assert_equal 1, flattened.rules_count

    flattened_rule = flattened.rules.first

    assert_equal '.parent .child', flattened_rule.selector
    assert_has_property({ color: 'blue' }, flattened_rule)
  end

  def test_flatten_nested_with_combinators
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        > .child {
          color: red;
        }
        + .sibling {
          color: blue;
        }
      }
    CSS

    flattened = sheet.flatten

    # Should flatten combinators properly
    # With different selectors, should get separate rules
    assert_operator flattened.rules_count, :>=, 1

    # Check that combinators are preserved in flattened selectors
    selectors = flattened.rules.map(&:selector)

    assert selectors.any? { |s| s.include?('>') || s.include?('+') },
           'Combinators should be preserved in flattened selectors'
  end

  def test_flatten_bang_mutates_receiver
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black; }
      .test { margin: 10px; }
    CSS

    original_object_id = sheet.object_id
    original_rules_count = sheet.rules_count

    # flatten! should return self
    result = sheet.flatten!

    # Should return the same object
    assert_same sheet, result, 'flatten! should return self'
    assert_equal original_object_id, sheet.object_id, 'flatten! should mutate receiver, not create new object'

    # Should have flattened the rules
    assert_equal 1, sheet.rules_count, 'flatten! should have flattened duplicate selectors'
    assert_operator sheet.rules_count, :<, original_rules_count, 'flatten! should reduce rule count'

    # Check flattened content
    assert_has_property({ color: 'black' }, sheet.rules.first)
    assert_has_property({ margin: '10px' }, sheet.rules.first)
  end

  # ============================================================================
  # Selector preservation tests
  # ============================================================================

  def test_flatten_preserves_single_selector
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      body { font-family: Arial; color: #333; }
      body { font-size: 14px; }
      body { line-height: 1.5; color: #000; }
    CSS

    flattened = sheet.flatten

    assert_equal 1, flattened.rules_count, 'Should flatten into single rule'
    assert_equal 'body', flattened.rules.first.selector, 'Should preserve original selector, not use "merged"'
  end

  def test_flatten_preserves_multiple_different_selectors
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .header { color: red; font-size: 20px; }
      .footer { color: blue; font-size: 12px; }
      .sidebar { color: green; }
    CSS

    flattened = sheet.flatten

    assert_equal 3, flattened.rules_count, 'Should have 3 separate rules'

    selectors = flattened.rules.map(&:selector).sort

    assert_equal ['.footer', '.header', '.sidebar'], selectors,
                 'Should preserve all original selectors'

    header_rule = flattened.rules.find { |r| r.selector == '.header' }
    footer_rule = flattened.rules.find { |r| r.selector == '.footer' }
    sidebar_rule = flattened.rules.find { |r| r.selector == '.sidebar' }

    assert_has_property({ color: 'red' }, header_rule)
    assert_has_property({ color: 'blue' }, footer_rule)
    assert_has_property({ color: 'green' }, sidebar_rule)
  end

  def test_flatten_groups_by_selector
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .container { margin-top: 10px; }
      .sidebar { padding: 5px; }
      .container { margin-bottom: 20px; }
      .sidebar { background: blue; }
      .container { color: red; }
    CSS

    flattened = sheet.flatten

    assert_equal 2, flattened.rules_count, 'Should group by selector'

    selectors = flattened.rules.map(&:selector).sort

    assert_equal ['.container', '.sidebar'], selectors

    container_rule = flattened.rules.find { |r| r.selector == '.container' }
    sidebar_rule = flattened.rules.find { |r| r.selector == '.sidebar' }

    # Container should have all its properties flattened
    assert_has_property({ 'margin-top': '10px' }, container_rule)
    assert_has_property({ 'margin-bottom': '20px' }, container_rule)
    assert_has_property({ color: 'red' }, container_rule)

    # Sidebar should have its properties flattened
    assert_has_property({ padding: '5px' }, sidebar_rule)
    assert_has_property({ background: 'blue' }, sidebar_rule)
  end

  def test_flatten_never_uses_merged_placeholder_selector
    # Various CSS inputs - verify we never use the old 'merged' placeholder selector
    test_cases = [
      '.test { color: red; }',
      'body { color: blue; } body { margin: 0; }',
      'div { padding: 10px; } span { margin: 5px; }',
      '#id { color: green; }'
    ]

    test_cases.each do |css|
      sheet = Cataract::Stylesheet.parse(css)
      flattened = sheet.flatten

      selectors = flattened.rules.map(&:selector)

      assert selectors.none?('merged'),
             "Should never use 'merged' placeholder selector. Input: #{css.inspect}, Got selectors: #{selectors.inspect}"
    end
  end

  # Test that AtRules (@keyframes, @font-face, etc.) are passed through unchanged
  def test_atrule_passthrough
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
      .test { color: red; }
      .test { margin: 10px; }
    CSS

    flattened = sheet.flatten

    # Should have 2 rules: the flattened .test rule and the @keyframes AtRule
    assert_equal 2, flattened.rules_count,
                 'Should have 1 flattened rule + 1 passthrough AtRule'

    # Find the AtRule
    at_rule = flattened.rules.find { |r| r.is_a?(Cataract::AtRule) }

    assert at_rule, 'Should have @keyframes AtRule in output'
    assert_equal '@keyframes fade', at_rule.selector

    # Find the regular rule
    regular_rule = flattened.rules.find { |r| r.is_a?(Cataract::Rule) }

    assert regular_rule, 'Should have .test Rule in output'
    assert_equal '.test', regular_rule.selector
    assert_has_property({ color: 'red' }, regular_rule)
    assert_has_property({ margin: '10px' }, regular_rule)
  end

  # Test that a stylesheet with ONLY AtRules (no regular rules) is handled correctly
  def test_atrule_only
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
    CSS

    flattened = sheet.flatten

    # Should have 1 AtRule passthrough
    assert_equal 1, flattened.rules_count,
                 'Should have 1 passthrough AtRule'

    at_rule = flattened.rules.first

    assert_kind_of Cataract::AtRule, at_rule, 'Rule should be an AtRule'
    assert_equal '@keyframes fade', at_rule.selector
  end
end
