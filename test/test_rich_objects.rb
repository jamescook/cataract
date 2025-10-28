require "minitest/autorun"
require "cataract"

class TestParser < Minitest::Test
  def test_parser_with_rich_objects
    parser = Cataract::Parser.new
    css = %{
      .header { color: blue; font-size: large }
      #nav { background: red !important }
      [disabled] { opacity: 0.5 }
    }
    
    parser.parse(css)
    
    # Test lazy loading
    assert_equal 3, parser.rules_count

    # Test rules are Rule structs (internal representation)
    rules = parser.rules
    assert rules.all? { |rule| rule.is_a?(Cataract::Rule) }
    
    # Test individual rules
    header_rule = rules.find { |r| r.selector == ".header" }
    assert_equal "blue;", header_rule["color"]
    assert_equal "large;", header_rule["font-size"]
    
    nav_rule = rules.find { |r| r.selector == "#nav" }
    assert_equal "red !important;", nav_rule["background"]
    assert Cataract::Declarations.new(nav_rule.declarations).important?("background")
  end
  
  def test_parser_add_rule
    parser = Cataract::Parser.new
    parser.parse(".existing { color: blue }")
    
    # Add a new rule
    new_rule = parser.add_rule!(
      selector: ".new",
      declarations: {"color" => "red", "margin" => "10px !important"}
    )
    
    assert_equal 2, parser.rules_count
    assert_equal ".new", new_rule.selector
    assert_equal "red;", new_rule["color"]
    assert new_rule.declarations.important?("margin")
    
    # Verify it's in the rules
    new_rule_found = parser.rules.find { |r| r.selector == ".new" }
    assert new_rule_found
    assert_equal "red;", new_rule_found["color"]
  end
  
  def test_parser_find_by_selector
    parser = Cataract::Parser.new
    parser.parse(%{
      .header { color: blue }
      .footer { color: green }
      .header { background: red }
    })
    
    # Should find both .header rules
    header_rules = parser.find_by_selector(".header")
    assert_equal 2, header_rules.length
    assert_includes header_rules, "color: blue;"
    assert_includes header_rules, "background: red;"
  end
  
  def test_parser_css_regeneration
    original_css = %{
      .header { color: blue; font-size: large }
      #nav { background: red }
    }.strip
    
    parser = Cataract::Parser.new
    parser.parse(original_css)
    
    regenerated = parser.to_css
    
    # Should contain the essential parts (order might differ)
    assert_includes regenerated, ".header { color: blue; font-size: large; }"
    assert_includes regenerated, "#nav { background: red; }"
  end
  
  def test_backward_compatibility
    parser = Cataract::Parser.new
    parser.parse(".test { color: red }")
    
    # Old API should still work
    selectors = []
    parser.each_selector do |selector, declarations, specificity|
      selectors << [selector, declarations, specificity]
    end
    
    assert_equal 1, selectors.length
    assert_equal ".test", selectors[0][0]
    assert_equal "color: red;", selectors[0][1]
    assert_equal 10, selectors[0][2]
  end
end
