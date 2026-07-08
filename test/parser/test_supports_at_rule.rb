# frozen_string_literal: true

require_relative '../test_helper'

# @supports (feature queries) - https://www.w3.org/TR/css-conditional-3/#at-supports
#
# Cataract never evaluates the condition (no real "does the browser support
# this" logic - that's a runtime concern, out of scope per cat-bng). It only
# needs to preserve the condition text and which rules it wraps, faithfully
# enough to round-trip and to be queried structurally.
class TestSupportsAtRule < Minitest::Test
  include StylesheetTestHelper

  def test_supports_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        .foo { color: red; }
      }
    CSS

    assert_equal 1, sheet.conditional_groups.size
    group = sheet.conditional_groups.first

    assert_equal :supports, group.type
    assert_equal '(display: grid)', group.condition
    assert_nil group.name
    assert_nil group.parent_id
  end

  def test_supports_with_not_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports not (display: flex) {
        .fallback { display: block; }
      }
    CSS

    assert_equal 'not (display: flex)', sheet.conditional_groups.first.condition
  end

  def test_supports_with_and_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) and (gap: 1rem) {
        .modern { display: grid; }
      }
    CSS

    assert_equal '(display: grid) and (gap: 1rem)', sheet.conditional_groups.first.condition
  end

  def test_supports_with_or_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: flex) or (display: -webkit-flex) {
        .flex { display: flex; }
      }
    CSS

    assert_equal '(display: flex) or (display: -webkit-flex)', sheet.conditional_groups.first.condition
  end

  def test_rules_inside_supports_are_tagged_with_conditional_group_id
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first
    rule = sheet.with_selector('.foo').first

    assert_equal group.id, rule.conditional_group_id
  end

  def test_rules_outside_supports_have_nil_conditional_group_id
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      .bar { color: blue; }
      @supports (display: grid) {
        .foo { color: red; }
      }
    CSS

    bar = sheet.with_selector('.bar').first

    assert_nil bar.conditional_group_id
  end

  def test_rules_inside_supports_stay_flat_and_queryable
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        .foo { color: red; }
        .bar { color: blue; }
      }
    CSS

    assert_equal 2, sheet.rules_count
    assert_has_selector '.foo', sheet
    assert_has_selector '.bar', sheet
  end

  def test_supports_round_trip_single_rule
    css = <<~CSS
      @supports (display: grid) {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_supports_round_trip_multiple_rules
    css = <<~CSS
      @supports (display: grid) {
      .foo { color: red; }
      .bar { color: blue; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_supports_round_trip_alongside_unwrapped_rules
    css = <<~CSS
      .before { color: green; }
      @supports (display: grid) {
      .foo { color: red; }
      }
      .after { color: purple; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_supports_nested_inside_media_preserves_both_contexts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @media screen {
        @supports (display: grid) {
          .foo { color: red; }
        }
      }
    CSS

    rule = sheet.with_selector('.foo').first

    refute_nil rule.media_query_id, 'rule should still carry its media context'
    refute_nil rule.conditional_group_id, 'rule should also carry its conditional-group context'
    assert_equal :screen, sheet.media_queries[rule.media_query_id].type
    assert_equal :supports, sheet.conditional_groups[rule.conditional_group_id].type
  end

  def test_supports_nested_inside_media_round_trips
    css = <<~CSS
      @media screen {
      @supports (display: grid) {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_media_nested_inside_supports_preserves_both_contexts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        @media screen {
          .foo { color: red; }
        }
      }
    CSS

    rule = sheet.with_selector('.foo').first

    refute_nil rule.media_query_id
    refute_nil rule.conditional_group_id
    assert_equal :screen, sheet.media_queries[rule.media_query_id].type
    assert_equal :supports, sheet.conditional_groups[rule.conditional_group_id].type
  end

  def test_nested_supports_tracks_parent_chain
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        @supports (gap: 1rem) {
          .foo { color: red; }
        }
      }
    CSS

    outer = sheet.conditional_groups.find { |g| g.condition == '(display: grid)' }
    inner = sheet.conditional_groups.find { |g| g.condition == '(gap: 1rem)' }
    rule = sheet.with_selector('.foo').first

    assert_nil outer.parent_id
    assert_equal outer.id, inner.parent_id
    assert_equal inner.id, rule.conditional_group_id
  end

  def test_nested_supports_round_trips
    css = <<~CSS
      @supports (display: grid) {
      @supports (gap: 1rem) {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_supports_dup_produces_independent_conditional_groups
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        .foo { color: red; }
      }
    CSS
    copy = sheet.dup

    assert_equal sheet.conditional_groups.map(&:condition), copy.conditional_groups.map(&:condition)
    assert_no_shared_mutable_state(sheet, copy)
  end

  def test_concat_merges_conditional_groups_from_both_sheets
    sheet1 = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        .foo { color: red; }
      }
    CSS
    sheet2 = Cataract::Stylesheet.parse(<<~CSS)
      @supports (gap: 1rem) {
        .bar { color: blue; }
      }
    CSS

    combined = sheet1 + sheet2

    assert_equal 2, combined.conditional_groups.size
    foo = combined.with_selector('.foo').first
    bar = combined.with_selector('.bar').first

    assert_equal '(display: grid)', combined.conditional_groups[foo.conditional_group_id].condition
    assert_equal '(gap: 1rem)', combined.conditional_groups[bar.conditional_group_id].condition
  end
end
