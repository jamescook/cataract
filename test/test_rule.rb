require_relative 'test_helper'

class TestRule < Minitest::Test
  def test_equality_same_selector_and_declarations
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls2, 10, nil, nil)

    assert_equal rule1, rule2
  end

  def test_equality_different_id_same_content
    # Two rules with different IDs but same selector/declarations are logically equal
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(99, '.foo', decls, 10, nil, nil)

    assert_equal rule1, rule2, 'ID is an implementation detail, not part of logical equality'
  end

  def test_equality_different_specificity_same_selector
    # If selector is the same, specificity MUST be the same (it's derived)
    # But equality check should ignore specificity anyway
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls, 999, nil, nil) # wrong specificity!

    assert_equal rule1, rule2, 'Specificity is derived from selector, not part of equality check'
  end

  def test_equality_different_selector
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.bar', decls, 10, nil, nil)

    refute_equal rule1, rule2
  end

  def test_equality_different_declarations
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [Cataract::Declaration.new('color', 'blue', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls2, 10, nil, nil)

    refute_equal rule1, rule2
  end

  def test_equality_different_declaration_count
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [
      Cataract::Declaration.new('color', 'red', false),
      Cataract::Declaration.new('margin', '10px', false)
    ]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls2, 10, nil, nil)

    refute_equal rule1, rule2
  end

  def test_equality_with_non_rule
    decls = [Cataract::Declaration.new('color', 'red', false)]
    rule = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)

    refute_equal rule, 'not a rule'
    refute_equal rule, nil
  end

  def test_eql_alias
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)

    assert rule1.eql?(rule2), 'eql? should be aliased to =='
  end

  def test_hash_contract_equal_objects_same_hash
    # Hash contract: if a == b, then a.hash == b.hash
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(99, '.foo', decls2, 10, nil, nil)

    assert_equal rule1, rule2, 'Rules should be equal'
    assert_equal rule1.hash, rule2.hash, 'Equal rules must have same hash'
  end

  def test_hash_contract_shorthand_vs_longhand
    # Parse shorthand vs longhand - should have same hash
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    rule1 = sheet1.rules.first
    rule2 = sheet2.rules.first

    assert_equal rule1, rule2, 'Shorthand and longhand should be equal'
    assert_equal rule1.hash, rule2.hash, 'Equal rules must have same hash'
  end

  def test_rules_as_hash_keys
    # Rules should work as Hash keys
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    rule1 = sheet1.rules.first
    rule2 = sheet2.rules.first

    cache = {}
    cache[rule1] = 'cached_value'

    # Should find the value using the equivalent longhand rule
    assert_equal 'cached_value', cache[rule2], 'Equal rules should work as same Hash key'
  end

  def test_rules_in_set
    require 'set'

    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    rule1 = sheet1.rules.first
    rule2 = sheet2.rules.first

    rules = Set.new
    rules << rule1

    assert_includes rules, rule2, 'Set should recognize equivalent longhand rule'
    assert_equal 1, rules.size, 'Set should not add duplicate equivalent rule'

    # Adding the equivalent rule shouldn't change the size
    rules << rule2

    assert_equal 1, rules.size, 'Set should still have only 1 rule after adding equivalent'
  end

  def test_array_uniq_with_shorthand_awareness
    # Array#uniq uses hash + eql? when available
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')
    sheet3 = Cataract.parse_css('.box { color: red; }')

    rules = [sheet1.rules.first, sheet2.rules.first, sheet3.rules.first]

    unique_rules = rules.uniq

    assert_equal 2, unique_rules.length, 'uniq should remove shorthand/longhand duplicate'
  end

  def test_equality_with_string_exact_match
    rule = Cataract.parse_css('.box { color: red; }').rules.first

    assert_equal rule, '.box { color: red; }' # rubocop:disable Minitest/LiteralAsActualArgument
  end

  def test_equality_with_string_shorthand_vs_longhand
    rule = Cataract.parse_css('.box { margin: 10px; }').rules.first

    # Should match longhand equivalent
    assert_equal rule, '.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }' # rubocop:disable Minitest/LiteralAsActualArgument
  end

  def test_equality_with_string_different_selector
    rule = Cataract.parse_css('.box { color: red; }').rules.first

    refute_equal rule, '.other { color: red; }'
  end

  def test_equality_with_string_different_value
    rule = Cataract.parse_css('.box { color: red; }').rules.first

    refute_equal rule, '.box { color: blue; }'
  end

  def test_equality_with_string_multiple_rules
    rule = Cataract.parse_css('.box { color: red; }').rules.first

    # String with multiple rules should not match
    refute_equal rule, '.box { color: red; } .other { margin: 10px; }'
  end

  def test_equality_with_string_empty
    rule = Cataract.parse_css('.box { color: red; }').rules.first

    # Empty CSS string - let parser handle it
    refute_equal rule, ''
  end

  def test_equality_with_string_invalid_css
    rule = Cataract.parse_css('.box { color: red; }').rules.first

    # Invalid CSS - parser will raise or return empty stylesheet
    # Let's see what happens naturally
    result = rule == 'this is not valid css at all { { {'

    refute result, 'Invalid CSS should not match'
  end

  def test_reject_with_string_css
    sheet = Cataract.parse_css('.box { margin: 10px; } .other { color: red; }')

    # Remove rules matching the CSS string
    sheet.rules.reject! { |r| r == '.box { margin: 10px; }' }

    assert_equal 1, sheet.rules.size
    assert_equal '.other', sheet.rules.first.selector
  end

  def test_any_with_string_css
    sheet = Cataract.parse_css('.box { margin: 10px; } .other { color: red; }')

    # Check if any rule matches (with shorthand awareness)
    assert sheet.rules.any? { |r| r == '.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }' }
  end
end
