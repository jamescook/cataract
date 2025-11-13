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

    result = sheet.merge

    assert_equal 1, result.rules.size
    assert result.rules.first.has_property?('color', 'blue')
  end

  def test_merge_bang_alias_still_works
    # Keep for backwards compatibility
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.merge!

    assert_same sheet, result
    assert_equal 1, sheet.rules.size
  end
end
