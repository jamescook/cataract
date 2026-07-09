# frozen_string_literal: true

require_relative '../test_helper'

# @container (container queries) - https://www.w3.org/TR/css-contain-3/#container-rule
#
# Cataract never evaluates the condition (no real "does this container match
# this size query" logic - that's a runtime/layout concern, out of scope per
# cat-bng). It only needs to preserve the optional name and condition text,
# and which rules it wraps, faithfully enough to round-trip and to be
# queried structurally.
class TestContainerAtRule < Minitest::Test
  include StylesheetTestHelper

  def test_named_container_name_and_condition_are_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar (min-width: 400px) {
        .foo { color: red; }
      }
    CSS

    assert_equal 1, sheet.conditional_groups.size
    group = sheet.conditional_groups.first

    assert_equal :container, group.type
    assert_equal 'sidebar', group.name
    assert_equal '(min-width: 400px)', group.condition
    assert_nil group.parent_id
  end

  def test_anonymous_container_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container (min-width: 400px) {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first

    assert_nil group.name
    assert_equal '(min-width: 400px)', group.condition
  end

  def test_named_container_with_no_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first

    assert_equal 'sidebar', group.name
    assert_nil group.condition
  end

  def test_anonymous_container_with_not_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container not (min-width: 400px) {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first

    assert_nil group.name
    assert_equal 'not (min-width: 400px)', group.condition
  end

  def test_named_container_with_not_condition_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar not (min-width: 400px) {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first

    assert_equal 'sidebar', group.name
    assert_equal 'not (min-width: 400px)', group.condition
  end

  def test_rules_inside_container_are_tagged_with_conditional_group_id
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar (min-width: 400px) {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first
    rule = sheet.with_selector('.foo').first

    assert_equal group.id, rule.conditional_group_id
  end

  def test_rules_inside_container_stay_flat_and_queryable
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar (min-width: 400px) {
        .foo { color: red; }
        .bar { color: blue; }
      }
    CSS

    assert_equal 2, sheet.rules_count
    assert_has_selector '.foo', sheet
    assert_has_selector '.bar', sheet
  end

  def test_named_container_round_trip
    css = <<~CSS
      @container sidebar (min-width: 400px) {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_anonymous_container_round_trip
    css = <<~CSS
      @container (min-width: 400px) {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_named_container_no_condition_round_trip
    css = <<~CSS
      @container sidebar {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_container_round_trip_alongside_unwrapped_rules
    css = <<~CSS
      .before { color: green; }
      @container sidebar (min-width: 400px) {
      .foo { color: red; }
      }
      .after { color: purple; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_container_nested_inside_media_preserves_both_contexts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @media screen {
        @container sidebar (min-width: 400px) {
          .foo { color: red; }
        }
      }
    CSS

    rule = sheet.with_selector('.foo').first

    refute_nil rule.media_query_id
    refute_nil rule.conditional_group_id
    assert_equal :screen, sheet.media_queries[rule.media_query_id].type
    assert_equal :container, sheet.conditional_groups[rule.conditional_group_id].type
  end

  def test_container_nested_inside_media_round_trips
    css = <<~CSS
      @media screen {
      @container sidebar (min-width: 400px) {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_media_nested_inside_container_preserves_both_contexts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar (min-width: 400px) {
        @media screen {
          .foo { color: red; }
        }
      }
    CSS

    rule = sheet.with_selector('.foo').first

    refute_nil rule.media_query_id
    refute_nil rule.conditional_group_id
    assert_equal :screen, sheet.media_queries[rule.media_query_id].type
    assert_equal :container, sheet.conditional_groups[rule.conditional_group_id].type
  end

  def test_container_nested_inside_supports_preserves_both_chain
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        @container sidebar (min-width: 400px) {
          .foo { color: red; }
        }
      }
    CSS

    outer = sheet.conditional_groups.find { |g| g.type == :supports }
    inner = sheet.conditional_groups.find { |g| g.type == :container }
    rule = sheet.with_selector('.foo').first

    assert_nil outer.parent_id
    assert_equal outer.id, inner.parent_id
    assert_equal inner.id, rule.conditional_group_id
  end

  def test_container_nested_inside_supports_round_trips
    css = <<~CSS
      @supports (display: grid) {
      @container sidebar (min-width: 400px) {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_nested_container_tracks_parent_chain
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container outer (min-width: 300px) {
        @container inner (min-width: 400px) {
          .foo { color: red; }
        }
      }
    CSS

    outer = sheet.conditional_groups.find { |g| g.name == 'outer' }
    inner = sheet.conditional_groups.find { |g| g.name == 'inner' }
    rule = sheet.with_selector('.foo').first

    assert_nil outer.parent_id
    assert_equal outer.id, inner.parent_id
    assert_equal inner.id, rule.conditional_group_id
  end

  def test_nested_container_round_trips
    css = <<~CSS
      @container outer (min-width: 300px) {
      @container inner (min-width: 400px) {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_container_dup_produces_independent_conditional_groups
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar (min-width: 400px) {
        .foo { color: red; }
      }
    CSS
    copy = sheet.dup

    assert_equal sheet.conditional_groups.map(&:condition), copy.conditional_groups.map(&:condition)
    assert_no_shared_mutable_state(sheet, copy)
  end

  def test_concat_merges_container_groups_from_both_sheets
    sheet1 = Cataract::Stylesheet.parse(<<~CSS)
      @container sidebar (min-width: 400px) {
        .foo { color: red; }
      }
    CSS
    sheet2 = Cataract::Stylesheet.parse(<<~CSS)
      @container header (min-width: 600px) {
        .bar { color: blue; }
      }
    CSS

    combined = sheet1 + sheet2

    assert_equal 2, combined.conditional_groups.size
    foo = combined.with_selector('.foo').first
    bar = combined.with_selector('.bar').first

    assert_equal 'sidebar', combined.conditional_groups[foo.conditional_group_id].name
    assert_equal 'header', combined.conditional_groups[bar.conditional_group_id].name
  end
end
