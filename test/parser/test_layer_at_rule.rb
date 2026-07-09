# frozen_string_literal: true

require_relative '../test_helper'

# @layer (cascade layers) - https://www.w3.org/TR/css-cascade-5/#layering
#
# @layer has two forms:
# - Block form: `@layer name? { ... }` - wraps rules, name optional
#   (anonymous). A dotted name (`a.b`) is shorthand for nesting
#   (`@layer a { @layer b { ... } }`) - both are treated as opaque name
#   text here, since Cataract doesn't compute the effective cascade layer
#   graph, only preserves whatever nesting form was written.
# - Statement form: `@layer name#;` - comma-separated names, declares
#   layer order only, wraps no rules at all. Represented as an AtRule
#   (mirrors @keyframes/@font-face) with content nil, since there's
#   nothing to wrap.
#
# Cataract never computes cascade layer order/precedence - it only
# preserves names and wrapped rules faithfully enough to round-trip and
# be queried structurally.
class TestLayerAtRule < Minitest::Test
  include StylesheetTestHelper

  # --- Block form ---

  def test_named_layer_name_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer utilities {
        .foo { color: red; }
      }
    CSS

    assert_equal 1, sheet.conditional_groups.size
    group = sheet.conditional_groups.first

    assert_equal :layer, group.type
    assert_equal 'utilities', group.name
    assert_nil group.condition
    assert_nil group.parent_id
  end

  def test_anonymous_layer_is_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first

    assert_equal :layer, group.type
    assert_nil group.name
  end

  def test_dotted_layer_name_is_preserved_as_single_opaque_string
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer framework.layout {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first

    assert_equal 'framework.layout', group.name
  end

  def test_rules_inside_layer_are_tagged_with_conditional_group_id
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer utilities {
        .foo { color: red; }
      }
    CSS

    group = sheet.conditional_groups.first
    rule = sheet.with_selector('.foo').first

    assert_equal group.id, rule.conditional_group_id
  end

  def test_rules_inside_layer_stay_flat_and_queryable
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer utilities {
        .foo { color: red; }
        .bar { color: blue; }
      }
    CSS

    assert_equal 2, sheet.rules_count
    assert_has_selector '.foo', sheet
    assert_has_selector '.bar', sheet
  end

  def test_named_layer_round_trip
    css = <<~CSS
      @layer utilities {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_anonymous_layer_round_trip
    css = <<~CSS
      @layer {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_dotted_layer_round_trip
    css = <<~CSS
      @layer framework.layout {
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_layer_round_trip_alongside_unwrapped_rules
    css = <<~CSS
      .before { color: green; }
      @layer utilities {
      .foo { color: red; }
      }
      .after { color: purple; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_layer_nested_inside_media_preserves_both_contexts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @media screen {
        @layer utilities {
          .foo { color: red; }
        }
      }
    CSS

    rule = sheet.with_selector('.foo').first

    refute_nil rule.media_query_id
    refute_nil rule.conditional_group_id
    assert_equal :screen, sheet.media_queries[rule.media_query_id].type
    assert_equal :layer, sheet.conditional_groups[rule.conditional_group_id].type
  end

  def test_layer_nested_inside_media_round_trips
    css = <<~CSS
      @media screen {
      @layer utilities {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_media_nested_inside_layer_preserves_both_contexts
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer utilities {
        @media screen {
          .foo { color: red; }
        }
      }
    CSS

    rule = sheet.with_selector('.foo').first

    refute_nil rule.media_query_id
    refute_nil rule.conditional_group_id
    assert_equal :screen, sheet.media_queries[rule.media_query_id].type
    assert_equal :layer, sheet.conditional_groups[rule.conditional_group_id].type
  end

  def test_layer_nested_inside_supports_preserves_both_chain
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @supports (display: grid) {
        @layer utilities {
          .foo { color: red; }
        }
      }
    CSS

    outer = sheet.conditional_groups.find { |g| g.type == :supports }
    inner = sheet.conditional_groups.find { |g| g.type == :layer }
    rule = sheet.with_selector('.foo').first

    assert_nil outer.parent_id
    assert_equal outer.id, inner.parent_id
    assert_equal inner.id, rule.conditional_group_id
  end

  def test_layer_nested_inside_supports_round_trips
    css = <<~CSS
      @supports (display: grid) {
      @layer utilities {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_nested_layer_via_block_form_tracks_parent_chain
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer outer {
        @layer inner {
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

  def test_nested_layer_via_block_form_round_trips
    css = <<~CSS
      @layer outer {
      @layer inner {
      .foo { color: red; }
      }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_layer_dup_produces_independent_conditional_groups
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer utilities {
        .foo { color: red; }
      }
    CSS
    copy = sheet.dup

    assert_equal sheet.conditional_groups.map(&:name), copy.conditional_groups.map(&:name)
    assert_no_shared_mutable_state(sheet, copy)
  end

  def test_concat_merges_layer_groups_from_both_sheets
    sheet1 = Cataract::Stylesheet.parse(<<~CSS)
      @layer utilities {
        .foo { color: red; }
      }
    CSS
    sheet2 = Cataract::Stylesheet.parse(<<~CSS)
      @layer base {
        .bar { color: blue; }
      }
    CSS

    combined = sheet1 + sheet2

    assert_equal 2, combined.conditional_groups.size
    foo = combined.with_selector('.foo').first
    bar = combined.with_selector('.bar').first

    assert_equal 'utilities', combined.conditional_groups[foo.conditional_group_id].name
    assert_equal 'base', combined.conditional_groups[bar.conditional_group_id].name
  end

  # --- Statement form ---

  def test_statement_single_name_is_preserved
    sheet = Cataract::Stylesheet.parse('@layer utilities;')

    assert_equal 1, sheet.size
    at_rule = sheet.rules.first

    assert at_rule.at_rule_type?(:layer)
    assert_equal '@layer utilities', at_rule.selector
    assert_nil at_rule.content
  end

  def test_statement_multiple_names_are_preserved
    sheet = Cataract::Stylesheet.parse('@layer base, utilities, overrides;')

    at_rule = sheet.rules.first

    assert_equal '@layer base, utilities, overrides', at_rule.selector
  end

  def test_statement_dotted_name_is_preserved
    sheet = Cataract::Stylesheet.parse('@layer framework.layout;')

    at_rule = sheet.rules.first

    assert_equal '@layer framework.layout', at_rule.selector
  end

  def test_statement_form_creates_no_conditional_group
    sheet = Cataract::Stylesheet.parse('@layer base, utilities;')

    assert_empty sheet.conditional_groups
  end

  def test_statement_round_trip
    css = "@layer base, utilities;\n"
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_statement_does_not_corrupt_the_following_rule
    # Regression: the at-rule scanner used to search only for '{', running
    # straight through the statement's ';' and swallowing the next rule's
    # block as if it were the @layer's own content.
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @layer base, utilities;
      .foo { color: red; }
    CSS

    assert_equal 2, sheet.size
    assert_has_selector '.foo', sheet
    rule = sheet.with_selector('.foo').first

    assert_has_property({ color: 'red' }, rule)
  end

  def test_statement_round_trip_alongside_other_rules
    css = <<~CSS
      @layer base, utilities;
      .foo { color: red; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_statement_nested_inside_media_preserves_media_context
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @media screen {
        @layer base, utilities;
        .foo { color: red; }
      }
    CSS

    at_rule = sheet.rules.find { |r| r.at_rule_type?(:layer) }

    refute_nil at_rule.media_query_id
    assert_equal :screen, sheet.media_queries[at_rule.media_query_id].type
  end

  def test_statement_nested_inside_media_round_trips
    css = <<~CSS
      @media screen {
      @layer base, utilities;
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end
end
