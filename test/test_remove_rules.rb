# frozen_string_literal: true

# Tests for Stylesheet#remove_rules! method
# This file tests the NEW positional argument API: remove_rules!(rules_or_css, media_types: nil)
# - First arg can be a String (CSS to parse) or a collection of Rule/AtRule objects
# - media_types kwarg is retained for filtering
class TestRemoveRules < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # ============================================================================
  # New API: remove_rules!(rules_or_css, media_types: nil)
  # ============================================================================

  def test_remove_rules_with_css_string_selector
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
      .footer { color: red; }
    CSS

    assert_equal 3, @sheet.rules_count

    # Pass CSS string with selector to remove
    @sheet.remove_rules!('.header { }')

    assert_equal 2, @sheet.rules_count
    assert_predicate @sheet.with_selector('body'), :any?
    assert_empty @sheet.with_selector('.header')
    assert_predicate @sheet.with_selector('.footer'), :any?
  end

  def test_remove_rules_with_css_string_multiple_selectors
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
      .footer { color: red; }
      .sidebar { width: 200px; }
    CSS

    assert_equal 4, @sheet.rules_count

    # Pass CSS string with multiple selectors
    @sheet.remove_rules!('.header { } .sidebar { }')

    assert_equal 2, @sheet.rules_count
    assert_predicate @sheet.with_selector('body'), :any?
    assert_empty @sheet.with_selector('.header')
    assert_predicate @sheet.with_selector('.footer'), :any?
    assert_empty @sheet.with_selector('.sidebar')
  end

  def test_remove_rules_with_css_string_and_media_filter
    @sheet.add_block(<<~CSS)
      .header { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .header { color: red; } }
    CSS

    assert_equal 3, @sheet.rules_count

    # Remove .header only from screen media
    @sheet.remove_rules!('.header { }', media_types: :screen)

    assert_equal 2, @sheet.rules_count

    # Base .header should still exist
    base_header = @sheet.rules.find { |r| r.selector == '.header' && !in_media_query?(r) }

    assert base_header

    # Screen .header should be gone
    assert_empty @sheet.with_media(:screen).with_selector('.header')

    # Print .header should still exist
    assert_predicate @sheet.with_media(:print).with_selector('.header'), :any?
  end

  def test_remove_rules_with_rule_collection
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
      .footer { color: red; }
      .sidebar { width: 200px; }
    CSS

    assert_equal 4, @sheet.rules_count

    # Find rules to remove
    rules_to_remove = @sheet.select { |r| ['.header', '.sidebar'].include?(r.selector) }

    assert_equal 2, rules_to_remove.length

    # Pass array of rules
    @sheet.remove_rules!(rules_to_remove)

    assert_equal 2, @sheet.rules_count
    assert_predicate @sheet.with_selector('body'), :any?
    assert_empty @sheet.with_selector('.header')
    assert_predicate @sheet.with_selector('.footer'), :any?
    assert_empty @sheet.with_selector('.sidebar')
  end

  def test_remove_rules_with_rule_collection_and_media_filter
    @sheet.add_block(<<~CSS)
      .header { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .header { color: red; } }
    CSS

    assert_equal 3, @sheet.rules_count

    # Get all .header rules
    all_headers = @sheet.select { |r| r.selector == '.header' }

    assert_equal 3, all_headers.length

    # Remove only from screen media
    @sheet.remove_rules!(all_headers, media_types: :screen)

    assert_equal 2, @sheet.rules_count

    # Base and print should remain
    assert_predicate @sheet.with_selector('.header'), :any?
    assert_empty @sheet.with_media(:screen).with_selector('.header')
    assert_predicate @sheet.with_media(:print).with_selector('.header'), :any?
  end

  def test_remove_rules_with_single_rule_object
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
      .footer { color: red; }
    CSS

    assert_equal 3, @sheet.rules_count

    # Find single rule
    header_rule = @sheet.find { |r| r.selector == '.header' }

    # Pass single rule (not in array)
    @sheet.remove_rules!(header_rule)

    assert_equal 2, @sheet.rules_count
    assert_predicate @sheet.with_selector('body'), :any?
    assert_empty @sheet.with_selector('.header')
    assert_predicate @sheet.with_selector('.footer'), :any?
  end

  def test_remove_rules_with_multiple_media_types_filter
    @sheet.add_block(<<~CSS)
      .header { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .header { color: red; } }
      @media handheld { .header { color: green; } }
    CSS

    assert_equal 4, @sheet.rules_count

    # Remove .header from screen and print only
    @sheet.remove_rules!('.header { }', media_types: %i[screen print])

    assert_equal 2, @sheet.rules_count

    # Base and handheld should remain
    base_header = @sheet.rules.find { |r| r.selector == '.header' && !in_media_query?(r) }

    assert base_header
    assert_predicate @sheet.with_media(:handheld).with_selector('.header'), :any?

    # Screen and print should be gone
    assert_empty @sheet.with_media(:screen).with_selector('.header')
    assert_empty @sheet.with_media(:print).with_selector('.header')
  end

  def test_remove_rules_cleans_up_empty_media_queries
    @sheet.add_block('@media screen { .header { color: blue; } }')

    assert_equal 1, @sheet.rules_count
    assert @sheet.media_queries.any? { |mq| mq.type == :screen }, 'Should have screen media query'

    # Remove the only rule in the screen group
    @sheet.remove_rules!('.header { }', media_types: :screen)

    assert_equal 0, @sheet.rules_count
    assert_empty @sheet.media_queries
  end

  def test_remove_rules_with_at_rules
    @sheet.add_block(<<~CSS)
      body { color: black; }
      @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
      .header { color: blue; }
    CSS

    assert_equal 3, @sheet.rules_count

    # Find the keyframes at-rule
    keyframes_rule = @sheet.find { |r| r.is_a?(Cataract::AtRule) && r.at_rule_type?(:keyframes) }

    assert keyframes_rule

    # Remove the at-rule
    @sheet.remove_rules!(keyframes_rule)

    assert_equal 2, @sheet.rules_count
    assert_predicate @sheet.with_selector('body'), :any?
    refute(@sheet.any? { |r| r.is_a?(Cataract::AtRule) && r.at_rule_type?(:keyframes) })
    assert_predicate @sheet.with_selector('.header'), :any?
  end

  def test_remove_rules_updates_rule_ids_correctly
    @sheet.add_block(<<~CSS)
      .rule-1 { color: red; }
      .rule-2 { color: blue; }
      .rule-3 { color: green; }
      .rule-4 { color: yellow; }
    CSS

    # Find .rule-2
    rule_to_remove = @sheet.find { |r| r.selector == '.rule-2' }

    # Remove .rule-2
    @sheet.remove_rules!(rule_to_remove)

    # Check IDs are sequential
    assert_equal 0, @sheet.rules[0].id
    assert_equal 1, @sheet.rules[1].id
    assert_equal 2, @sheet.rules[2].id

    # Check selectors are correct
    assert_equal '.rule-1', @sheet.rules[0].selector
    assert_equal '.rule-3', @sheet.rules[1].selector
    assert_equal '.rule-4', @sheet.rules[2].selector
  end

  def test_remove_rules_updates_media_index_correctly
    @sheet.add_block(<<~CSS)
      @media screen {
        .rule-1 { color: red; }
        .rule-2 { color: blue; }
        .rule-3 { color: green; }
      }
    CSS

    # Before removal: IDs should be [0, 1, 2]
    assert_equal [0, 1, 2], @sheet.media_index[:screen]

    # Remove .rule-2 (ID 1)
    @sheet.remove_rules!('.rule-2 { }', media_types: :screen)

    # After removal: IDs should be [0, 1] (decremented)
    assert_equal [0, 1], @sheet.media_index[:screen]

    # Check rules are correct
    assert_equal '.rule-1', @sheet.rules[0].selector
    assert_equal '.rule-3', @sheet.rules[1].selector
  end

  def test_remove_rules_with_all_media_type_removes_base_rules
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
      @media screen { .sidebar { width: 200px; } }
    CSS

    assert_equal 3, @sheet.rules_count

    # Remove body from :all media (should remove base rule)
    @sheet.remove_rules!('body { }', media_types: :all)

    assert_equal 2, @sheet.rules_count
    assert_empty @sheet.with_selector('body')
    assert_predicate @sheet.with_selector('.header'), :any?
    assert_predicate @sheet.with_media(:screen).with_selector('.sidebar'), :any?
  end

  def test_remove_rules_clears_memoized_selectors
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
      .footer { color: red; }
    CSS

    # Access selectors to memoize
    original_selectors = @sheet.selectors

    assert_equal 3, original_selectors.length

    # Remove a rule
    @sheet.remove_rules!('.header { }')

    # Selectors should be refreshed
    new_selectors = @sheet.selectors

    assert_equal 2, new_selectors.length
    refute_includes new_selectors, '.header'
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  def test_remove_rules_with_nonexistent_selector
    @sheet.add_block('body { color: black; }')

    assert_equal 1, @sheet.rules_count

    @sheet.remove_rules!('.nonexistent { }')

    # Should not remove anything
    assert_equal 1, @sheet.rules_count
  end

  def test_remove_rules_with_nonexistent_media_type
    @sheet.add_block('@media screen { .header { color: blue; } }')

    assert_equal 1, @sheet.rules_count

    @sheet.remove_rules!('.header { }', media_types: :print)

    # Should not remove anything
    assert_equal 1, @sheet.rules_count
  end

  def test_remove_rules_with_complex_media_query
    @sheet.add_block(<<~CSS)
      @media screen and (min-width: 768px) {
        .container { width: 750px; }
      }
    CSS

    assert_equal 1, @sheet.rules_count

    # Should match media type :screen from complex query
    @sheet.remove_rules!('.container { }', media_types: :screen)

    assert_equal 0, @sheet.rules_count
  end

  def test_remove_rules_with_multi_media_query
    @sheet.add_block(<<~CSS)
      @media screen, print {
        .universal { color: blue; }
      }
    CSS

    assert_equal 1, @sheet.rules_count

    # Removing from screen should remove the rule (it matches screen)
    @sheet.remove_rules!('.universal { }', media_types: :screen)

    assert_equal 0, @sheet.rules_count
  end

  def test_remove_rules_with_empty_array
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
    CSS

    assert_equal 2, @sheet.rules_count

    # Pass empty array - should remove nothing
    @sheet.remove_rules!([])

    assert_equal 2, @sheet.rules_count
  end

  def test_remove_rules_with_css_string_no_matching_selectors
    @sheet.add_block(<<~CSS)
      body { color: black; }
      .header { color: blue; }
    CSS

    assert_equal 2, @sheet.rules_count

    # Parse CSS that doesn't match any existing rules
    @sheet.remove_rules!('.footer { } .sidebar { }')

    # Should not remove anything
    assert_equal 2, @sheet.rules_count
  end

  private

  def in_media_query?(rule)
    media_index = @sheet.media_index
    media_index.values.flatten.include?(rule.id)
  end
end
