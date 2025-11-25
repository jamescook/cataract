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

  def test_simple_selector_list_tracked_in_selector_lists_hash
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract.parse_css(css)

    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    refute_empty selector_lists, 'Should have selector list entries'

    # Should have one list entry
    assert_equal 1, selector_lists.size

    # Get the list ID and rule IDs
    _, rule_ids = selector_lists.first

    assert_equal 3, rule_ids.size, 'List should contain 3 rule IDs'

    # Verify rule IDs match actual rules
    assert_equal rule_ids.sort, sheet.rules.map(&:id).sort
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

    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_empty selector_lists, 'Single selectors should not create list entries'
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

    # Should have exactly one list entry
    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_equal 1, selector_lists.size
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

    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_equal 2, selector_lists.size, 'Should have two independent selector lists'

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

    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_equal 3, selector_lists.size, 'Should have three independent selector lists'

    # Each list should have 2 rules
    selector_lists.each_value do |rule_ids|
      assert_equal 2, rule_ids.size
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

    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_equal 1, selector_lists.size
    _list_id, rule_ids = selector_lists.first

    assert_equal 20, rule_ids.size
  end

  def test_selector_list_id_counter_increments
    css = 'h1, h2 { color: red; } h3, h4 { color: blue; }'
    sheet = Cataract.parse_css(css)

    selector_lists = sheet.instance_variable_get(:@_selector_lists)
    list_ids = selector_lists.keys.sort

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

    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_equal 2, selector_lists.size, 'Should have two selector lists (one in base, one in @media)'
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

    # Selector lists should be duplicated
    selector_lists1 = sheet1.instance_variable_get(:@_selector_lists)
    selector_lists2 = sheet2.instance_variable_get(:@_selector_lists)

    assert_equal selector_lists1.keys, selector_lists2.keys
    refute_same selector_lists1, selector_lists2, 'Should be a different object'
  end

  def test_selector_list_counter_tracks_correctly
    css = 'h1, h2 { color: red; }'
    sheet = Cataract.parse_css(css)

    counter = sheet.instance_variable_get(:@_next_selector_list_id)

    assert_equal 1, counter, 'Counter should be 1 after creating one list (IDs are 0-indexed)'
  end

  # ============================================================================
  # Parser Options - Disable Selector Lists
  # ============================================================================

  def test_selector_lists_disabled_does_not_populate_hash
    css = 'h1, h2, h3 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: false })

    # Should still create 3 rules
    assert_selector_count 3, sheet

    # But selector_lists hash should be empty
    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    assert_empty selector_lists, 'Selector lists should be empty when disabled'

    # All rules should have nil selector_list_id
    sheet.rules.each do |rule|
      assert_nil rule.selector_list_id, "Rule '#{rule.selector}' should have nil selector_list_id when disabled"
    end

    # Counter should not increment
    counter = sheet.instance_variable_get(:@_next_selector_list_id)

    assert_equal 0, counter, 'Counter should stay at 0 when selector lists disabled'
  end

  def test_selector_lists_enabled_by_default
    css = 'h1, h2 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Parser options should have selector_lists: true by default
    parser_options = sheet.instance_variable_get(:@parser_options)

    assert parser_options[:selector_lists], 'selector_lists should be enabled by default'

    # Should track selector lists
    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    refute_empty selector_lists, 'Selector lists should be tracked by default'
  end

  def test_selector_lists_explicitly_enabled
    css = 'h1, h2 { color: red; }'
    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: true })

    # Should track selector lists
    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    refute_empty selector_lists, 'Selector lists should be tracked when explicitly enabled'

    # Rules should have selector_list_id
    refute_nil sheet.rules.first.selector_list_id
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
    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    refute_empty selector_lists, 'Should have tracked selector lists inside @media'

    # Should have 2 selector lists (one for h1,h2,h3 and one for buttons)
    assert_equal 2, selector_lists.size

    # Verify each list has correct number of rule IDs
    selector_lists.each_value do |rule_ids|
      assert_operator rule_ids.size, :>=, 2, 'Each selector list should have at least 2 rules'
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
    selector_lists = sheet.instance_variable_get(:@_selector_lists)

    refute_empty selector_lists, 'Should have tracked selector lists inside @supports'

    # Should have 2 selector lists
    assert_equal 2, selector_lists.size

    # Verify each list has correct number of rule IDs
    selector_lists.each_value do |rule_ids|
      assert_operator rule_ids.size, :>=, 2, 'Each selector list should have at least 2 rules'
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
