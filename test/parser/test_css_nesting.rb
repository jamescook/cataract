# frozen_string_literal: true

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

    parent_rule = @sheet.with_selector('.parent').first
    child_rule = @sheet.with_selector('.parent .child').first

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

    foo_rule = @sheet.with_selector('.foo').first
    bar_rule = @sheet.with_selector('.foo .bar').first

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

    button_rule = @sheet.with_selector('.button').first
    primary_rule = @sheet.with_selector('.button.primary').first

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

    link_rule = @sheet.with_selector('.link').first
    hover_rule = @sheet.with_selector('.link:hover').first

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

    a_rule = @sheet.with_selector('.a').first
    b_rule = @sheet.with_selector('.a .b').first
    c_rule = @sheet.with_selector('.a .b .c').first

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

    first_rule = @sheet.with_selector('.parent:first-child').first
    last_rule = @sheet.with_selector('.parent:last-child').first

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

    a_c_rule = @sheet.with_selector('.a .c').first
    b_c_rule = @sheet.with_selector('.b .c').first

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

    td_rule = @sheet.with_selector('table.colortable td').first
    td_c_rule = @sheet.with_selector('table.colortable td.c').first
    td_first_rule = @sheet.with_selector('table.colortable td:first-child').first
    td_adjacent_rule = @sheet.with_selector('table.colortable td:first-child + td').first
    th_rule = @sheet.with_selector('table.colortable th').first

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

    child_rule = @sheet.with_selector('.parent .child').first

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

    parent_rule = @sheet.with_selector('.parent').first
    child_rule = @sheet.with_selector('.parent .child').first

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

    child_rule = @sheet.with_selector('.parent > .child').first
    sibling_rule = @sheet.with_selector('.parent + .sibling').first
    general_rule = @sheet.with_selector('.parent ~ .general').first

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

    foo_rule = @sheet.with_media(:all).with_selector('.foo').first
    foo_screen_rule = @sheet.with_media(:screen).with_selector('.foo').first

    assert foo_rule, 'Should have .foo rule'
    assert foo_screen_rule, 'Should have .foo rule in screen media'

    # All rules should include both (one from general, one from screen)
    all_foo_rules = @sheet.with_media(:all).with_selector('.foo')

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

  def test_nested_media_within_css_nesting_combines_media_queries
    # Test that @media nested inside a CSS nesting block properly combines MediaQuery objects
    # This exercises the parse_mixed_block path where parent_media_query_id is passed
    css = <<~CSS
      .parent {
        @media screen {
          @media (min-width: 500px) {
            color: red;
          }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Find the rule with the color declaration (the innermost nested @media rule)
    rule_with_color = sheet.rules.find { |r| r.declarations.any? { |d| d.property == 'color' } }

    refute_nil rule_with_color, 'Should have a rule with color declaration'
    assert_equal '.parent', rule_with_color.selector

    # Verify the combined MediaQuery was created (screen + min-width condition)
    refute_nil rule_with_color.media_query_id
    mq = sheet.media_queries[rule_with_color.media_query_id]

    refute_nil mq
    assert_equal :screen, mq.type
    assert_equal '(min-width: 500px)', mq.conditions
  end

  def test_nested_media_with_both_parent_and_child_conditions_in_css_nesting
    # Test combining when BOTH parent and child @media have conditions inside CSS nesting
    css = <<~CSS
      .widget {
        @media screen and (orientation: landscape) {
          @media (min-width > 1024px) {
            font-size: 20px;
          }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Find the rule with the font-size declaration
    rule_with_font = sheet.rules.find { |r| r.declarations.any? { |d| d.property == 'font-size' } }

    refute_nil rule_with_font, 'Should have a rule with font-size declaration'

    # Verify combined MediaQuery has both conditions joined by " and "
    mq = sheet.media_queries[rule_with_font.media_query_id]

    assert_equal :screen, mq.type
    assert_equal '(orientation: landscape) and (min-width > 1024px)', mq.conditions
  end

  # Test recursion depth limit (MAX_PARSE_DEPTH = 10)
  def test_depth_error_on_deep_nesting
    # Build CSS with 10 nested & .x blocks (depth 11: .a at 1, then 10 nested = exceeds limit)
    css = ".a { #{'& .x { ' * 10}color: red;#{' }' * 10} }"

    error = assert_raises(Cataract::DepthError) do
      Cataract::Stylesheet.parse(css)
    end

    assert_equal 'CSS nesting too deep: exceeded maximum depth of 10', error.message
  end

  # Test depth error with @media nesting
  def test_depth_error_with_media_nesting
    # Build deeply nested @media queries (11 levels total)
    css = "#{'@media a { ' * 11}body { margin: 0; }#{' }' * 11}"

    error = assert_raises(Cataract::DepthError) do
      Cataract::Stylesheet.parse(css)
    end

    assert_equal 'CSS nesting too deep: exceeded maximum depth of 10', error.message
  end

  # Test that depth error doesn't trigger at exactly max depth
  def test_depth_ok_at_maximum
    # Build CSS with 9 nested & .x blocks (depth 10: .a at 1, then 9 nested = max allowed)
    css = ".a { #{'& .x { ' * 9}color: red;#{' }' * 9} }"

    # Should not raise DepthError
    sheet = Cataract::Stylesheet.parse(css)

    assert_predicate sheet.rules_count, :positive?
  end

  # W3C Spec Example 1: & can be used on its own
  # https://www.w3.org/TR/css-nesting-1/
  def test_w3c_example_ampersand_on_its_own
    css = <<~CSS
      .foo {
        color: blue;
        & > .bar { color: red; }
        > .baz { color: green; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 3 rules:
    # .foo { color: blue; }
    # .foo > .bar { color: red; }
    # .foo > .baz { color: green; }
    assert_equal 3, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    bar_rule = sheet.with_selector('.foo > .bar').first
    baz_rule = sheet.with_selector('.foo > .baz').first

    assert foo_rule, 'Should have .foo rule'
    assert bar_rule, 'Should have .foo > .bar rule'
    assert baz_rule, 'Should have .foo > .baz rule'

    assert_has_property({ color: 'blue' }, foo_rule)
    assert_has_property({ color: 'red' }, bar_rule)
    assert_has_property({ color: 'green' }, baz_rule)
  end

  # W3C Spec Example 2: & in compound selector
  def test_w3c_example_compound_selector
    css = <<~CSS
      .foo {
        color: blue;
        &.bar { color: red; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: blue; }
    # .foo.bar { color: red; }
    assert_equal 2, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    foobar_rule = sheet.with_selector('.foo.bar').first

    assert foo_rule, 'Should have .foo rule'
    assert foobar_rule, 'Should have .foo.bar rule'

    assert_has_property({ color: 'blue' }, foo_rule)
    assert_has_property({ color: 'red' }, foobar_rule)
  end

  # W3C Spec Example: Multiple levels of nesting
  def test_w3c_example_multiple_levels
    css = <<~CSS
      figure {
        margin: 0;

        > figcaption {
          background: hsl(0 0% 0% / 50%);

          > p {
            font-size: .9rem;
          }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 3 rules:
    # figure { margin: 0; }
    # figure > figcaption { background: hsl(0 0% 0% / 50%); }
    # figure > figcaption > p { font-size: .9rem; }
    assert_equal 3, sheet.rules_count

    figure_rule = sheet.with_selector('figure').first
    figcaption_rule = sheet.with_selector('figure > figcaption').first
    p_rule = sheet.with_selector('figure > figcaption > p').first

    assert figure_rule, 'Should have figure rule'
    assert figcaption_rule, 'Should have figure > figcaption rule'
    assert p_rule, 'Should have figure > figcaption > p rule'

    assert_has_property({ margin: '0' }, figure_rule)
    assert_has_property({ background: 'hsl(0 0% 0% / 50%)' }, figcaption_rule)
    assert_has_property({ 'font-size': '.9rem' }, p_rule)
  end

  # W3C Spec Example: Mixing declarations with nested rules
  # Per spec: "nested style rules are considered to come after their parent rule"
  def test_w3c_example_mixed_declarations_cascade_order
    css = <<~CSS
      article {
        color: blue;
        & { color: red; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules (parent + nested):
    # article { color: blue; }
    # article { color: red; }
    # Both have same selector and specificity, but nested comes after
    assert_equal 2, sheet.rules_count

    article_rules = sheet.with_selector('article')

    assert_equal 2, article_rules.length, 'Should have 2 article rules'

    # First rule should have color: blue
    assert_has_property({ color: 'blue' }, article_rules[0])
    # Second rule should have color: red
    assert_has_property({ color: 'red' }, article_rules[1])
  end

  # W3C Spec Example: & can be used multiple times in a single selector
  def test_w3c_example_ampersand_multiple_times
    css = <<~CSS
      .foo {
        color: blue;
        & .bar & .baz & .qux { color: red; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: blue; }
    # .foo .bar .foo .baz .foo .qux { color: red; }
    assert_equal 2, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    complex_rule = sheet.with_selector('.foo .bar .foo .baz .foo .qux').first

    assert foo_rule, 'Should have .foo rule'
    assert complex_rule, 'Should have .foo .bar .foo .baz .foo .qux rule'

    assert_has_property({ color: 'blue' }, foo_rule)
    assert_has_property({ color: 'red' }, complex_rule)
  end

  # W3C Spec Example: & doesn't have to be at the beginning
  def test_w3c_example_ampersand_not_at_beginning
    css = <<~CSS
      .foo {
        color: red;
        .parent & {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: red; }
    # .parent .foo { color: blue; }
    assert_equal 2, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    parent_foo_rule = sheet.with_selector('.parent .foo').first

    assert foo_rule, 'Should have .foo rule'
    assert parent_foo_rule, 'Should have .parent .foo rule'

    assert_has_property({ color: 'red' }, foo_rule)
    assert_has_property({ color: 'blue' }, parent_foo_rule)
  end

  # W3C Spec Example: & with :not()
  def test_w3c_example_ampersand_with_not
    css = <<~CSS
      .foo {
        color: red;
        :not(&) {
          color: blue;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: red; }
    # :not(.foo) { color: blue; }
    assert_equal 2, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    not_foo_rule = sheet.with_selector(':not(.foo)').first

    assert foo_rule, 'Should have .foo rule'
    assert not_foo_rule, 'Should have :not(.foo) rule'

    assert_has_property({ color: 'red' }, foo_rule)
    assert_has_property({ color: 'blue' }, not_foo_rule)
  end

  # W3C Spec Example: Relative selector with implied &
  def test_w3c_example_relative_selector
    css = <<~CSS
      .foo {
        color: red;
        + .bar + & { color: blue; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: red; }
    # .foo + .bar + .foo { color: blue; }
    assert_equal 2, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    complex_rule = sheet.with_selector('.foo + .bar + .foo').first

    assert foo_rule, 'Should have .foo rule'
    assert complex_rule, 'Should have .foo + .bar + .foo rule'

    assert_has_property({ color: 'red' }, foo_rule)
    assert_has_property({ color: 'blue' }, complex_rule)
  end

  # W3C Spec Example: & used all on its own
  def test_w3c_example_ampersand_alone
    css = <<~CSS
      .foo {
        color: blue;
        & { padding: 2ch; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: blue; }
    # .foo { padding: 2ch; }
    assert_equal 2, sheet.rules_count

    foo_rules = sheet.with_selector('.foo')

    assert_equal 2, foo_rules.length, 'Should have 2 .foo rules'

    assert_has_property({ color: 'blue' }, foo_rules[0])
    assert_has_property({ padding: '2ch' }, foo_rules[1])
  end

  # W3C Spec Example: && doubled up
  def test_w3c_example_ampersand_doubled
    css = <<~CSS
      .foo {
        color: blue;
        && { padding: 2ch; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { color: blue; }
    # .foo.foo { padding: 2ch; }
    assert_equal 2, sheet.rules_count

    foo_rule = sheet.with_selector('.foo').first
    foo_foo_rule = sheet.with_selector('.foo.foo').first

    assert foo_rule, 'Should have .foo rule'
    assert foo_foo_rule, 'Should have .foo.foo rule'

    assert_has_property({ color: 'blue' }, foo_rule)
    assert_has_property({ padding: '2ch' }, foo_foo_rule)
  end

  # W3C Spec Example: Nesting @media with properties
  def test_w3c_example_media_nesting_simple
    css = <<~CSS
      .foo {
        display: grid;

        @media (orientation: landscape) {
          grid-auto-flow: column;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 2 rules:
    # .foo { display: grid; }
    # @media (orientation: landscape) { .foo { grid-auto-flow: column; } }
    assert_equal 2, sheet.rules_count

    foo_base = sheet.with_selector('.foo').find { |r| r.declarations.any? { |d| d.property == 'display' } }
    foo_media = sheet.with_selector('.foo').find { |r| r.declarations.any? { |d| d.property == 'grid-auto-flow' } }

    assert foo_base, 'Should have .foo rule with display'
    assert foo_media, 'Should have .foo rule with grid-auto-flow (in @media)'

    assert_has_property({ display: 'grid' }, foo_base)
    assert_has_property({ 'grid-auto-flow': 'column' }, foo_media)

    # Check media query is set correctly
    # Media queries with only conditions (no type) are indexed under :all
    media_sym = sheet.media_index.find { |_, ids| ids.include?(foo_media.id) }&.first

    assert media_sym, 'Should have media query for foo_media rule'
    assert_equal :all, media_sym

    # Check the actual MediaQuery object has the conditions
    mq = sheet.media_queries[foo_media.media_query_id]

    assert_equal :all, mq.type
    assert_equal '(orientation: landscape)', mq.conditions
  end

  # W3C Spec Example: Nested @media queries
  def test_w3c_example_media_nesting_nested
    css = <<~CSS
      .foo {
        display: grid;

        @media (orientation: landscape) {
          grid-auto-flow: column;

          @media (min-width > 1024px) {
            max-inline-size: 1024px;
          }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should produce 3 rules:
    # .foo { display: grid; }
    # @media (orientation: landscape) { .foo { grid-auto-flow: column; } }
    # @media (orientation: landscape) and (min-width > 1024px) { .foo { max-inline-size: 1024px; } }
    assert_equal 3, sheet.rules_count

    foo_base = sheet.with_selector('.foo').find { |r| r.declarations.any? { |d| d.property == 'display' } }
    foo_landscape = sheet.with_selector('.foo').find { |r| r.declarations.any? { |d| d.property == 'grid-auto-flow' } }
    foo_nested = sheet.with_selector('.foo').find { |r| r.declarations.any? { |d| d.property == 'max-inline-size' } }

    assert foo_base, 'Should have .foo rule with display'
    assert foo_landscape, 'Should have .foo rule with grid-auto-flow'
    assert foo_nested, 'Should have .foo rule with max-inline-size'

    assert_has_property({ display: 'grid' }, foo_base)
    assert_has_property({ 'grid-auto-flow': 'column' }, foo_landscape)
    assert_has_property({ 'max-inline-size': '1024px' }, foo_nested)

    # Check media queries
    # Media queries with only conditions (no type) are indexed under :all
    media_index = sheet.media_index
    landscape_media = media_index.find { |_, ids| ids.include?(foo_landscape.id) }&.first
    nested_media = media_index.find { |_, ids| ids.include?(foo_nested.id) }&.first

    assert_equal :all, landscape_media
    # Combined media query should also be indexed under :all
    assert_equal :all, nested_media

    # Check the actual MediaQuery objects have the correct conditions
    landscape_mq = sheet.media_queries[foo_landscape.media_query_id]

    assert_equal '(orientation: landscape)', landscape_mq.conditions

    nested_mq = sheet.media_queries[foo_nested.media_query_id]
    # Combined media query should be: (orientation: landscape) and (min-width > 1024px)
    assert_equal '(orientation: landscape) and (min-width > 1024px)', nested_mq.conditions
  end

  # W3C Spec Example: Mixed declarations order doesn't matter
  def test_w3c_example_mixed_declarations_order
    css = <<~CSS
      article {
        color: green;
        & { color: blue; }
        color: red;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Per spec: "relative order of declarations vs other rules is not preserved"
    # Equivalent to:
    # article { color: green; color: red; & { color: blue; } }
    # So we should have 2 rules:
    # article { color: green; color: red; } (both declarations in parent)
    # article { color: blue; } (nested rule)
    assert_equal 2, sheet.rules_count

    article_rules = sheet.with_selector('article')

    assert_equal 2, article_rules.length, 'Should have 2 article rules'

    # Parent rule should have both green and red (red wins in cascade)
    parent_rule = article_rules[0]

    assert_equal 2, parent_rule.declarations.length, 'Parent should have 2 color declarations'

    # Nested rule should have blue
    nested_rule = article_rules[1]

    assert_has_property({ color: 'blue' }, nested_rule)
  end

  # Rule order: parent must come before nested in array order for proper cascade
  def test_parent_rule_comes_before_nested_in_array
    css = <<~CSS
      .parent {
        color: blue;
        & .child { color: red; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    rules = sheet.instance_variable_get(:@rules)

    # Find indices
    parent_idx = rules.index { |r| r.selector == '.parent' }
    child_idx = rules.index { |r| r.selector == '.parent .child' }

    assert parent_idx, 'Should have .parent rule'
    assert child_idx, 'Should have .parent .child rule'
    assert_operator parent_idx, :<, child_idx, 'Parent rule must come before nested child in array order'
  end

  def test_nested_important_declarations
    css = <<~CSS
      .parent {
        .child {
          color: blue !important;
          margin: 10px;
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    child_rule = sheet.with_selector('.parent .child').first

    assert child_rule, 'Should have .parent .child rule'

    color_decl = child_rule.declarations.find { |d| d.property == 'color' }
    margin_decl = child_rule.declarations.find { |d| d.property == 'margin' }

    assert color_decl, 'Should have color declaration'
    assert_equal 'blue', color_decl.value, 'Color value should not include !important'
    assert color_decl.important, 'Color declaration should be marked as important'

    assert margin_decl, 'Should have margin declaration'
    assert_equal '10px', margin_decl.value
    refute margin_decl.important, 'Margin declaration should not be marked as important'
  end
end
