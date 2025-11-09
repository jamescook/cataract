# frozen_string_literal: true

require_relative 'test_helper'

# CSS Nesting support tests
# Reference: https://www.w3.org/TR/css-nesting-1/
class TestCssNesting < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # Basic nesting with & selector
  def test_basic_nesting_with_ampersand
    css = <<~CSS
      .parent {
        color: red;
        & .child {
          color: blue;
        }
      }
    CSS

    @sheet.add_block(css)

    # Should produce two rules:
    # 1. .parent { color: red; }
    # 2. .parent .child { color: blue; }
    assert_equal 2, @sheet.rules_count

    parent_rule = @sheet.find_by_selector('.parent').first
    child_rule = @sheet.find_by_selector('.parent .child').first

    assert parent_rule, 'Should have .parent rule'
    assert child_rule, 'Should have .parent .child rule'

    assert_has_property({ color: 'red' }, parent_rule)
    assert_has_property({ color: 'blue' }, child_rule)
  end

  # Nesting without & (implicit descendant)
  def test_implicit_descendant_nesting
    css = <<~CSS
      .foo {
        color: red;
        .bar {
          color: blue;
        }
      }
    CSS

    @sheet.add_block(css)

    assert_equal 2, @sheet.rules_count

    foo_rule = @sheet.find_by_selector('.foo').first
    bar_rule = @sheet.find_by_selector('.foo .bar').first

    assert foo_rule, 'Should have .foo rule'
    assert bar_rule, 'Should have .foo .bar rule'

    assert_has_property({ color: 'red' }, foo_rule)
    assert_has_property({ color: 'blue' }, bar_rule)
  end

  # & with class modifier (no space)
  def test_ampersand_with_class_modifier
    css = <<~CSS
      .button {
        color: black;
        &.primary {
          color: blue;
        }
      }
    CSS

    @sheet.add_block(css)

    assert_equal 2, @sheet.rules_count

    button_rule = @sheet.find_by_selector('.button').first
    primary_rule = @sheet.find_by_selector('.button.primary').first

    assert button_rule, 'Should have .button rule'
    assert primary_rule, 'Should have .button.primary rule'

    assert_has_property({ color: 'black' }, button_rule)
    assert_has_property({ color: 'blue' }, primary_rule)
  end

  # & with pseudo-class
  def test_ampersand_with_pseudo_class
    css = <<~CSS
      .link {
        color: blue;
        &:hover {
          color: red;
        }
      }
    CSS

    @sheet.add_block(css)

    assert_equal 2, @sheet.rules_count

    link_rule = @sheet.find_by_selector('.link').first
    hover_rule = @sheet.find_by_selector('.link:hover').first

    assert link_rule, 'Should have .link rule'
    assert hover_rule, 'Should have .link:hover rule'

    assert_has_property({ color: 'blue' }, link_rule)
    assert_has_property({ color: 'red' }, hover_rule)
  end

  # Multiple levels of nesting
  def test_deep_nesting
    css = <<~CSS
      .a {
        color: red;
        .b {
          color: blue;
          .c {
            color: green;
          }
        }
      }
    CSS

    @sheet.add_block(css)

    assert_equal 3, @sheet.rules_count

    a_rule = @sheet.find_by_selector('.a').first
    b_rule = @sheet.find_by_selector('.a .b').first
    c_rule = @sheet.find_by_selector('.a .b .c').first

    assert a_rule, 'Should have .a rule'
    assert b_rule, 'Should have .a .b rule'
    assert c_rule, 'Should have .a .b .c rule'

    assert_has_property({ color: 'red' }, a_rule)
    assert_has_property({ color: 'blue' }, b_rule)
    assert_has_property({ color: 'green' }, c_rule)
  end

  # Comma-separated nested selectors
  def test_comma_separated_nested_selectors
    css = <<~CSS
      .parent {
        &:first-child,
        &:last-child {
          margin: 0;
        }
      }
    CSS

    @sheet.add_block(css)

    # With nesting: 3 rules (.parent:first-child, .parent:last-child, .parent placeholder)
    assert_equal 3, @sheet.rules_count

    first_rule = @sheet.find_by_selector('.parent:first-child').first
    last_rule = @sheet.find_by_selector('.parent:last-child').first

    assert first_rule, 'Should have .parent:first-child rule'
    assert last_rule, 'Should have .parent:last-child rule'

    assert_has_property({ margin: '0' }, first_rule)
    assert_has_property({ margin: '0' }, last_rule)
  end

  # Comma-separated parent with nested child
  def test_comma_separated_parent_with_nested_child
    css = <<~CSS
      .a, .b {
        & .c {
          color: red;
        }
      }
    CSS

    @sheet.add_block(css)

    # With nesting support, creates 4 rules: .a -> .a .c -> .b -> .b .c
    assert_equal 4, @sheet.rules_count

    a_c_rule = @sheet.find_by_selector('.a .c').first
    b_c_rule = @sheet.find_by_selector('.b .c').first

    assert a_c_rule, 'Should have .a .c rule'
    assert b_c_rule, 'Should have .b .c rule'

    assert_has_property({ color: 'red' }, a_c_rule)
    assert_has_property({ color: 'red' }, b_c_rule)
  end

  # Complex example from user
  def test_complex_table_example
    css = <<~CSS
      table.colortable {
        & td {
          text-align: center;
          &.c { text-transform: uppercase }
          &:first-child, &:first-child + td { border: 1px solid black }
        }
        & th {
          text-align: center;
          background: black;
          color: white;
        }
      }
    CSS

    @sheet.add_block(css)

    # With nesting: 6 rules (5 with declarations + table.colortable placeholder)
    # table.colortable td { text-align: center; }
    # table.colortable td.c { text-transform: uppercase; }
    # table.colortable td:first-child { border: 1px solid black; }
    # table.colortable td:first-child + td { border: 1px solid black; }
    # table.colortable th { text-align: center; background: black; color: white; }
    assert_equal 6, @sheet.rules_count

    td_rule = @sheet.find_by_selector('table.colortable td').first
    td_c_rule = @sheet.find_by_selector('table.colortable td.c').first
    td_first_rule = @sheet.find_by_selector('table.colortable td:first-child').first
    td_adjacent_rule = @sheet.find_by_selector('table.colortable td:first-child + td').first
    th_rule = @sheet.find_by_selector('table.colortable th').first

    assert td_rule, 'Should have table.colortable td rule'
    assert td_c_rule, 'Should have table.colortable td.c rule'
    assert td_first_rule, 'Should have table.colortable td:first-child rule'
    assert td_adjacent_rule, 'Should have table.colortable td:first-child + td rule'
    assert th_rule, 'Should have table.colortable th rule'

    assert_has_property({ 'text-align': 'center' }, td_rule)
    assert_has_property({ 'text-transform': 'uppercase' }, td_c_rule)
    assert_has_property({ border: '1px solid black' }, td_first_rule)
    assert_has_property({ border: '1px solid black' }, td_adjacent_rule)
    assert_has_property({ 'text-align': 'center' }, th_rule)
    assert_has_property({ background: 'black' }, th_rule)
    assert_has_property({ color: 'white' }, th_rule)
  end

  # Nested rule with no parent declarations
  def test_nested_rule_with_no_parent_declarations
    css = <<~CSS
      .parent {
        .child {
          color: blue;
        }
      }
    CSS

    @sheet.add_block(css)

    # With nesting: 2 rules (.parent .child + .parent placeholder)
    assert_equal 2, @sheet.rules_count

    child_rule = @sheet.find_by_selector('.parent .child').first

    assert child_rule, 'Should have .parent .child rule'
    assert_has_property({ color: 'blue' }, child_rule)
  end

  # Mixing nested rules and regular declarations
  def test_mixing_nested_and_declarations
    css = <<~CSS
      .parent {
        margin: 10px;
        .child {
          padding: 5px;
        }
        color: red;
      }
    CSS

    @sheet.add_block(css)

    assert_equal 2, @sheet.rules_count

    parent_rule = @sheet.find_by_selector('.parent').first
    child_rule = @sheet.find_by_selector('.parent .child').first

    assert parent_rule, 'Should have .parent rule'
    assert child_rule, 'Should have .parent .child rule'

    # Parent should have both margin and color
    assert_has_property({ margin: '10px' }, parent_rule)
    assert_has_property({ color: 'red' }, parent_rule)
    assert_has_property({ padding: '5px' }, child_rule)
  end

  # Combinators with implicit nesting
  def test_combinators_with_implicit_nesting
    css = <<~CSS
      .parent {
        > .child { color: red; }
        + .sibling { color: blue; }
        ~ .general { color: green; }
      }
    CSS

    @sheet.add_block(css)

    # With nesting: 4 rules (3 with combinators + .parent placeholder)
    assert_equal 4, @sheet.rules_count

    child_rule = @sheet.find_by_selector('.parent > .child').first
    sibling_rule = @sheet.find_by_selector('.parent + .sibling').first
    general_rule = @sheet.find_by_selector('.parent ~ .general').first

    assert child_rule, 'Should have .parent > .child rule'
    assert sibling_rule, 'Should have .parent + .sibling rule'
    assert general_rule, 'Should have .parent ~ .general rule'

    assert_has_property({ color: 'red' }, child_rule)
    assert_has_property({ color: 'blue' }, sibling_rule)
    assert_has_property({ color: 'green' }, general_rule)
  end

  # @media nested inside selector (W3C spec allows this)
  def test_media_nested_inside_selector
    css = <<~CSS
      .foo {
        color: red;
        @media screen {
          color: blue;
        }
      }
    CSS

    @sheet.add_block(css)

    # Should produce:
    # .foo { color: red; } (no media)
    # @media screen { .foo { color: blue; } }
    assert_equal 2, @sheet.rules_count

    foo_rule = @sheet.find_by_selector('.foo', media: :all).first
    foo_screen_rule = @sheet.find_by_selector('.foo', media: :screen).first

    assert foo_rule, 'Should have .foo rule'
    assert foo_screen_rule, 'Should have .foo rule in screen media'

    # All rules should include both (one from general, one from screen)
    all_foo_rules = @sheet.find_by_selector('.foo', media: :all)

    assert_equal 2, all_foo_rules.length
  end

  # ============================================================================
  # Serialization tests (to_s) - compact format
  # ============================================================================

  def test_to_s_with_implicit_nesting
    css = <<~CSS
      .parent {
        color: red;
        .child {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Should reconstruct nested CSS in compact format
    expected = <<~CSS
      .parent { color: red; .child { color: blue; } }
    CSS

    assert_equal expected, output
  end

  def test_to_s_with_explicit_ampersand_nesting
    css = <<~CSS
      .button {
        color: black;
        &:hover {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Should reconstruct with & notation
    expected = <<~CSS
      .button { color: black; &:hover { color: blue; } }
    CSS

    assert_equal expected, output
  end

  def test_to_s_with_ampersand_class_modifier
    css = <<~CSS
      .button {
        &.primary {
          background: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    expected = <<~CSS
      .button { &.primary { background: blue; } }
    CSS

    assert_equal expected, output
  end

  def test_to_s_with_comma_separated_parent
    css = <<~CSS
      .a, .b {
        & .c {
          color: red;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Will be output as separate nested blocks (semantic equivalence)
    # .a { & .c { color: red; } }
    # .b { & .c { color: red; } }
    expected = <<~CSS
      .a { & .c { color: red; } }
      .b { & .c { color: red; } }
    CSS

    assert_equal expected, output
  end

  def test_to_s_with_deep_nesting
    css = <<~CSS
      .a {
        .b {
          .c {
            color: green;
          }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Should preserve multi-level nesting
    expected = <<~CSS
      .a { .b { .c { color: green; } } }
    CSS

    assert_equal expected, output
  end

  def test_to_s_roundtrip_with_nesting
    css = <<~CSS
      .parent {
        margin: 0;
        &.active {
          color: blue;
        }
        .child {
          padding: 10px;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Parse the output again
    sheet2 = Cataract::Stylesheet.parse(output)
    output2 = sheet2.to_s

    # Should be idempotent (structure preserved)
    assert_equal sheet.rules_count, sheet2.rules_count
    assert_equal output, output2, 'to_s should be idempotent'
  end

  def test_to_s_with_mixed_declarations_and_nesting
    css = <<~CSS
      .parent {
        margin: 10px;
        .child {
          padding: 5px;
        }
        color: red;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Declarations should come first, then nested rules
    expected = <<~CSS
      .parent { margin: 10px; color: red; .child { padding: 5px; } }
    CSS

    assert_equal expected, output
  end

  # ============================================================================
  # Serialization tests (to_formatted_s) - formatted with indentation
  # ============================================================================

  def test_to_formatted_s_with_implicit_nesting
    css = <<~CSS
      .parent {
        color: red;
        .child {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_formatted_s

    # Verify proper indentation
    expected = <<~CSS
      .parent {
        color: red;
        .child {
          color: blue;
        }
      }
    CSS

    assert_equal expected, output
  end

  def test_to_formatted_s_with_explicit_ampersand
    css = <<~CSS
      .button {
        color: black;
        &:hover {
          color: blue;
        }
        &.primary {
          background: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_formatted_s

    expected = <<~CSS
      .button {
        color: black;
        &:hover {
          color: blue;
        }
        &.primary {
          background: blue;
        }
      }
    CSS

    assert_equal expected, output
  end

  def test_to_formatted_s_with_deep_nesting
    css = <<~CSS
      .a {
        color: red;
        .b {
          color: blue;
          .c {
            color: green;
          }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_formatted_s

    expected = <<~CSS
      .a {
        color: red;
        .b {
          color: blue;
          .c {
            color: green;
          }
        }
      }
    CSS

    assert_equal expected, output
  end

  def test_to_formatted_s_with_mixed_content
    css = <<~CSS
      .parent {
        margin: 10px;
        .child {
          padding: 5px;
        }
        color: red;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_formatted_s

    # Declarations should come first, then nested rules
    expected = <<~CSS
      .parent {
        margin: 10px;
        color: red;
        .child {
          padding: 5px;
        }
      }
    CSS

    assert_equal expected, output
  end

  def test_to_formatted_s_roundtrip
    css = <<~CSS
      .parent {
        color: red;
        &.active {
          background: blue;
        }
        .child {
          margin: 0;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_formatted_s

    # Parse and format again
    sheet2 = Cataract::Stylesheet.parse(output)
    output2 = sheet2.to_formatted_s

    assert_equal output, output2, 'to_formatted_s should be idempotent'
  end

  # ============================================================================
  # Nested @media serialization tests
  # ============================================================================

  def test_to_s_with_nested_media
    css = <<~CSS
      .foo {
        color: red;
        @media screen {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    # Should reconstruct nested @media
    expected = <<~CSS
      .foo { color: red; @media screen { color: blue; } }
    CSS

    assert_equal expected, output
  end

  def test_to_formatted_s_with_nested_media
    css = <<~CSS
      .foo {
        color: red;
        @media screen {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_formatted_s

    expected = <<~CSS
      .foo {
        color: red;
        @media screen {
          color: blue;
        }
      }
    CSS

    assert_equal expected, output
  end

  def test_to_s_with_multiple_nested_media
    css = <<~CSS
      .container {
        padding: 10px;
        @media screen {
          padding: 20px;
        }
        @media print {
          padding: 0;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    output = sheet.to_s

    expected = <<~CSS
      .container { padding: 10px; @media screen { padding: 20px; } @media print { padding: 0; } }
    CSS

    assert_equal expected, output
  end
end
