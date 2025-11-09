# frozen_string_literal: true

require_relative 'test_helper'

class TestAtRule < Minitest::Test
  def test_selector_predicate
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    refute_predicate at_rule, :selector?
  end

  def test_at_rule_predicate
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    assert_predicate at_rule, :at_rule?
  end

  def test_at_rule_type_keyframes
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    assert at_rule.at_rule_type?(:keyframes)
    refute at_rule.at_rule_type?(:font_face)
    refute at_rule.at_rule_type?(:media)
  end

  def test_at_rule_type_font_face
    at_rule = Cataract::AtRule.new(0, '@font-face', [], nil)

    assert at_rule.at_rule_type?(:font_face)
    refute at_rule.at_rule_type?(:keyframes)
  end

  def test_has_property_returns_false
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    refute at_rule.has_property?('color')
    refute at_rule.has_property?('opacity')
  end

  def test_has_property_with_value_returns_false
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    refute at_rule.has_property?('opacity', '0')
  end

  def test_has_important_returns_false
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    refute_predicate at_rule, :has_important?
    refute at_rule.has_important?('opacity')
  end

  def test_equality_same_attributes
    at_rule1 = Cataract::AtRule.new(0, '@keyframes fade', [], nil)
    at_rule2 = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    assert_equal at_rule1, at_rule2
  end

  def test_equality_different_selector
    at_rule1 = Cataract::AtRule.new(0, '@keyframes fade', [], nil)
    at_rule2 = Cataract::AtRule.new(0, '@keyframes slide', [], nil)

    refute_equal at_rule1, at_rule2
  end

  def test_equality_different_id
    at_rule1 = Cataract::AtRule.new(0, '@keyframes fade', [], nil)
    at_rule2 = Cataract::AtRule.new(1, '@keyframes fade', [], nil)

    refute_equal at_rule1, at_rule2
  end

  def test_equality_with_non_at_rule
    at_rule = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    refute_equal at_rule, 'not an at-rule'
    refute_equal at_rule, nil
  end

  def test_eql_alias
    at_rule1 = Cataract::AtRule.new(0, '@keyframes fade', [], nil)
    at_rule2 = Cataract::AtRule.new(0, '@keyframes fade', [], nil)

    assert at_rule1.eql?(at_rule2)
  end
end
