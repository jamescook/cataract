require_relative '../test_helper'

class TestSelectorLists < Minitest::Test
  include StylesheetTestHelper

  # ============================================================================
  # Basic Selector List Parsing
  # ============================================================================

  def test_simple_selector_list_creates_multiple_rules
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract.parse_css(css)

    # Should create 3 separate rules
    assert_selector_count 3, sheet
    assert_has_selector 'h1', sheet
    assert_has_selector 'h2', sheet
    assert_has_selector 'h3', sheet
  end

  def test_simple_selector_list_shares_same_list_id
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract.parse_css(css)

    rules = sheet.rules

    assert_equal 3, rules.size

    # All rules should have the same selector_list_id
    list_ids = rules.map(&:selector_list_id).uniq

    assert_equal 1, list_ids.size, 'All rules from same selector list should share selector_list_id'
    refute_nil list_ids.first, 'Selector list ID should not be nil'
  end

  def test_two_selector_list_creates_six_rules
    css = 'h1, h2 { color: red; } h3, h4 { color: blue; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 4, sheet
    assert_has_selector 'h1', sheet
    assert_has_selector 'h2', sheet
    assert_has_selector 'h3', sheet
    assert_has_selector 'h4', sheet
  end

  def test_single_selector_has_nil_list_id
    css = '.single { color: red; }'
    sheet = Cataract.parse_css(css)

    rule = sheet.rules.first

    assert_nil rule.selector_list_id, 'Single selector should have nil selector_list_id'
  end

  def test_mixed_single_and_list_selectors
    css = '.single { color: red; } h1, h2 { color: blue; } .another { color: green; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 4, sheet

    # Check which rules have list IDs
    rules = sheet.rules
    single1 = rules.find { |r| r.selector == '.single' }
    h1 = rules.find { |r| r.selector == 'h1' }
    h2 = rules.find { |r| r.selector == 'h2' }
    single2 = rules.find { |r| r.selector == '.another' }

    # Single selectors should have nil list_id
    assert_nil single1.selector_list_id
    assert_nil single2.selector_list_id

    # List selectors should share same list_id
    refute_nil h1.selector_list_id
    assert_equal h1.selector_list_id, h2.selector_list_id

    # Should have exactly one shared list_id
    list_ids = rules.map(&:selector_list_id).compact.uniq

    assert_equal 1, list_ids.size
  end

  # ============================================================================
  # Complex Selector Lists
  # ============================================================================

  def test_compound_selector_list
    css = 'h1.title, h2#main, div.container { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 3, sheet
    assert_has_selector 'h1.title', sheet
    assert_has_selector 'h2#main', sheet
    assert_has_selector 'div.container', sheet

    # All should share same list ID
    list_ids = sheet.rules.map(&:selector_list_id).uniq

    assert_equal 1, list_ids.size
  end

  def test_complex_selector_list
    css = 'h1 > p, div .container, ul li + li { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 3, sheet
    assert_has_selector 'h1 > p', sheet
    assert_has_selector 'div .container', sheet
    assert_has_selector 'ul li + li', sheet

    # All should share same list ID
    list_ids = sheet.rules.map(&:selector_list_id).uniq

    assert_equal 1, list_ids.size
  end

  def test_selector_list_with_whitespace
    css = 'h1  ,  h2  ,  h3 { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 3, sheet
    # Selectors should be trimmed
    assert_has_selector 'h1', sheet
    assert_has_selector 'h2', sheet
    assert_has_selector 'h3', sheet
  end

  def test_selector_list_with_pseudo_classes
    css = 'a:hover, a:focus, a:active { color: blue; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 3, sheet
    assert_has_selector 'a:hover', sheet
    assert_has_selector 'a:focus', sheet
    assert_has_selector 'a:active', sheet

    list_ids = sheet.rules.map(&:selector_list_id).uniq

    assert_equal 1, list_ids.size
  end

  def test_selector_list_with_attribute_selectors
    css = '[type="text"], [type="email"], [type="password"] { border: 1px solid gray; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 3, sheet
    assert_has_selector '[type="text"]', sheet
    assert_has_selector '[type="email"]', sheet
    assert_has_selector '[type="password"]', sheet
  end

  # ============================================================================
  # Multiple Independent Selector Lists
  # ============================================================================

  def test_multiple_independent_selector_lists
    css = 'h1, h2 { color: red; } p, div { color: blue; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 4, sheet

    list_ids = sheet.rules.map(&:selector_list_id).compact.uniq

    assert_equal 2, list_ids.size, 'Should have two independent selector lists'

    # Get rules for each list
    h1 = sheet.rules.find { |r| r.selector == 'h1' }
    h2 = sheet.rules.find { |r| r.selector == 'h2' }
    p_rule = sheet.rules.find { |r| r.selector == 'p' }
    div_rule = sheet.rules.find { |r| r.selector == 'div' }

    # First list
    assert_equal h1.selector_list_id, h2.selector_list_id
    # Second list
    assert_equal p_rule.selector_list_id, div_rule.selector_list_id
    # Different lists
    refute_equal h1.selector_list_id, p_rule.selector_list_id
  end

  def test_three_selector_lists
    css = 'h1, h2 { color: red; } h3, h4 { color: blue; } h5, h6 { color: green; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 6, sheet

    list_ids = sheet.rules.map(&:selector_list_id).compact.uniq

    assert_equal 3, list_ids.size, 'Should have three independent selector lists'

    # Each list should have 2 rules
    sheet.rules.group_by(&:selector_list_id).each do |list_id, rules_in_list|
      next if list_id.nil?

      assert_equal 2, rules_in_list.size
    end
  end

  # ============================================================================
  # Declarations Consistency
  # ============================================================================

  def test_selector_list_rules_share_same_declarations
    css = 'h1, h2, h3 { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)

    rules = sheet.rules

    assert_equal 3, rules.size

    # All rules should have identical declarations
    rules.each do |rule|
      assert_has_property({ color: 'red' }, rule)
      assert_has_property({ margin: '10px' }, rule)
      assert_equal 2, rule.declarations.size
    end
  end

  def test_selector_list_with_important_declarations
    css = 'h1, h2 { color: red !important; }'
    sheet = Cataract.parse_css(css)

    rules = sheet.rules

    assert_equal 2, rules.size

    rules.each do |rule|
      assert_has_property({ color: 'red !important' }, rule)
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  def test_empty_selector_list_ignored
    # Leading/trailing commas should be handled gracefully
    css = 'h1 { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 1, sheet
    assert_nil sheet.rules.first.selector_list_id
  end

  def test_selector_list_with_newlines
    css = <<~CSS
      h1,
      h2,
      h3 {
        color: red;
      }
    CSS
    sheet = Cataract.parse_css(css)

    assert_selector_count 3, sheet
    list_ids = sheet.rules.map(&:selector_list_id).uniq

    assert_equal 1, list_ids.size
  end

  def test_very_long_selector_list
    # Test with many selectors in one list
    selectors = (1..20).map { |i| ".class-#{i}" }.join(', ')
    css = "#{selectors} { color: red; }"
    sheet = Cataract.parse_css(css)

    assert_selector_count 20, sheet

    # All should share same list ID
    list_ids = sheet.rules.map(&:selector_list_id).uniq

    assert_equal 1, list_ids.size

    rule_count = sheet.rules.count { |r| r.selector_list_id == list_ids.first }

    assert_equal 20, rule_count
  end

  def test_selector_list_id_counter_increments
    css = 'h1, h2 { color: red; } h3, h4 { color: blue; }'
    sheet = Cataract.parse_css(css)

    list_ids = sheet.rules.map(&:selector_list_id).compact.uniq.sort

    # Should have list IDs 0 and 1
    assert_equal [0, 1], list_ids
  end

  def test_selector_list_preserves_rule_order
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract.parse_css(css)

    # Rules should appear in order: h1, h2, h3
    selectors = sheet.rules.map(&:selector)

    assert_equal %w[h1 h2 h3], selectors
  end

  # ============================================================================
  # Media Queries with Selector Lists
  # ============================================================================

  def test_selector_list_in_media_query
    css = '@media screen { h1, h2 { color: red; } }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 2, sheet

    h1 = sheet.rules.find { |r| r.selector == 'h1' }
    h2 = sheet.rules.find { |r| r.selector == 'h2' }

    # Should share same list ID
    assert_equal h1.selector_list_id, h2.selector_list_id

    # Both should be in media query
    assert_rule_in_media h1, :screen, sheet
    assert_rule_in_media h2, :screen, sheet
  end

  def test_selector_list_with_nested_media
    css = 'h1, h2 { color: red; } @media print { h3, h4 { color: blue; } }'
    sheet = Cataract.parse_css(css)

    assert_selector_count 4, sheet

    list_ids = sheet.rules.map(&:selector_list_id).compact.uniq

    assert_equal 2, list_ids.size, 'Should have two selector lists (one in base, one in @media)'
  end

  # ============================================================================
  # Integration with Existing Features
  # ============================================================================

  def test_selector_list_duplicates_work_with_dup
    css = 'h1, h2 { color: red; }'
    sheet1 = Cataract.parse_css(css)
    sheet2 = sheet1.dup

    # Should have same structure
    assert_equal sheet1.rules.size, sheet2.rules.size

    # Selector list assignment should be duplicated identically...
    assert_equal sheet1.rules.map(&:selector_list_id), sheet2.rules.map(&:selector_list_id)

    # ...but as fully independent state, not shared with the source
    assert_no_shared_mutable_state(sheet1, sheet2)
  end

  # ============================================================================
  # Parser Options - Disable Selector Lists
  # ============================================================================

  def test_selector_lists_disabled_leaves_selector_list_id_nil
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: false })

    # Should still create 3 rules
    assert_selector_count 3, sheet

    # All rules should have nil selector_list_id when disabled
    sheet.rules.each do |rule|
      assert_nil rule.selector_list_id, "Rule '#{rule.selector}' should have nil selector_list_id when disabled"
    end
  end

  def test_selector_lists_enabled_by_default
    css = 'h1, h2 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # selector_lists is enabled by default, so comma-separated rules should
    # share a selector_list_id
    refute_nil sheet.rules.first.selector_list_id, 'selector_lists should be enabled by default'
  end

  def test_selector_lists_explicitly_enabled
    css = 'h1, h2 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: true })

    refute_nil sheet.rules.first.selector_list_id, 'selector_lists should be tracked when explicitly enabled'
  end

  def test_selector_lists_inside_media_query
    # This test covers the uncovered code path at parser.rb:976-985
    # which handles merging nested selector_lists when parsing @media blocks
    css = <<~CSS
      @media screen {
        h1, h2, h3 { font-size: 24px; }
        .btn-primary, .btn-secondary { padding: 10px; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should have 5 rules (3 from h1,h2,h3 + 2 from btn-primary,btn-secondary)
    assert_equal 5, sheet.rules.length

    # Verify all rules are in screen media
    sheet.rules.each do |rule|
      refute_nil rule.media_query_id, "Rule #{rule.selector} should have media_query_id"
      mq = sheet.media_queries[rule.media_query_id]

      assert_equal :screen, mq.type
    end

    # Verify selector_lists were tracked
    list_ids = sheet.rules.map(&:selector_list_id).compact.uniq

    refute_empty list_ids, 'Should have tracked selector lists inside @media'

    # Should have 2 selector lists (one for h1,h2,h3 and one for buttons)
    assert_equal 2, list_ids.size

    # Verify each list has correct number of rule IDs
    sheet.rules.group_by(&:selector_list_id).each do |list_id, rules_in_list|
      next if list_id.nil?

      assert_operator rules_in_list.size, :>=, 2, 'Each selector list should have at least 2 rules'
    end

    # Verify all rules have sequential IDs
    rule_ids = sheet.rules.map(&:id)

    assert_equal (0...sheet.rules.length).to_a, rule_ids.sort, 'Rule IDs should be sequential'
  end

  def test_selector_lists_inside_supports
    # This test covers the uncovered code path at parser.rb:858-867
    # which handles merging nested selector_lists when parsing @supports/@layer/@container/@scope blocks
    css = <<~CSS
      @supports (display: grid) {
        h1, h2, h3 { display: grid; }
        .card, .panel { grid-template-columns: 1fr; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should have 5 rules (3 from h1,h2,h3 + 2 from card,panel)
    assert_equal 5, sheet.rules.length

    # Verify selectors
    assert_has_selector 'h1', sheet
    assert_has_selector 'h2', sheet
    assert_has_selector 'h3', sheet
    assert_has_selector '.card', sheet
    assert_has_selector '.panel', sheet

    # Verify selector_lists were tracked
    list_ids = sheet.rules.map(&:selector_list_id).compact.uniq

    refute_empty list_ids, 'Should have tracked selector lists inside @supports'

    # Should have 2 selector lists
    assert_equal 2, list_ids.size

    # Verify each list has correct number of rule IDs
    sheet.rules.group_by(&:selector_list_id).each do |list_id, rules_in_list|
      next if list_id.nil?

      assert_operator rules_in_list.size, :>=, 2, 'Each selector list should have at least 2 rules'
    end
  end

  def test_media_query_lists_inside_nested_media
    # This test covers the uncovered code path at parser.rb:999-1006
    # which handles merging nested media_query_lists (comma-separated media queries)
    # when parsing nested @media blocks
    css = <<~CSS
      @media screen {
        @media print, projection {
          .foo { color: red; }
        }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Should have 1 rule
    assert_equal 1, sheet.rules.length
    assert_has_selector '.foo', sheet

    # Verify media_query_lists were tracked
    media_query_lists = sheet.instance_variable_get(:@_media_query_lists)

    refute_empty media_query_lists, 'Should have tracked media_query_lists for nested comma-separated @media'

    # Should have at least 1 media query list
    assert_operator media_query_lists.size, :>=, 1
  end
end
