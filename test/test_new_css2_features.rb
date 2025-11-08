# frozen_string_literal: true

require_relative 'test_helper'

# Tests for CSS2 features that are not yet implemented
# These tests are expected to fail until the features are added
class TestNewCSS2Features < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # ============================================================================
  # @media Rules (CSS2 - Critical)
  # ============================================================================

  def test_simple_media_query
    css = %(
      @media print {
        body { margin: 0 }
      }
    )

    @sheet.add_block(css)

    assert_equal 1, @sheet.size

    # Should have media type :print
    assert_matches_media :print, @sheet
    assert_has_selector 'body', @sheet, media: :print, count: 1

    body_rule = @sheet.find_by_selector('body', media: :print).first

    assert_has_property({ margin: '0' }, body_rule)

    # Should not match :screen
    assert_no_selector_matches 'body', @sheet, media: :screen
  end

  def test_multiple_media_types
    css = %(
      @media screen, print {
        .header { color: black }
      }
    )

    @sheet.add_block(css)

    # Should match both media types
    assert_matches_media :screen, @sheet
    assert_matches_media :print, @sheet
    assert_has_selector '.header', @sheet, media: :screen, count: 1
    assert_has_selector '.header', @sheet, media: :print, count: 1
  end

  def test_media_query_with_feature
    css = %{
      @media screen and (min-width: 768px) {
        .container { width: 750px }
      }
    }

    @sheet.add_block(css)

    # Check it parses and applies to screen
    assert_equal 1, @sheet.size

    container_rules = @sheet.find_by_selector('.container', media: :screen)

    assert_equal 1, container_rules.length
    assert_equal '.container', container_rules[0].selector
    assert_equal 'width', container_rules[0].declarations[0].property
    assert_equal '750px', container_rules[0].declarations[0].value
  end

  def test_mixed_media_and_non_media_rules
    css = %(
      body { margin: 10px }

      @media print {
        body { margin: 0 }
      }

      .header { color: blue }
    )

    @sheet.add_block(css)

    assert_equal 3, @sheet.size

    # :all matches ALL rules regardless of media type
    all_body_rules = @sheet.find_by_selector('body', media: :all)

    assert_equal 2, all_body_rules.length
    assert_equal 'body', all_body_rules[0].selector
    assert_equal 'body', all_body_rules[1].selector

    header_rules = @sheet.find_by_selector('.header', media: :all)

    assert_equal 1, header_rules.length
    assert_equal '.header', header_rules[0].selector

    # Media-specific query returns ONLY media-specific rules (matches css_parser)
    print_body_rules = @sheet.find_by_selector('body', media: :print)

    assert_equal 1, print_body_rules.length
    assert_equal 'body', print_body_rules[0].selector
  end

  # ============================================================================
  # Combinators (CSS2)
  # ============================================================================

  def test_descendant_combinator
    css = 'div p { color: red }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.size
    assert_has_selector 'div p', @sheet
  end

  def test_child_combinator
    css = 'div > p { color: blue }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.size
    assert_has_selector 'div > p', @sheet

    # Specificity: element + element = 2
    assert_specificity 2, 'div > p'
  end

  def test_adjacent_sibling_combinator
    css = 'h1 + p { margin-top: 0 }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.size
    assert_has_selector 'h1 + p', @sheet
  end

  def test_complex_selector_with_combinators
    css = 'div.container > p.intro { font-weight: bold }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.size
    # Specificity: div(1) + .container(10) + p(1) + .intro(10) = 22
    assert_specificity 22, 'div.container > p.intro'
  end

  # ============================================================================
  # Pseudo-classes (CSS2)
  # ============================================================================

  def test_hover_pseudo_class
    css = 'a:hover { color: red }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.size
    assert_has_selector 'a:hover', @sheet

    # Pseudo-class counts as class selector: element(1) + class(10) = 11
    assert_specificity 11, 'a:hover'
  end

  def test_focus_pseudo_class
    css = 'input:focus { border-color: blue }'
    @sheet.add_block(css)

    assert_has_selector 'input:focus', @sheet
  end

  def test_first_child_pseudo_class
    css = 'p:first-child { margin-top: 0 }'
    @sheet.add_block(css)

    assert_has_selector 'p:first-child', @sheet
  end

  def test_link_visited_pseudo_classes
    css = %(
      a:link { color: blue }
      a:visited { color: purple }
    )

    @sheet.add_block(css)

    assert_equal 2, @sheet.size
    assert_has_selector 'a:link', @sheet
    assert_has_selector 'a:visited', @sheet
  end

  # ============================================================================
  # Pseudo-elements (CSS2)
  # ============================================================================

  def test_before_pseudo_element
    css = "p::before { content: '>' }"
    @sheet.add_block(css)

    assert_has_selector 'p::before', @sheet

    # Pseudo-element counts as element: element(1) + element(1) = 2
    assert_specificity 2, 'p::before'
  end

  def test_after_pseudo_element
    css = "p::after { content: '<' }"
    @sheet.add_block(css)

    assert_has_selector 'p::after', @sheet
  end

  def test_first_line_pseudo_element
    css = 'p::first-line { font-weight: bold }'
    @sheet.add_block(css)

    assert_has_selector 'p::first-line', @sheet
  end

  # ============================================================================
  # Advanced Attribute Selectors (CSS2)
  # ============================================================================

  def test_attribute_word_match
    # ~= matches one word in space-separated list
    css = '[class~="button"] { padding: 10px }'
    @sheet.add_block(css)

    assert_has_selector '[class~="button"]', @sheet
  end

  def test_attribute_dash_match
    # |= matches value or value followed by hyphen
    css = '[lang|="en"] { quotes: "\\"" "\\"" }'
    @sheet.add_block(css)

    assert_has_selector '[lang|="en"]', @sheet
  end

  # ============================================================================
  # Universal Selector (CSS2)
  # ============================================================================

  def test_universal_selector
    css = '* { margin: 0; padding: 0 }'
    @sheet.add_block(css)

    assert_has_selector '*', @sheet

    # Universal selector has specificity 0
    assert_specificity 0, '*'
  end

  def test_universal_with_namespace
    css = 'div * { border: none }'
    @sheet.add_block(css)

    # Should parse as descendant combinator with universal
    assert_has_selector 'div *', @sheet
  end

  # ============================================================================
  # !important flag (CSS2 - Already works but test for completeness)
  # ============================================================================

  def test_important_flag_already_working
    css = '.priority { color: red !important }'
    @sheet.add_block(css)

    # This should already work based on Declarations class
    rule = @sheet.rules.first
    decls = Cataract::Declarations.new(rule.declarations)

    assert decls.important?('color')
    assert_equal 'color: red !important;', decls.to_s
  end

  # ============================================================================
  # Edge Cases and Complex Scenarios
  # ============================================================================

  def test_multiple_selectors_with_combinators
    css = 'div p, article > h1, nav + aside { display: block }'
    @sheet.add_block(css)

    # Should create 3 separate rules
    assert_equal 3, @sheet.size
    assert_has_selector 'div p', @sheet
    assert_has_selector 'article > h1', @sheet
    assert_has_selector 'nav + aside', @sheet
  end

  def test_selector_with_everything
    # Complex selector combining multiple CSS2 features
    css = 'div.container > ul#nav li:first-child a[href^="http"]:hover { color: orange }'
    @sheet.add_block(css)

    assert_equal 1, @sheet.size
    # This is a very specific selector - specificity should be high
  end
end
