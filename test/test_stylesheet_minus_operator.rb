require_relative 'test_helper'

class TestStylesheetMinusOperator < Minitest::Test
  # ============================================================================
  # Stylesheet subtraction tests (-)
  # ============================================================================

  def test_minus_operator_removes_matching_rules
    sheet1 = Cataract.parse_css('.box { color: red; } .other { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, '- should remove matching rules'
    assert_equal '.other', result.rules[0].selector
  end

  def test_minus_operator_returns_new_stylesheet
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    result = sheet1 - sheet2

    refute_same sheet1, result, '- should return new stylesheet'
    assert_equal 1, sheet1.rules.size, 'Original should be unchanged'
  end

  def test_minus_operator_uses_shorthand_aware_matching
    # Should remove rule using Rule#== (shorthand-aware)
    sheet1 = Cataract.parse_css('.box { margin: 10px; } .other { color: red; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, 'Shorthand should match longhand'
    assert_equal '.other', result.rules[0].selector
  end

  def test_minus_operator_does_not_apply_cascade
    # - should NOT apply cascade, just remove rules
    sheet1 = Cataract.parse_css('.box { color: red; } .box { color: blue; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1 - sheet2

    assert_equal 2, result.rules.size, '- should not apply cascade'
    assert_equal '.box', result.rules[0].selector
    assert_equal '.box', result.rules[1].selector
  end

  def test_minus_operator_no_matching_rules
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, 'Should keep all rules when no matches'
    assert_equal '.box', result.rules[0].selector
  end

  def test_minus_operator_removes_all_rules
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    result = sheet1 - sheet2

    assert_equal 0, result.rules.size, 'Should remove all matching rules'
  end

  def test_minus_operator_preserves_media_queries
    # Keep rules with media queries that don't match
    sheet1 = Cataract.parse_css('@media print { .box { color: red; } } @media screen { .other { margin: 10px; } }')
    sheet2 = Cataract.parse_css('@media print { .box { color: red; } }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, 'Should remove matching media rule'
    assert_equal '.other', result.rules[0].selector
    assert result.media_queries.any? { |mq| mq.type == :screen }, 'Should have screen media query'
    refute result.media_queries.any? { |mq| mq.type == :print }, 'Should not have print media query'
  end

  def test_minus_operator_updates_media_index_correctly
    # Test that media index IDs are updated when rules are removed
    sheet1 = Cataract.parse_css('.base { color: red; } @media print { .print1 { margin: 10px; } } .middle { padding: 5px; } @media screen { .screen1 { font-size: 16px; } }')
    sheet2 = Cataract.parse_css('.base { color: red; }')

    result = sheet1 - sheet2

    # .base removed (was ID 0), so remaining rules shift down
    assert_equal 3, result.rules.size
    assert_equal '.print1', result.rules[0].selector  # Now ID 0 (was 1)
    assert_equal '.middle', result.rules[1].selector  # Now ID 1 (was 2)
    assert_equal '.screen1', result.rules[2].selector # Now ID 2 (was 3)

    # Media index should have updated IDs
    print_rules = result.with_media(:print).to_a

    assert_equal 1, print_rules.size
    assert_equal 0, print_rules[0].id, 'Media index should reference updated ID'

    screen_rules = result.with_media(:screen).to_a

    assert_equal 1, screen_rules.size
    assert_equal 2, screen_rules[0].id, 'Media index should reference updated ID'
  end

  def test_minus_operator_removes_middle_rule_with_media
    # Remove a rule in the middle and verify IDs update correctly
    sheet1 = Cataract.parse_css('@media print { .first { color: red; } } @media screen { .second { margin: 10px; } } @media print { .third { padding: 5px; } }')
    sheet2 = Cataract.parse_css('@media screen { .second { margin: 10px; } }')

    result = sheet1 - sheet2

    assert_equal 2, result.rules.size
    assert_equal '.first', result.rules[0].selector
    assert_equal '.third', result.rules[1].selector

    # Check media index
    print_rules = result.with_media(:print).to_a

    assert_equal 2, print_rules.size
    assert_equal 0, print_rules[0].id
    assert_equal 1, print_rules[1].id

    # Screen media should be gone
    refute_includes result.media_queries, :screen
  end
end
