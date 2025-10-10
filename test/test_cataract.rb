require "minitest/autorun"
require "cataract"

class TestCataract < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
  end

  def test_simple_selector
    css = ".header { color: blue }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, ".header"
  end

  def test_multiple_rules
    css = %{
      .header { color: blue }
      #nav { font-size: large }
      body { margin: zero }
    }

    @parser.parse(css)

    assert_equal 3, @parser.rules_count
    assert_includes @parser.selectors, ".header"
    assert_includes @parser.selectors, "#nav"
    assert_includes @parser.selectors, "body"
  end

  def test_each_selector
    css = ".test { color: red }"
    @parser.parse(css)

    selectors = []
    @parser.each_selector do |selector, declarations, specificity|
      selectors << selector
      assert_equal "color: red;", declarations
      assert_equal 10, specificity # class selector = 10
    end

    assert_equal [".test"], selectors
  end

  def test_find_by_selector
    css = %{
      .header { color: blue }
      .footer { color: green }
    }

    @parser.parse(css)

    header_rules = @parser.find_by_selector(".header")
    assert_equal ["color: blue;"], header_rules

    missing_rules = @parser.find_by_selector(".nonexistent")
    assert_equal [], missing_rules
  end

  def test_comments_ignored
    css = %{
      /* Header styles */
      .header { color: blue }
      /* Footer styles */
    }

    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, ".header"
  end

  def test_multiple_declarations
    css = ".multi { color: red; background: blue; margin: 10px }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count

    @parser.each_selector do |selector, declarations, specificity|
      assert_equal ".multi", selector
      assert_includes declarations, "color: red;"
      assert_includes declarations, "background: blue;"
      assert_includes declarations, "margin: 10px;"
    end
  end

  def test_selector_lists
    css = ".header, .footer, #nav { color: blue }"
    @parser.parse(css)

    # Should create 3 separate rules
    assert_equal 3, @parser.rules_count

    selectors = @parser.selectors
    assert_includes selectors, ".header"
    assert_includes selectors, ".footer"
    assert_includes selectors, "#nav"

    # Each should have the same declarations
    [".header", ".footer", "#nav"].each do |selector|
      rules = @parser.find_by_selector(selector)
      assert_equal ["color: blue;"], rules
    end
  end

  def test_selector_lists_with_multiple_declarations
    css = ".btn, .button { color: white; background: blue; padding: 10px }"
    @parser.parse(css)

    # Should create 2 separate rules
    assert_equal 2, @parser.rules_count

    [".btn", ".button"].each do |selector|
      rules = @parser.find_by_selector(selector).first
      assert_includes rules, "color: white;"
      assert_includes rules, "background: blue;"
      assert_includes rules, "padding: 10px;"
    end
  end

  def test_hyphenated_identifiers
    css = ".main-header { background-color: white }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, ".main-header"

    @parser.each_selector do |selector, declarations, specificity|
      assert_equal "background-color: white;", declarations
    end
  end

  def test_specificity_calculation
    css = %{
      body { margin: zero }
      .class { color: blue }
      #id { font-size: large }
    }

    @parser.parse(css)

    specificities = {}
    @parser.each_selector do |selector, declarations, specificity|
      specificities[selector] = specificity
    end

    assert_equal 1, specificities["body"]     # element = 1
    assert_equal 10, specificities[".class"]  # class = 10
    assert_equal 100, specificities["#id"]    # id = 100
  end

  def test_to_s_regeneration
    css = ".header { color: blue }"
    @parser.parse(css)

    output = @parser.to_s
    assert_includes output, ".header"
    assert_includes output, "color: blue"
    assert_includes output, "{"
    assert_includes output, "}"
  end

  # Attribute selector tests
  def test_attribute_exists_selector
    css = "[disabled] { opacity: 0.5 }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "[disabled]"

    @parser.each_selector do |selector, declarations, specificity|
      assert_equal "[disabled]", selector
      assert_equal "opacity: 0.5;", declarations
      assert_equal 10, specificity # attribute selector = 10
    end
  end

  def test_hyphenated_attribute_selector
    css = "[data-toggle] { cursor: pointer }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "[data-toggle]"
  end

  def test_mixed_attribute_and_other_selectors
    css = %{
      .btn { color: black }
      [disabled] { opacity: 0.5 }
      input { background: green }
    }

    @parser.parse(css)

    assert_equal 3, @parser.rules_count
    assert_includes @parser.selectors, ".btn"
    assert_includes @parser.selectors, "[disabled]"
    assert_includes @parser.selectors, "input"
  end

  def test_attribute_selector_list
    css = "[required], [disabled] { border: 2px solid red }"
    @parser.parse(css)

    # Should create 2 separate rules
    assert_equal 2, @parser.rules_count

    selectors = @parser.selectors
    assert_includes selectors, "[required]"
    assert_includes selectors, "[disabled]"

    # Each should have the same declarations
    ["[required]", "[disabled]"].each do |selector|
      rules = @parser.find_by_selector(selector)
      assert_equal ["border: 2px solid red;"], rules
    end
  end

  def test_attribute_selector_specificity
    css = %{
      input { color: black }
      [type] { color: blue }
      #special { color: red }
    }

    @parser.parse(css)

    specificities = {}
    @parser.each_selector do |selector, declarations, specificity|
      specificities[selector] = specificity
    end

    assert_equal 1, specificities["input"]     # element = 1
    assert_equal 10, specificities["[type]"]   # attribute = 10
    assert_equal 100, specificities["#special"] # id = 100
  end

  def test_attribute_equals_unquoted_value
    css = "[type=submit] { background: blue }"
    @parser.parse(css)

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "[type=submit]"

    @parser.each_selector do |selector, declarations, specificity|
      assert_equal "[type=submit]", selector
      assert_equal "background: blue;", declarations
      assert_equal 10, specificity # attribute selector = 10
    end
  end

  def test_attribute_equals_double_quoted_value
    css = '[data-role="button"] { padding: 10px }'
    @parser.parse(css)
    
    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, '[data-role="button"]'
    
    rules = @parser.find_by_selector('[data-role="button"]')
    assert_equal ["padding: 10px;"], rules
  end

  def test_attribute_equals_single_quoted_value
    css = "[title='Main Menu'] { font-weight: bold }"
    @parser.parse(css)
    
    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "[title='Main Menu']"
  end

  def test_attribute_with_hyphenated_values
    css = "[data-toggle=dropdown] { cursor: pointer }"
    @parser.parse(css)
    
    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "[data-toggle=dropdown]"
  end

  def test_attribute_value_with_spaces_in_quotes
    css = '[alt="Click here to continue"] { border: 1px solid }'
    @parser.parse(css)
    
    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, '[alt="Click here to continue"]'
  end

  def test_mixed_attribute_syntaxes
    css = %{
      [disabled] { opacity: 0.5 }
      [type=submit] { background: green }
      [data-role="button"] { padding: 8px }
    }
    
    @parser.parse(css)
    
    assert_equal 3, @parser.rules_count
    assert_includes @parser.selectors, "[disabled]"
    assert_includes @parser.selectors, "[type=submit]"
    assert_includes @parser.selectors, '[data-role="button"]'
  end

  def test_attribute_value_selector_lists
    css = "[required], [type=email] { border: 2px solid red }"
    @parser.parse(css)
    
    # Should create 2 separate rules
    assert_equal 2, @parser.rules_count
    
    selectors = @parser.selectors
    assert_includes selectors, "[required]"
    assert_includes selectors, "[type=email]"
    
    # Each should have the same declarations
    ["[required]", "[type=email]"].each do |selector|
      rules = @parser.find_by_selector(selector)
      assert_equal ["border: 2px solid red;"], rules
    end
  end

  def test_attribute_value_specificity
    css = %{
      input { color: black }
      [type] { color: blue }
      [type=text] { color: green }
      #special { color: red }
    }

    @parser.parse(css)

    specificities = {}
    @parser.each_selector do |selector, declarations, specificity|
      specificities[selector] = specificity
    end

    assert_equal 1, specificities["input"]      # element = 1
    assert_equal 10, specificities["[type]"]    # attribute = 10
    assert_equal 10, specificities["[type=text]"] # attribute with value = 10
    assert_equal 100, specificities["#special"] # id = 100
  end

  def test_edge_cases
    # Test various edge cases for attribute values
    css = %{
      [data-value=""] { color: red }
      [data-number="123"] { font-size: large }
      [data-mixed="abc-123"] { text-decoration: underline }
    }
    
    @parser.parse(css)
    
    assert_equal 3, @parser.rules_count
    assert_includes @parser.selectors, '[data-value=""]'
    assert_includes @parser.selectors, '[data-number="123"]'
    assert_includes @parser.selectors, '[data-mixed="abc-123"]'
  end
end
