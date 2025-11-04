# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

class TestParser < Minitest::Test
  def test_parser_with_rich_objects
    sheet = Cataract::Stylesheet.new
    css = %(
      .header { color: blue; font-size: large }
      #nav { background: red !important }
      [disabled] { opacity: 0.5 }
    )

    sheet.parse(css)

    # Test lazy loading
    assert_equal 3, sheet.rules_count

    # Test rules are Rule structs (internal representation)
    rules = sheet.rules

    assert(rules.all?(Cataract::Rule))

    # Test individual rules
    header_rule = rules.find { |r| r.selector == '.header' }

    assert_equal 'blue', header_rule.property('color')
    assert_equal 'large', header_rule.property('font-size')

    nav_rule = rules.find { |r| r.selector == '#nav' }

    assert_equal 'red !important', nav_rule.property('background')
    assert Cataract::Declarations.new(nav_rule.declarations).important?('background')
  end

  def test_parser_add_rule
    sheet = Cataract::Stylesheet.new
    sheet.parse('.existing { color: blue }')

    # Add a new rule
    new_rule = sheet.add_rule!(
      selector: '.new',
      declarations: { 'color' => 'red', 'margin' => '10px !important' }
    )

    assert_equal 2, sheet.rules_count
    assert_equal '.new', new_rule.selector
    assert_equal 'red', new_rule.property('color')
    assert new_rule.declarations.important?('margin')

    # Verify it's in the rules
    new_rule_found = sheet.rules.find { |r| r.selector == '.new' }

    assert new_rule_found
    assert_equal 'red', new_rule_found.property('color')
  end

  def test_parser_find_by_selector
    sheet = Cataract::Stylesheet.new
    sheet.parse(%(
      .header { color: blue }
      .footer { color: green }
      .header { background: red }
    ))

    # Should find both .header rules
    header_rules = sheet.find_by_selector('.header')

    assert_equal 2, header_rules.length
    assert_includes header_rules, 'color: blue;'
    assert_includes header_rules, 'background: red;'
  end

  def test_parser_css_regeneration
    original_css = %(
      .header { color: blue; font-size: large }
      #nav { background: red }
    ).strip

    sheet = Cataract::Stylesheet.new
    sheet.parse(original_css)

    regenerated = sheet.to_css

    # Should contain the essential parts (order might differ)
    assert_includes regenerated, '.header { color: blue; font-size: large; }'
    assert_includes regenerated, '#nav { background: red; }'
  end

  def test_backward_compatibility
    sheet = Cataract::Stylesheet.new
    sheet.parse('.test { color: red }')

    # Old API should still work
    selectors = []
    sheet.each_selector do |selector, declarations, specificity|
      selectors << [selector, declarations, specificity]
    end

    assert_equal 1, selectors.length
    assert_equal '.test', selectors[0][0]
    assert_equal 'color: red;', selectors[0][1]
    assert_equal 10, selectors[0][2]
  end
end
