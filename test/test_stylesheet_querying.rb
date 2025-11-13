require_relative 'test_helper'

class TestStylesheetQuerying < Minitest::Test
  def test_for_media_filter
    css = <<~CSS
      body { color: black; }
      @media screen { h1 { color: red; } }
      @media print { h2 { color: blue; } }
      @media screen { p { color: green; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    assert_matches_media :screen, sheet
    assert_matches_media :print, sheet

    screen_rules = sheet.with_media(:screen)

    assert_equal 2, screen_rules.length
    assert_equal %w[h1 p], screen_rules.map(&:selector)
  end

  def test_base_rules_filter
    css = <<~CSS
      body { color: black; }
      @media screen { h1 { color: red; } }
      div { margin: 0; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    base_rules = sheet.base_rules

    assert_equal 2, base_rules.length
    assert_equal %w[body div], base_rules.map(&:selector)
  end

  def test_media_queries_list
    css = <<~CSS
      body { color: black; }
      @media screen { h1 { color: red; } }
      @media print { h2 { color: blue; } }
      @media screen { p { color: green; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    media_queries = sheet.media_queries

    assert_equal 2, media_queries.length
    assert_member media_queries, :screen
    assert_member media_queries, :print
  end

  def test_each_selector_basic
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal %w[body div], sheet.selectors
  end

  def test_nested_media_each_selector
    css = <<~CSS
      @media screen {
        @media (min-width: 500px) {
          .nested { color: red; }
        }
      }
      .normal { color: blue; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should have 2 rules total
    assert_equal 2, sheet.size

    # Query with combined media should return nested rule
    combined_media = :'screen and (min-width: 500px)'

    assert_matches_media combined_media, sheet
    assert_selectors_match ['.nested'], sheet, media: combined_media

    # Query with just :screen should return nested rule (it's in screen index too)
    assert_matches_media :screen, sheet
    assert_selectors_match ['.nested'], sheet, media: :screen

    # Query with :all should return both rules
    assert_selectors_match ['.nested', '.normal'], sheet, media: :all
  end

  def test_finding_by_selector
    css = <<-CSS
      html, body, p { margin: 0px; }
      p { padding: 0px; }
      #content { font: 12px/normal sans-serif; }
      .content { color: red; }
    CSS

    stylesheet = Cataract::Stylesheet.parse(css)

    # find_by_selector returns array of Rule objects
    body_rules = stylesheet.with_selector('body')

    assert_equal 1, body_rules.size
    assert_kind_of Cataract::Rule, body_rules[0]
    assert_equal 'body', body_rules[0].selector

    # Can access declarations from the rule
    assert_equal 1, body_rules[0].declarations.length
  end

  def test_selectors_all
    css = 'body { color: red; } .header { padding: 5px; } #main { font-size: 14px; }'
    sheet = Cataract::Stylesheet.parse(css)
    sels = sheet.selectors

    assert_equal 3, sels.length
    assert_member sels, 'body'
    assert_member sels, '.header'
    assert_member sels, '#main'
  end
end
