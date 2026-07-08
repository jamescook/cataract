# frozen_string_literal: true

require_relative 'test_helper'

# Conformance test between the C extension and pure Ruby backends.
#
# This file doesn't compare the two backends directly - it can't, since only
# one is active per test run. Instead it relies on the dual-pass test
# infrastructure: `rake test:c` and `rake test:pure` each run this entire
# file against one backend per process. As long as the assertions
# below are exact (not "at least contains"), a real divergence between
# backends shows up as this file passing under one backend's run and
# failing under the other's - without ever needing to know which backend
# it's currently running under.
#
# The fixture (test/fixtures/conformance.css) intentionally only uses
# constructs already proven supported elsewhere in the test suite (nesting,
# media queries, !important, custom properties, shorthand/longhand,
# keyframes, font-face, an unknown at-rule, url()) - the goal is catching
# backend drift on already-supported CSS, not exploring the edges of CSS
# spec compliance. Gaps found here should be filed as their own issues
# rather than expanded into this fixture.
class TestBackendConformance < Minitest::Test
  def setup
    @css = File.read(File.join(__dir__, 'fixtures', 'conformance.css'))
    @sheet = Cataract::Stylesheet.parse(@css)
  end

  # Canonicalize a Stylesheet's rules into plain, comparable data - selector
  # text, specificity, resolved media (type/conditions, not the raw
  # media_query_id, which is an implementation detail), the parent rule's
  # selector (not the raw parent_rule_id, for the same reason), and
  # declarations as [property, value, important] triples.
  def canonical_rules(sheet)
    sheet.rules.map do |rule|
      next { at_rule: rule.selector } if rule.is_a?(Cataract::AtRule)

      mq = rule.media_query_id ? sheet.media_queries[rule.media_query_id] : nil
      parent = rule.parent_rule_id ? sheet.rules[rule.parent_rule_id].selector : nil

      {
        selector: rule.selector,
        specificity: rule.specificity,
        media: mq ? [mq.type, mq.conditions] : nil,
        parent_selector: parent,
        declarations: rule.declarations.map { |d| [d.property, d.value, d.important] }
      }
    end
  end

  def test_parse_produces_expected_rule_structure
    expected = [
      { selector: 'body', specificity: 1, media: nil, parent_selector: nil,
        declarations: [%w[margin 0], %w[padding 0]].map { |p, v| [p, v, false] } },
      { selector: 'html', specificity: 1, media: nil, parent_selector: nil,
        declarations: [%w[margin 0], %w[padding 0]].map { |p, v| [p, v, false] } },
      { selector: '.container', specificity: 10, media: nil, parent_selector: nil,
        declarations: [
          ['--spacing', '16px', false],
          ['--primary-color', '#336699', false],
          ['max-width', '1200px', false],
          ['margin', '0 auto', false],
          ['padding', 'var(--spacing)', false]
        ] },
      { selector: '.container > .row', specificity: 20, media: nil, parent_selector: nil,
        declarations: [['display', 'flex', false]] },
      { selector: '.container + .footer', specificity: 20, media: nil, parent_selector: nil,
        declarations: [['margin-top', '2rem', false]] },
      { selector: '.container ~ .sibling', specificity: 20, media: nil, parent_selector: nil,
        declarations: [['color', 'gray', false]] },
      { selector: '.box', specificity: 10, media: nil, parent_selector: nil,
        declarations: [
          ['margin-top', '10px', false],
          ['margin-right', '10px', false],
          ['margin-bottom', '10px', false],
          ['margin-left', '10px', false],
          ['color', 'red', false]
        ] },
      { selector: '.box', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['color', 'blue', false]] },
      { selector: '#special.box', specificity: 110, media: nil, parent_selector: nil,
        declarations: [['color', 'green', false]] },
      { selector: '.override', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['color', 'red', true]] },
      { selector: '.override', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['color', 'blue', false]] },
      { selector: '.card', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['background', 'white', false], ['border', '1px solid #ddd', false]] },
      { selector: '.card .card-header', specificity: 20, media: nil, parent_selector: '.card',
        declarations: [['padding', '1rem', false]] },
      { selector: '.card .card-header.highlighted', specificity: 30, media: nil,
        parent_selector: '.card .card-header', declarations: [['background', '#f0f0f0', false]] },
      { selector: '.card:hover', specificity: 20, media: nil, parent_selector: '.card',
        declarations: [['box-shadow', '0 0 4px rgba(0, 0, 0, 0.2)', false]] },
      { selector: '.card .card-body', specificity: 20, media: nil, parent_selector: '.card',
        declarations: [] },
      { selector: '.card .card-body .card-title', specificity: 30, media: nil,
        parent_selector: '.card .card-body', declarations: [['font-size', '1.25rem', false]] },
      { selector: '.urgent', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['color', 'red', true]] },
      { selector: '.urgent-commented', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['color', 'green /* keep this */', true]] },
      { selector: '.visible-screen', specificity: 10, media: [:screen, nil], parent_selector: nil,
        declarations: [['display', 'block', false]] },
      { selector: '.visible-print', specificity: 10, media: [:print, nil], parent_selector: nil,
        declarations: [['display', 'block', false]] },
      { selector: '.responsive', specificity: 10, media: [:screen, '(min-width: 768px)'], parent_selector: nil,
        declarations: [['width', '750px', false]] },
      { selector: '.universal', specificity: 10, media: [:screen, nil], parent_selector: nil,
        declarations: [['color', 'black', false]] },
      { selector: '.widget', specificity: 10, media: nil, parent_selector: nil,
        declarations: [['padding', '1rem', false]] },
      { selector: '.widget', specificity: 10, media: [:all, '(min-width: 1024px)'], parent_selector: '.widget',
        declarations: [['padding', '2rem', false]] },
      { at_rule: '@keyframes fade-in' },
      { at_rule: '@font-face' },
      { selector: '@page', specificity: 1, media: nil, parent_selector: nil,
        declarations: [['margin', '1in', false]] },
      { selector: '.background', specificity: 10, media: nil, parent_selector: nil,
        declarations: [
          ['background-image', 'url("images/bg.png")', false],
          ['content', '"hello world"', false]
        ] }
    ]

    assert_equal expected, canonical_rules(@sheet)
  end

  def test_parse_produces_expected_media_queries
    expected = [
      %i[screen], # :screen, conditions: nil
      %i[print],
      [:screen, '(min-width: 768px)'],
      %i[screen],
      %i[print], # combined query 'screen, print' creates two MediaQuery entries
      [:all, '(min-width: 1024px)']
    ]

    actual = @sheet.media_queries.map { |mq| mq.conditions ? [mq.type, mq.conditions] : [mq.type] }

    assert_equal expected, actual
  end

  def test_flatten_produces_expected_cascade_result
    flattened = @sheet.flatten
    canonical = canonical_rules(flattened).reject { |r| r[:at_rule] }

    # Spot-check the cascade-sensitive rules rather than the whole structure -
    # shorthand recreation and cascade order are the parts that would
    # actually diverge between backends.
    box = canonical.find { |r| r[:selector] == '.box' }
    override = canonical.find { |r| r[:selector] == '.override' }
    card = canonical.find { |r| r[:selector] == '.card' }
    widgets = canonical.select { |r| r[:selector] == '.widget' }

    # Later non-important declaration wins over earlier non-important at the
    # same specificity; margin longhand properties recombine into shorthand
    assert_equal [%w[color blue], %w[margin 10px]].map { |p, v| [p, v, false] }, box[:declarations]

    # !important beats a later non-important declaration
    assert_equal [['color', 'red', true]], override[:declarations]

    # Declaration order isn't otherwise disturbed by flattening a single rule
    assert_equal [['border', '1px solid #ddd', false], ['background', 'white', false]],
                 card[:declarations]

    # Media-scoped rules for the same selector don't merge with the base rule
    # or each other - they're conditionally applied, not unconditionally cascaded
    assert_equal 2, widgets.length
  end

  def test_to_s_round_trips_to_identical_structure
    reparsed = Cataract::Stylesheet.parse(@sheet.to_s)

    assert_equal canonical_rules(@sheet), canonical_rules(reparsed)
  end

  def test_to_formatted_s_round_trips_to_identical_structure
    reparsed = Cataract::Stylesheet.parse(@sheet.to_formatted_s)

    assert_equal canonical_rules(@sheet), canonical_rules(reparsed)
  end

  def test_to_s_produces_expected_serialization
    expected = <<~CSS
      @charset "UTF-8";
      body { margin: 0; padding: 0; }
      html { margin: 0; padding: 0; }
      .container { --spacing: 16px; --primary-color: #336699; max-width: 1200px; margin: 0 auto; padding: var(--spacing); }
      .container > .row { display: flex; }
      .container + .footer { margin-top: 2rem; }
      .container ~ .sibling { color: gray; }
      .box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; color: red; }
      .box { color: blue; }
      #special.box { color: green; }
      .override { color: red !important; }
      .override { color: blue; }
      .card { background: white; border: 1px solid #ddd; .card-header { padding: 1rem; &.highlighted { background: #f0f0f0; } } &:hover { box-shadow: 0 0 4px rgba(0, 0, 0, 0.2); } .card-body { .card-title { font-size: 1.25rem; } } }
      .urgent { color: red !important; }
      .urgent-commented { color: green /* keep this */ !important; }
      @media screen {
      .visible-screen { display: block; }
      }
      @media print {
      .visible-print { display: block; }
      }
      @media screen and (min-width: 768px) {
      .responsive { width: 750px; }
      }
      @media screen, print {
      .universal { color: black; }
      }
      .widget { padding: 1rem; @media (min-width: 1024px) { padding: 2rem; } }
      @keyframes fade-in {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      @font-face {
        font-family: "CustomFont"; src: url("custom-font.woff2") format("woff2"); font-weight: 400;
      }
      @page { margin: 1in; }
      .background { background-image: url("images/bg.png"); content: "hello world"; }
    CSS

    assert_equal expected, @sheet.to_s
  end
end
