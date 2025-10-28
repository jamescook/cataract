require "minitest/autorun"
require "cataract"

# Tests for CSS2 features that are not yet implemented
# These tests are expected to fail until the features are added
class TestCSS2Features < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
  end

  # ============================================================================
  # @media Rules (CSS2 - Critical)
  # ============================================================================

  def test_simple_media_query
    css = %{
      @media print {
        body { margin: 0 }
      }
    }

    @parser.parse(css)

    assert_equal 1, @parser.rules_count

    # Should have media type :print
    body_rules = @parser.find_by_selector("body", :print)
    assert_equal ["margin: 0;"], body_rules

    # Should not match :screen
    screen_rules = @parser.find_by_selector("body", :screen)
    assert_equal [], screen_rules
  end

  def test_multiple_media_types
    css = %{
      @media screen, print {
        .header { color: black }
      }
    }

    @parser.parse(css)

    # Should match both media types
    assert_equal ["color: black;"], @parser.find_by_selector(".header", :screen)
    assert_equal ["color: black;"], @parser.find_by_selector(".header", :print)
  end

  def test_media_query_with_feature
    css = %{
      @media screen and (min-width: 768px) {
        .container { width: 750px }
      }
    }

    @parser.parse(css)

    # For now, just check it parses and applies to screen
    assert_equal 1, @parser.rules_count
    assert_includes @parser.find_by_selector(".container", :screen), "width: 750px;"
  end

  def test_mixed_media_and_non_media_rules
    css = %{
      body { margin: 10px }

      @media print {
        body { margin: 0 }
      }

      .header { color: blue }
    }

    @parser.parse(css)

    assert_equal 3, @parser.rules_count

    # :all matches ALL rules regardless of media type
    assert_equal ["margin: 10px;", "margin: 0;"], @parser.find_by_selector("body", :all)
    assert_equal ["color: blue;"], @parser.find_by_selector(".header", :all)

    # Media-specific query returns ONLY media-specific rules (matches css_parser)
    assert_equal ["margin: 0;"], @parser.find_by_selector("body", :print)
  end

  # ============================================================================
  # Combinators (CSS2)
  # ============================================================================

  def test_descendant_combinator
    css = "div p { color: red }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "div p"
  end

  def test_child_combinator
    css = "div > p { color: blue }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "div > p"

    # Specificity: element + element = 2
    @parser.each_selector do |selector, declarations, specificity|
      assert_equal 2, specificity if selector == "div > p"
    end
  end

  def test_adjacent_sibling_combinator
    css = "h1 + p { margin-top: 0 }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "h1 + p"
  end

  def test_complex_selector_with_combinators
    css = "div.container > p.intro { font-weight: bold }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    # Specificity: div(1) + .container(10) + p(1) + .intro(10) = 22
    @parser.each_selector do |selector, declarations, specificity|
      assert_equal 22, specificity
    end
  end

  # ============================================================================
  # Pseudo-classes (CSS2)
  # ============================================================================

  def test_hover_pseudo_class
    css = "a:hover { color: red }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "a:hover"

    # Pseudo-class counts as class selector: element(1) + class(10) = 11
    @parser.each_selector do |selector, declarations, specificity|
      assert_equal 11, specificity if selector == "a:hover"
    end
  end

  def test_focus_pseudo_class
    css = "input:focus { border-color: blue }"
    @parser.parse(css)

    assert_includes @parser.selectors, "input:focus"
  end

  def test_first_child_pseudo_class
    css = "p:first-child { margin-top: 0 }"
    @parser.parse(css)

    assert_includes @parser.selectors, "p:first-child"
  end

  def test_link_visited_pseudo_classes
    css = %{
      a:link { color: blue }
      a:visited { color: purple }
    }

    @parser.parse(css)

    assert_equal 2, @parser.rules_count
    assert_includes @parser.selectors, "a:link"
    assert_includes @parser.selectors, "a:visited"
  end

  # ============================================================================
  # Pseudo-elements (CSS2)
  # ============================================================================

  def test_before_pseudo_element
    css = "p::before { content: '>' }"
    @parser.parse(css)

    assert_includes @parser.selectors, "p::before"

    # Pseudo-element counts as element: element(1) + element(1) = 2
    @parser.each_selector do |selector, declarations, specificity|
      assert_equal 2, specificity if selector == "p::before"
    end
  end

  def test_after_pseudo_element
    css = "p::after { content: '<' }"
    @parser.parse(css)

    assert_includes @parser.selectors, "p::after"
  end

  def test_first_line_pseudo_element
    css = "p::first-line { font-weight: bold }"
    @parser.parse(css)

    assert_includes @parser.selectors, "p::first-line"
  end

  # ============================================================================
  # Advanced Attribute Selectors (CSS2)
  # ============================================================================

  def test_attribute_word_match
    # ~= matches one word in space-separated list
    css = '[class~="button"] { padding: 10px }'
    @parser.parse(css)

    assert_includes @parser.selectors, '[class~="button"]'
  end

  def test_attribute_dash_match
    # |= matches value or value followed by hyphen
    css = '[lang|="en"] { quotes: "\\"" "\\"" }'
    @parser.parse(css)

    assert_includes @parser.selectors, '[lang|="en"]'
  end

  # ============================================================================
  # Universal Selector (CSS2)
  # ============================================================================

  def test_universal_selector
    css = "* { margin: 0; padding: 0 }"
    @parser.parse(css)

    assert_includes @parser.selectors, "*"

    # Universal selector has specificity 0
    @parser.each_selector do |selector, declarations, specificity|
      assert_equal 0, specificity if selector == "*"
    end
  end

  def test_universal_with_namespace
    css = "div * { border: none }"
    @parser.parse(css)

    # Should parse as descendant combinator with universal
    assert_includes @parser.selectors, "div *"
  end

  # ============================================================================
  # !important flag (CSS2 - Already works but test for completeness)
  # ============================================================================

  def test_important_flag_already_working
    css = ".priority { color: red !important }"
    @parser.parse(css)

    # This should already work based on Declarations class
    rule = @parser.rules.first
    decls = Cataract::Declarations.new(rule.declarations)
    assert decls.important?("color")
    assert_equal "color: red !important;", decls.to_s
  end

  # ============================================================================
  # Edge Cases and Complex Scenarios
  # ============================================================================

  def test_multiple_selectors_with_combinators
    css = "div p, article > h1, nav + aside { display: block }"
    @parser.parse(css)

    # Should create 3 separate rules
    assert_equal 3, @parser.rules_count
    assert_includes @parser.selectors, "div p"
    assert_includes @parser.selectors, "article > h1"
    assert_includes @parser.selectors, "nav + aside"
  end

  def test_selector_with_everything
    # Complex selector combining multiple CSS2 features
    css = 'div.container > ul#nav li:first-child a[href^="http"]:hover { color: orange }'
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    # This is a very specific selector - specificity should be high
  end
end
