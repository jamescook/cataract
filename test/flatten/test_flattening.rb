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

  # ============================================================================
  # Selector list divergence tests
  # ============================================================================

  def test_selector_list_divergence_basic
    # h1, h2, h3 start with same color, then h3 gets overridden
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      h1, h2, h3 { color: red; }
      h3 { color: blue; }
    CSS

    flattened = sheet.flatten

    # Should have 3 rules after flattening
    assert_equal 3, flattened.rules_count

    h1_rule = flattened.rules.find { |r| r.selector == 'h1' }
    h2_rule = flattened.rules.find { |r| r.selector == 'h2' }
    h3_rule = flattened.rules.find { |r| r.selector == 'h3' }

    assert h1_rule, 'Should have h1 rule'
    assert h2_rule, 'Should have h2 rule'
    assert h3_rule, 'Should have h3 rule'

    # h1 and h2 should still have selector_list_id (same declarations)
    assert_equal h1_rule.selector_list_id, h2_rule.selector_list_id,
                 'h1 and h2 should share same selector_list_id'
    refute_nil h1_rule.selector_list_id, 'h1 should have selector_list_id'

    # h3 should have selector_list_id removed (diverged)
    assert_nil h3_rule.selector_list_id,
               'h3 should have selector_list_id removed after divergence'

    # Verify declarations
    assert_has_property({ color: 'red' }, h1_rule)
    assert_has_property({ color: 'red' }, h2_rule)
    assert_has_property({ color: 'blue' }, h3_rule)

    # Verify serialization groups h1,h2 but keeps h3 separate
    expected = <<~CSS
      h1, h2 { color: red; }
      h3 { color: blue; }
    CSS

    assert_equal expected, flattened.to_s
  end

  def test_selector_list_divergence_important
    # Selector list diverges due to !important
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .a, .b, .c { color: red; }
      .b { color: blue !important; }
    CSS

    flattened = sheet.flatten

    a_rule = flattened.rules.find { |r| r.selector == '.a' }
    b_rule = flattened.rules.find { |r| r.selector == '.b' }
    c_rule = flattened.rules.find { |r| r.selector == '.c' }

    # .a and .c should still share selector_list_id
    assert_equal a_rule.selector_list_id, c_rule.selector_list_id,
                 '.a and .c should still be grouped'
    refute_nil a_rule.selector_list_id

    # .b should be removed from selector list (diverged)
    assert_nil b_rule.selector_list_id,
               '.b should have selector_list_id removed after !important override'

    assert_has_property({ color: 'red' }, a_rule)
    assert_has_property({ color: 'blue !important' }, b_rule)
    assert_has_property({ color: 'red' }, c_rule)

    expected = <<~CSS
      .a, .c { color: red; }
      .b { color: blue !important; }
    CSS

    assert_equal expected, flattened.to_s
  end

  def test_selector_list_complete_divergence
    # All selectors in list diverge completely
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .x, .y, .z { color: red; }
      .x { color: blue; }
      .y { color: green; }
      .z { color: yellow; }
    CSS

    flattened = sheet.flatten

    x_rule = flattened.rules.find { |r| r.selector == '.x' }
    y_rule = flattened.rules.find { |r| r.selector == '.y' }
    z_rule = flattened.rules.find { |r| r.selector == '.z' }

    # All should have selector_list_id removed (complete divergence)
    assert_nil x_rule.selector_list_id, '.x should have no selector_list_id'
    assert_nil y_rule.selector_list_id, '.y should have no selector_list_id'
    assert_nil z_rule.selector_list_id, '.z should have no selector_list_id'

    assert_has_property({ color: 'blue' }, x_rule)
    assert_has_property({ color: 'green' }, y_rule)
    assert_has_property({ color: 'yellow' }, z_rule)

    expected = <<~CSS
      .x { color: blue; }
      .y { color: green; }
      .z { color: yellow; }
    CSS

    assert_equal expected, flattened.to_s
  end

  def test_selector_list_partial_divergence_multiple_properties
    # Selector list with multiple properties, only one property diverges
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .a, .b { color: red; margin: 10px; }
      .b { color: blue; }
    CSS

    flattened = sheet.flatten

    a_rule = flattened.rules.find { |r| r.selector == '.a' }
    b_rule = flattened.rules.find { |r| r.selector == '.b' }

    # .b should be removed from selector list (declarations diverged)
    assert_nil b_rule.selector_list_id,
               '.b should be removed from selector list when any declaration diverges'

    assert_has_property({ color: 'red' }, a_rule)
    assert_has_property({ margin: '10px' }, a_rule)

    assert_has_property({ color: 'blue' }, b_rule)
    assert_has_property({ margin: '10px' }, b_rule)

    expected = <<~CSS
      .a { color: red; margin: 10px; }
      .b { color: blue; margin: 10px; }
    CSS

    assert_equal expected, flattened.to_s
  end

  def test_selector_list_no_divergence_stays_grouped
    # Selector list with no cascade changes should stay grouped
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      h1, h2, h3 { color: red; font-size: 2em; }
      p { color: blue; }
    CSS

    flattened = sheet.flatten

    h1_rule = flattened.rules.find { |r| r.selector == 'h1' }
    h2_rule = flattened.rules.find { |r| r.selector == 'h2' }
    h3_rule = flattened.rules.find { |r| r.selector == 'h3' }

    # All should still share selector_list_id (no divergence)
    assert_equal h1_rule.selector_list_id, h2_rule.selector_list_id,
                 'h1 and h2 should share selector_list_id'
    assert_equal h2_rule.selector_list_id, h3_rule.selector_list_id,
                 'h2 and h3 should share selector_list_id'
    refute_nil h1_rule.selector_list_id, 'h1 should have selector_list_id'

    expected = <<~CSS
      h1, h2, h3 { color: red; font-size: 2em; }
      p { color: blue; }
    CSS

    assert_equal expected, flattened.to_s
  end

  def test_flatten_ignores_selector_lists_when_feature_disabled
    # When selector_lists is not enabled during parsing, flatten should not process selector lists
    sheet = Cataract::Stylesheet.parse(<<~CSS, parser: { selector_lists: false })
      h1, h2, h3 { color: red; }
      h3 { color: blue; }
    CSS

    flattened = sheet.flatten

    h1_rule = flattened.rules.find { |r| r.selector == 'h1' }
    h2_rule = flattened.rules.find { |r| r.selector == 'h2' }
    h3_rule = flattened.rules.find { |r| r.selector == 'h3' }

    # All selector_list_ids should be nil since feature was disabled
    assert_nil h1_rule.selector_list_id, 'h1 should not have selector_list_id when feature disabled'
    assert_nil h2_rule.selector_list_id, 'h2 should not have selector_list_id when feature disabled'
    assert_nil h3_rule.selector_list_id, 'h3 should not have selector_list_id when feature disabled'

    # Serialization should output rules separately (no grouping)
    expected = <<~CSS
      h1 { color: red; }
      h2 { color: red; }
      h3 { color: blue; }
    CSS

    assert_equal expected, flattened.to_s
  end

  def test_flatten_does_not_wrap_output_in_media_all
    # Flatten should set @media_index to empty hash, not wrap output in @media all
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      h1 { color: red; }
      .test { margin: 10px; }
    CSS

    flattened = sheet.flatten
    output = flattened.to_s

    # Should NOT contain @media wrapper
    refute_match(/@media/, output, 'Flatten should not wrap output in @media all')

    # Should contain the actual rules with correct properties
    assert_has_selector('h1', flattened)
    assert_has_property({ color: 'red' }, flattened.with_selector('h1').first)
    assert_has_selector('.test', flattened)
    assert_has_property({ margin: '10px' }, flattened.with_selector('.test').first)

    # Verify @_media_index is empty hash
    media_index = flattened.media_index

    assert_empty(media_index, '@_media_index should be empty hash after flatten')
  end

  def test_import_with_media_constraint_preserves_media_after_flatten
    # Create a temporary CSS file to import
    import_file = File.join(Dir.tmpdir, 'test_import_print.css')
    File.write(import_file, 'body { background: red; }')

    begin
      css = "@import \"#{import_file}\" print;\nbody { color: blue; }"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      # Before flatten, check media index
      media_index_before = sheet.media_index
      print_rules_before = media_index_before[:print] || []

      refute_empty(print_rules_before, 'Should have print media rules before flatten')

      # After flatten
      flattened = sheet.flatten
      media_index_after = flattened.media_index
      print_rules_after = media_index_after[:print] || []

      # Media constraint should be preserved after flatten
      refute_empty(print_rules_after, 'Should preserve print media rules after flatten')

      # The body rule with background:red should be in print media only
      body_rules = flattened.rules.select { |r| r.selector == 'body' }
      red_rule = body_rules.find { |r| r.declarations.any? { |d| d.property == 'background' && d.value == 'red' } }
      blue_rule = body_rules.find { |r| r.declarations.any? { |d| d.property == 'color' && d.value == 'blue' } }

      assert(red_rule, 'Should have body rule with background:red')
      assert(blue_rule, 'Should have body rule with color:blue')

      # red_rule should be in print media
      assert_rule_in_media(red_rule, :print, flattened)
      # blue_rule should NOT be in print media (it's a base rule)
      refute_member(print_rules_after, blue_rule.id, 'Color:blue rule should not be in print media')
    ensure
      FileUtils.rm_f(import_file)
    end
  end

  def test_flatten_preserves_media_queries
    css = <<~CSS
      body { color: blue; }
      @media print {
        body { color: red; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Before flatten - should have media index
    assert_matches_media(:print, sheet)

    # After flatten
    flattened = sheet.flatten

    # Media queries should be preserved after flatten
    assert_matches_media(:print, flattened)

    # Verify the print rule exists and has correct property
    assert_has_selector('body', flattened, media: :print)
    print_rule = flattened.with_media(:print).with_selector('body').first

    assert_has_property({ color: 'red' }, print_rule)
  end

  def test_flatten_preserves_multiple_media_queries
    css = <<~CSS
      @media screen {
        div { margin: 10px; }
      }
      @media print {
        div { margin: 0; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    flattened = sheet.flatten

    # Both media queries should be preserved
    assert_matches_media(:screen, flattened)
    assert_matches_media(:print, flattened)

    # Verify rules exist in correct media contexts
    assert_has_selector('div', flattened, media: :screen)
    assert_has_selector('div', flattened, media: :print)
  end

  def test_flatten_merges_rules_within_same_media_query
    css = <<~CSS
      @media print {
        body { color: red; }
        body { background: white; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    flattened = sheet.flatten

    # Should have one merged rule for body in print media
    assert_has_selector('body', flattened, media: :print, count: 1)

    # Both declarations should be present
    merged_rule = flattened.with_media(:print).with_selector('body').first

    assert_has_property({ color: 'red' }, merged_rule)
    assert_has_property({ background: 'white' }, merged_rule)

    # Media constraint should still be present
    assert_rule_in_media(merged_rule, :print, flattened)
  end

  def test_import_with_multiple_media_and_same_selector_keeps_rules_separate
    # Create import files matching the problematic scenario
    import_file = File.join(Dir.tmpdir, 'import.css')
    File.write(import_file, '.hide { display: none; }')

    noimport_file = File.join(Dir.tmpdir, 'noimport.css')
    File.write(noimport_file, 'body { background: red !important; }')

    begin
      # CSS with imports BEFORE rules (per CSS spec)
      css = <<~CSS
        @import "#{import_file}" screen, handheld;
        @import "#{noimport_file}" print;
        body {
          color: #fff;
          background-color: #9EBF00;
        }
      CSS

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'], extensions: ['css'] })
      flattened = sheet.flatten

      # MOST IMPORTANT: Verify flattened result is semantically correct per W3C spec
      # There should be TWO separate body rules:
      # 1. One for print media with background:red !important (from noimport.css)
      # 2. One for base/all media with color:#fff and background-color:#9EBF00

      body_rules = flattened.rules.select { |r| r.selector == 'body' }

      assert_equal(2, body_rules.length, 'Should have 2 separate body rules: one for print, one for base')

      # Find the print media body rule
      media_index = flattened.media_index
      print_rule_ids = media_index[:print] || []

      refute_empty(print_rule_ids, 'Should have print media rules')

      print_body_rule = body_rules.find { |r| print_rule_ids.include?(r.id) }

      assert(print_body_rule, 'Should have body rule in print media')
      assert_has_property({ background: 'red !important' }, print_body_rule)

      # Find the base body rule (NOT in print media)
      base_body_rule = body_rules.find { |r| !print_rule_ids.include?(r.id) }

      assert(base_body_rule, 'Should have body rule NOT in print media')
      assert_has_property({ color: '#fff' }, base_body_rule)
      assert_has_property({ 'background-color': '#9EBF00' }, base_body_rule)

      # THEN verify media index is correct
      # The print rule should ONLY be in print media
      assert_rule_in_media(print_body_rule, :print, flattened)

      # The base rule should NOT be in print media
      refute_member(print_rule_ids, base_body_rule.id, 'Base body rule should NOT be in print media')

      # Verify screen,handheld media for .hide rule
      # The rule should be indexed under both :screen and :handheld
      hide_rule = flattened.rules.find { |r| r.selector == '.hide' }

      assert(hide_rule, 'Should have .hide rule')
      assert_rule_in_media(hide_rule, :screen, flattened)
      assert_rule_in_media(hide_rule, :handheld, flattened)
    ensure
      FileUtils.rm_f(import_file)
      FileUtils.rm_f(noimport_file)
    end
  end
end
