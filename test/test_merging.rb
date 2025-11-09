#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_helper'

class TestMerging < Minitest::Test
  # Test simple merge of two rules with different properties
  def test_simple_merge
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test1 { color: black; }
      .test1 { margin: 0px; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'black' }, merged.rules.first)
    assert_has_property({ margin: '0px' }, merged.rules.first)
  end

  # Test that later rule with same specificity overwrites earlier
  def test_merging_same_property
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black; }
      .test { color: red; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red' }, merged.rules.first)
  end

  # Test that higher specificity wins
  def test_specificity_wins
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black; }
      #test { color: red; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red' }, merged.rules.first, 'ID selector (#test) should win over class (.test)')
  end

  # Test that lower specificity doesn't override higher
  def test_lower_specificity_loses
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      #test { color: red; }
      .test { color: black; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red' }, merged.rules.first, 'ID selector should not be overridden by class')
  end

  # Test !important wins over non-important regardless of specificity
  def test_important_wins
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black !important; }
      #test { color: red; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'black !important' }, merged.rules.first, '!important should win over higher specificity')
  end

  # Test !important doesn't override higher specificity !important
  def test_important_with_specificity
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      #test { color: red !important; }
      .test { color: black !important; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red !important' }, merged.rules.first, 'Higher specificity !important should win')
  end

  # Test merging with multiple selectors (uses max specificity)
  def test_multiple_selectors_max_specificity
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      p, a[rel="external"] { color: black; }
      a { color: blue; }
    CSS

    merged = sheet.merge

    # p=1, a[rel="external"]=11, so max=11 should beat a=1
    # The merged sheet should have one rule with black color
    assert_has_property({ color: 'black' }, merged.rules.first)
  end

  # Test property names are case-insensitive
  def test_case_insensitive_properties
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { CoLor: red; }
      .test { color: blue; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'blue' }, merged.rules.first)
  end

  # Test merging backgrounds (requires shorthand expansion)
  def test_merging_backgrounds
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { background-color: black; }
      .test { background-image: none; }
    CSS

    merged = sheet.merge

    # background shorthand should be created from multiple properties
    assert_has_property({ background: 'black none' }, merged.rules.first)
  end

  # Test merging dimensions (margin expansion then merge)
  def test_merging_dimensions
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { margin: 3em; }
      .test { margin-left: 1em; }
    CSS

    merged = sheet.merge

    assert_has_property({ margin: '3em 3em 3em 1em' }, merged.rules.first)
  end

  # Test merging fonts
  def test_merging_fonts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { font: 11px Arial; }
      .test { font-weight: bold; }
    CSS

    merged = sheet.merge

    assert_has_property({ font: 'bold 11px Arial' }, merged.rules.first)
  end

  # Test multiple !important with same specificity (last wins)
  def test_multiple_important_same_specificity
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black !important; }
      .test { color: red !important; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red !important' }, merged.rules.first)
  end

  # Test !important in same block (last wins)
  def test_important_in_same_block
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: black !important; color: red !important; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red !important' }, merged.rules.first)
  end

  # Test !important beats non-important in same block
  def test_important_beats_non_important_same_block
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: red; color: black !important; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'black !important' }, merged.rules.first)
  end

  # Test merging shorthand !important
  def test_shorthand_important
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { background: black none !important; }
      .test { background-color: red; }
    CSS

    merged = sheet.merge

    # After expansion and re-creation, background shorthand should be marked !important
    # Normal background-color cannot override !important
    assert_has_property({ background: 'black none !important' }, merged.rules.first)
    # The !important background wins, normal background-color is ignored
    refute(merged.rules.first.declarations.any? { |d| d.property == 'background-color' })
  end

  # Test empty merge (single rule)
  def test_single_rule_merge
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { color: red; margin: 10px; }
    CSS

    merged = sheet.merge

    assert_has_property({ color: 'red' }, merged.rules.first)
    assert_has_property({ margin: '10px' }, merged.rules.first)
  end

  # Test merging with no rules
  def test_empty_merge
    sheet = Cataract::Stylesheet.new
    merged = sheet.merge

    assert_empty merged.rules
  end

  # Test that uppercase property names are handled correctly
  # Properties should already be lowercase from parser, but test edge cases
  def test_uppercase_properties_are_lowercased
    # Parse CSS with uppercase properties (parser should lowercase them)
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { COLOR: red; MARGIN-TOP: 10px; }
      .test { color: blue; margin-top: 20px; }
    CSS

    merged = sheet.merge

    # Should merge correctly (case-insensitive property matching)
    assert_has_property({ color: 'blue' }, merged.rules.first)
    assert_has_property({ 'margin-top': '20px' }, merged.rules.first)

    # Verify properties in merged result are lowercase
    merged.rules.first.declarations.each do |decl|
      assert_equal decl.property, decl.property.downcase,
                   "Property '#{decl.property}' should be lowercase in merged result"
    end
  end

  # Test that shorthand expansion produces lowercase properties
  def test_shorthand_expansion_lowercase
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .test { margin: 10px 20px; }
    CSS

    merged = sheet.merge

    # Shorthand should be expanded to lowercase longhand properties
    merged.rules.first.declarations.each do |decl|
      assert_equal decl.property, decl.property.downcase,
                   "Expanded property '#{decl.property}' should be lowercase"
    end

    # Should have margin shorthand (or expanded longhands, both lowercase)
    # Just verify all properties are lowercase
    properties = merged.rules.first.declarations.map(&:property)

    assert properties.all? { |p| p == p.downcase },
           "All properties should be lowercase: #{properties.inspect}"
  end

  # ============================================================================
  # Nested CSS merging tests
  # ============================================================================

  def test_merge_with_implicit_nesting_flattens
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        color: red;
        .child {
          color: blue;
        }
      }
    CSS

    merged = sheet.merge

    # Per W3C spec: parent and child are separate rules with different selectors
    # Nesting should be flattened - all rules are top-level with resolved selectors
    assert_equal 2, merged.rules_count

    parent_rule = merged.rules.find { |r| r.selector == '.parent' }
    child_rule = merged.rules.find { |r| r.selector == '.parent .child' }

    assert parent_rule, 'Should have .parent rule'
    assert child_rule, 'Should have .parent .child rule'

    assert_has_property({ color: 'red' }, parent_rule)
    assert_has_property({ color: 'blue' }, child_rule)
  end

  def test_merge_with_explicit_nesting_flattens
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .button {
        color: black;
        &:hover {
          color: red;
        }
      }
    CSS

    merged = sheet.merge

    # Per W3C spec: .button and .button:hover are different selectors
    # Should have 2 separate rules
    assert_equal 2, merged.rules_count

    button_rule = merged.rules.find { |r| r.selector == '.button' }
    hover_rule = merged.rules.find { |r| r.selector == '.button:hover' }

    assert button_rule, 'Should have .button rule'
    assert hover_rule, 'Should have .button:hover rule'

    assert_has_property({ color: 'black' }, button_rule)
    assert_has_property({ color: 'red' }, hover_rule)
  end

  def test_merge_multiple_nested_rules_same_resolved_selector
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

    merged = sheet.merge

    # Should merge into single rule with both properties
    assert_equal 1, merged.rules_count

    merged_rule = merged.rules.first

    assert_equal '.parent .child', merged_rule.selector
    assert_has_property({ color: 'blue' }, merged_rule)
    assert_has_property({ margin: '10px' }, merged_rule)
  end

  def test_merge_nested_with_cascade_rules
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

    merged = sheet.merge

    # Later declaration should win (same specificity, later in source)
    assert_equal 1, merged.rules_count

    merged_rule = merged.rules.first

    assert_equal '.parent .child', merged_rule.selector
    assert_has_property({ color: 'red' }, merged_rule)
  end

  def test_merge_deep_nesting_flattens
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .a {
        .b {
          .c {
            color: green;
          }
        }
      }
    CSS

    merged = sheet.merge

    # Should fully flatten to .a .b .c
    assert_equal 1, merged.rules_count

    merged_rule = merged.rules.first

    assert_equal '.a .b .c', merged_rule.selector
    assert_has_property({ color: 'green' }, merged_rule)
  end

  def test_merge_mixed_nested_and_flat_rules
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

    merged = sheet.merge

    # Per W3C spec: parent and child are separate rules with different selectors
    # Should have 3 rules: .parent, .parent .child, and .other
    assert_equal 3, merged.rules_count

    parent_rule = merged.rules.find { |r| r.selector == '.parent' }
    child_rule = merged.rules.find { |r| r.selector == '.parent .child' }
    other_rule = merged.rules.find { |r| r.selector == '.other' }

    assert parent_rule, 'Should have .parent rule'
    assert child_rule, 'Should have .parent .child rule'
    assert other_rule, 'Should have .other rule'

    assert_has_property({ color: 'red' }, parent_rule)
    assert_has_property({ color: 'blue' }, child_rule)
    assert_has_property({ color: 'green' }, other_rule)
  end

  def test_merge_nested_with_important
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

    merged = sheet.merge

    # !important should win
    assert_equal 1, merged.rules_count

    merged_rule = merged.rules.first

    assert_has_property({ color: 'blue !important' }, merged_rule)
  end

  def test_merge_nested_preserves_specificity
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

    merged = sheet.merge

    # Different selectors: #parent .child (higher specificity) and .parent .child (lower)
    # Should have 2 separate rules with different selectors
    assert_equal 2, merged.rules_count

    high_spec_rule = merged.rules.find { |r| r.selector == '#parent .child' }
    low_spec_rule = merged.rules.find { |r| r.selector == '.parent .child' }

    assert high_spec_rule, 'Should have #parent .child rule'
    assert low_spec_rule, 'Should have .parent .child rule'

    assert_has_property({ color: 'blue' }, high_spec_rule)
    assert_has_property({ color: 'red' }, low_spec_rule)
  end

  def test_merge_nested_no_parent_declarations
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .parent {
        .child {
          color: blue;
        }
      }
    CSS

    merged = sheet.merge

    # Should only have the child rule, parent had no declarations
    assert_equal 1, merged.rules_count

    merged_rule = merged.rules.first

    assert_equal '.parent .child', merged_rule.selector
    assert_has_property({ color: 'blue' }, merged_rule)
  end

  def test_merge_nested_with_combinators
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

    merged = sheet.merge

    # Should flatten combinators properly
    # With different selectors, should get separate rules
    assert_operator merged.rules_count, :>=, 1

    # Check that combinators are preserved in flattened selectors
    selectors = merged.rules.map(&:selector)

    assert selectors.any? { |s| s.include?('>') || s.include?('+') },
           'Combinators should be preserved in flattened selectors'
  end
end
