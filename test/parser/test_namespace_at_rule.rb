# frozen_string_literal: true

require_relative '../test_helper'

# @namespace (CSS Namespaces Module) - https://www.w3.org/TR/css-namespaces-3/
#
# Unlike @layer/@supports/@container, @namespace has only ONE form - it's
# purely a statement (grammar: NAMESPACE_SYM S* [prefix S*]? [STRING|URI] S*
# ';'), never a block. It declares either the default namespace (no prefix)
# or a prefix->URI mapping, consumed later by namespaced selectors
# (ns|E, *|E, |E - see test_css2_features.rb). Multiple @namespace rules are
# legal (one default + any number of prefixed ones), and - like @layer's
# statement form - Cataract doesn't compute any resolution/merge semantics,
# it just captures each declaration verbatim as an AtRule with content nil.
class TestNamespaceAtRule < Minitest::Test
  include StylesheetTestHelper

  def test_default_namespace_with_url_is_preserved
    sheet = Cataract::Stylesheet.parse('@namespace url(http://www.w3.org/1999/xhtml);')

    assert_equal 1, sheet.size
    at_rule = sheet.rules.first

    assert at_rule.at_rule_type?(:namespace)
    assert_equal '@namespace url(http://www.w3.org/1999/xhtml)', at_rule.selector
    assert_nil at_rule.content
  end

  def test_default_namespace_with_string_is_preserved
    sheet = Cataract::Stylesheet.parse('@namespace "http://www.w3.org/1999/xhtml";')

    at_rule = sheet.rules.first

    assert_equal '@namespace "http://www.w3.org/1999/xhtml"', at_rule.selector
  end

  def test_prefixed_namespace_with_url_is_preserved
    sheet = Cataract::Stylesheet.parse('@namespace svg url(http://www.w3.org/2000/svg);')

    at_rule = sheet.rules.first

    assert_equal '@namespace svg url(http://www.w3.org/2000/svg)', at_rule.selector
  end

  def test_prefixed_namespace_with_string_is_preserved
    sheet = Cataract::Stylesheet.parse('@namespace svg "http://www.w3.org/2000/svg";')

    at_rule = sheet.rules.first

    assert_equal '@namespace svg "http://www.w3.org/2000/svg"', at_rule.selector
  end

  def test_multiple_namespace_declarations_are_each_preserved
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @namespace url(http://www.w3.org/1999/xhtml);
      @namespace svg url(http://www.w3.org/2000/svg);
    CSS

    assert_equal 2, sheet.size
    assert_equal '@namespace url(http://www.w3.org/1999/xhtml)', sheet.rules[0].selector
    assert_equal '@namespace svg url(http://www.w3.org/2000/svg)', sheet.rules[1].selector
  end

  def test_namespace_creates_no_conditional_group
    sheet = Cataract::Stylesheet.parse('@namespace svg url(http://www.w3.org/2000/svg);')

    assert_empty sheet.conditional_groups
  end

  def test_namespace_round_trip
    css = "@namespace svg url(http://www.w3.org/2000/svg);\n"
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_namespace_string_form_round_trip
    css = "@namespace \"http://www.w3.org/1999/xhtml\";\n"
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  def test_namespace_does_not_corrupt_the_following_rule
    # Regression: mirrors the equivalent @layer statement-form bug - the
    # at-rule scanner must stop at ';', not run through it into whatever
    # rule happens to follow.
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @namespace svg url(http://www.w3.org/2000/svg);
      .foo { color: red; }
    CSS

    assert_equal 2, sheet.size
    assert_has_selector '.foo', sheet
    rule = sheet.with_selector('.foo').first

    assert_has_property({ color: 'red' }, rule)
  end

  def test_namespace_round_trip_alongside_other_rules
    css = <<~CSS
      @namespace svg url(http://www.w3.org/2000/svg);
      .foo { color: red; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end

  # --- Minified / no-space edge cases ---
  #
  # A quote character isn't a valid CSS ident character, so the tokenizer
  # naturally splits "@namespace" from a directly-following string with no
  # whitespace required in between (unlike e.g. "@namespace url(...)",
  # where "url" being an ident DOES require a separating space or it merges
  # into one long at-keyword). This mirrors the minified @supports/@media
  # bug fixed elsewhere in this parser (name-scanning must stop at any
  # non-ident terminator, not just whitespace/'{').

  def test_default_namespace_minified_with_no_space_before_string
    sheet = Cataract::Stylesheet.parse('@namespace"http://www.w3.org/1999/xhtml";')

    at_rule = sheet.rules.first

    assert at_rule.at_rule_type?(:namespace)
    assert_equal '@namespace"http://www.w3.org/1999/xhtml"', at_rule.selector
  end

  def test_prefixed_namespace_minified_with_no_space_before_string
    sheet = Cataract::Stylesheet.parse('@namespace svg"http://www.w3.org/2000/svg";')

    at_rule = sheet.rules.first

    assert_equal '@namespace svg"http://www.w3.org/2000/svg"', at_rule.selector
  end

  def test_namespace_minified_does_not_corrupt_the_following_rule
    sheet = Cataract::Stylesheet.parse('@namespace svg"http://www.w3.org/2000/svg";.foo{color:red}')

    assert_equal 2, sheet.size
    assert_has_selector '.foo', sheet
  end

  def test_namespace_uri_containing_semicolon_is_not_truncated
    # A url() value could (rarely) contain an unescaped ';' - e.g. a data
    # URI - which must not be mistaken for the statement's own terminator.
    sheet = Cataract::Stylesheet.parse('@namespace svg url(data:image/svg+xml;base64,abc==);')

    at_rule = sheet.rules.first

    assert_equal '@namespace svg url(data:image/svg+xml;base64,abc==)', at_rule.selector
  end

  def test_namespace_nested_inside_media_preserves_media_context
    sheet = Cataract::Stylesheet.parse(<<~CSS)
      @media screen {
        @namespace svg url(http://www.w3.org/2000/svg);
        .foo { color: red; }
      }
    CSS

    at_rule = sheet.rules.find { |r| r.at_rule_type?(:namespace) }

    refute_nil at_rule.media_query_id
    assert_equal :screen, sheet.media_queries[at_rule.media_query_id].type
  end

  def test_namespace_nested_inside_media_round_trips
    css = <<~CSS
      @media screen {
      @namespace svg url(http://www.w3.org/2000/svg);
      .foo { color: red; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal css, sheet.to_s
  end
end
