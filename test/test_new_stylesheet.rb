require_relative 'test_helper'

class TestNewStylesheet < Minitest::Test
  # ============================================================================
  # Basic parsing and structure tests
  # ============================================================================

  def test_parse_returns_new_stylesheet
    css = 'body { color: red; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_instance_of Cataract::NewStylesheet, sheet
  end

  def test_parse_creates_flat_array_of_rules
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::NewStylesheet.parse(css)

    # Rules should be a flat array
    assert_kind_of Array, sheet.rules
    # Each rule should be a NewRule struct
    sheet.rules.each do |rule|
      assert_kind_of Cataract::NewRule, rule
    end
  end

  def test_new_rule_struct_fields
    # Create a NewRule manually to test struct definition
    rule = Cataract::NewRule.new(
      0,                         # id
      'body',                    # selector
      [],                        # declarations
      1                          # specificity
    )

    assert_equal 0, rule.id
    assert_equal 'body', rule.selector
    assert_empty rule.declarations
    assert_equal 1, rule.specificity
  end

  def test_new_declaration_struct_fields
    # Create a NewDeclaration manually to test struct definition
    decl = Cataract::NewDeclaration.new(
      'color',    # property
      'red',      # value
      false       # important
    )

    assert_equal 'color', decl.property
    assert_equal 'red', decl.value
    refute decl.important
  end

  def test_empty_stylesheet
    sheet = Cataract::NewStylesheet.new

    assert_equal 0, sheet.size
    assert_empty sheet
    assert_empty sheet.rules
  end

  def test_size_and_length
    css = 'body { color: red; } div { margin: 10px; } h1 { color: blue; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_equal 3, sheet.size
    assert_equal 3, sheet.length
  end

  # ============================================================================
  # Insertion order preservation (KEY FEATURE)
  # ============================================================================

  def test_preserves_insertion_order
    css = <<~CSS
      body { color: red; }
      @media print { h1 { color: blue; } }
      p { color: green; }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)
    output = sheet.to_s

    # Should preserve exact order
    assert_match(/body.*@media.*p/m, output)
  end

  def test_complex_interleaved_media
    css = <<~CSS
      body { margin: 0; }
      @media screen { h1 { color: red; } }
      p { padding: 0; }
      @media print { h1 { color: blue; } }
      @media screen { h2 { color: green; } }
      div { display: block; }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)
    output = sheet.to_s

    # Verify exact order preserved by checking positions
    positions = {
      body: output.index('body'),
      first_screen: output.index('@media screen'),
      p: output.index('p {'),
      print: output.index('@media print'),
      second_screen: output.rindex('@media screen'),
      div: output.index('div')
    }

    assert_operator positions[:body], :<, positions[:first_screen]
    assert_operator positions[:first_screen], :<, positions[:p]
    assert_operator positions[:p], :<, positions[:print]
    assert_operator positions[:print], :<, positions[:second_screen]
    assert_operator positions[:second_screen], :<, positions[:div]
  end

  # ============================================================================
  # Media query handling (as symbols)
  # ============================================================================

  def test_media_query_stored_as_symbol
    css = '@media screen { body { color: red; } }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_matches_media :screen, sheet
    assert_has_selector 'body', sheet, media: :screen
  end

  def test_media_query_deduplication
    css = <<~CSS
      @media screen { h1 { color: red; } }
      @media screen { h2 { color: blue; } }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)

    # Both rules should be in same media_index entry
    assert_includes sheet.media_index[:screen], sheet.rules[0].id
    assert_includes sheet.media_index[:screen], sheet.rules[1].id
  end

  def test_for_media_filter
    css = <<~CSS
      body { color: black; }
      @media screen { h1 { color: red; } }
      @media print { h2 { color: blue; } }
      @media screen { p { color: green; } }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)

    assert_matches_media :screen, sheet
    assert_matches_media :print, sheet

    screen_rules = sheet.for_media(:screen)

    assert_equal 2, screen_rules.length
    assert_equal %w[h1 p], screen_rules.map(&:selector)
  end

  def test_base_rules_filter
    css = <<~CSS
      body { color: black; }
      @media screen { h1 { color: red; } }
      div { margin: 0; }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)

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

    sheet = Cataract::NewStylesheet.parse(css)
    media_queries = sheet.media_queries

    assert_equal 2, media_queries.length
    assert_includes media_queries, :screen
    assert_includes media_queries, :print
  end

  # ============================================================================
  # Charset handling
  # ============================================================================

  def test_charset_parsing
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_equal 'UTF-8', sheet.charset
    assert_equal 1, sheet.size
  end

  def test_no_charset
    css = 'body { color: red; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_nil sheet.charset
    refute_includes sheet.to_s, '@charset'
  end

  def test_charset_serialization
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract::NewStylesheet.parse(css)
    result = sheet.to_s

    # @charset should be first line
    assert_match(/\A@charset "UTF-8";/, result)
    assert_includes result, 'body'
  end

  # ============================================================================
  # Round-trip tests
  # ============================================================================

  def test_round_trip
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract::NewStylesheet.parse(css)
    result = sheet.to_s

    # Parse the result again
    sheet2 = Cataract::NewStylesheet.parse(result)

    assert_equal sheet.size, sheet2.size
  end

  # ============================================================================
  # Utility methods
  # ============================================================================

  def test_clear
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_equal 2, sheet.size

    sheet.clear!

    assert_equal 0, sheet.size
    assert_empty sheet
    assert_nil sheet.charset
  end

  def test_inspect_empty
    sheet = Cataract::NewStylesheet.new

    inspect_str = sheet.inspect

    assert_includes inspect_str, 'NewStylesheet'
    assert_includes inspect_str, 'empty'
  end

  def test_inspect_with_rules
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::NewStylesheet.parse(css)

    inspect_str = sheet.inspect

    assert_includes inspect_str, 'NewStylesheet'
    assert_includes inspect_str, '2 rules'
  end

  # ============================================================================
  # Serialization (to_s) tests
  # ============================================================================

  def test_to_s_basic
    # Normalized fixture matching serialization format
    css = "body { color: red; margin: 10px; }\n"
    sheet = Cataract::NewStylesheet.parse(css)

    assert_equal 1, sheet.rules.length

    rule = sheet.rules[0]

    assert_equal 'body', rule.selector
    assert_equal 2, rule.declarations.length

    # Check declarations
    color_decl = rule.declarations.find { |d| d.property == 'color' }

    assert_equal 'red', color_decl.value
    refute color_decl.important

    margin_decl = rule.declarations.find { |d| d.property == 'margin' }

    assert_equal '10px', margin_decl.value
    refute margin_decl.important

    # E2E: Round-trip should match exactly
    assert_equal css, sheet.to_s
  end

  def test_to_s_with_important
    # Normalized fixture matching serialization format
    css = "div { color: blue !important; }\n"
    sheet = Cataract::NewStylesheet.parse(css)

    assert_equal 1, sheet.rules.length

    rule = sheet.rules[0]

    assert_equal 'div', rule.selector
    assert_equal 1, rule.declarations.length

    # Check declaration with !important
    decl = rule.declarations[0]

    assert_equal 'color', decl.property
    assert_equal 'blue', decl.value
    assert decl.important

    # E2E: Round-trip should match exactly
    assert_equal css, sheet.to_s
  end

  def test_to_s_groups_consecutive_media_rules
    # Normalized fixture - consecutive @media rules should group
    css_input = <<~CSS.chomp
      body { color: black; }
      @media screen { h1 { color: red; } }
      @media screen { h2 { color: blue; } }
      div { margin: 0; }
    CSS

    # Expected output groups consecutive screen rules
    css_expected = <<~CSS.chomp
      body { color: black; }
      @media screen {
      h1 { color: red; }
      h2 { color: blue; }
      }
      div { margin: 0; }
    CSS

    sheet = Cataract::NewStylesheet.parse(css_input)

    # Check parsed structure
    assert_equal 4, sheet.rules.length

    assert_equal 'body', sheet.rules[0].selector

    assert_equal 'h1', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    assert_equal 'div', sheet.rules[3].selector

    # E2E: Should group consecutive @media rules
    assert_equal css_expected, sheet.to_s.chomp
  end

  def test_to_s_separates_non_consecutive_media_rules
    css = <<~CSS
      @media screen { h1 { color: red; } }
      body { color: black; }
      @media screen { h2 { color: blue; } }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)

    # Check parsed structure preserves order
    assert_equal 3, sheet.rules.length

    assert_equal 'h1', sheet.rules[0].selector

    assert_equal 'body', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    # Verify serialization creates TWO separate @media blocks
    # (because body rule interrupts the screen rules)
    output = sheet.to_s
    media_count = output.scan(/@media screen/).length

    assert_equal 2, media_count, 'Should create separate @media blocks when interrupted'

    # Verify order is preserved
    body_pos = output.index('body')
    first_media_pos = output.index('@media screen')
    second_media_pos = output.rindex('@media screen')

    assert_operator first_media_pos, :<, body_pos, 'First @media should come before body'
    assert_operator body_pos, :<, second_media_pos, 'Body should come before second @media'
  end

  def test_to_s_mixed_media_queries
    css = <<~CSS
      body { margin: 0; }
      @media screen { h1 { color: red; } }
      @media print { h2 { color: blue; } }
      @media screen { p { color: green; } }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)

    # Check parsed structure
    assert_equal 4, sheet.rules.length

    assert_equal 'body', sheet.rules[0].selector

    assert_equal 'h1', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    assert_equal 'p', sheet.rules[3].selector

    # Verify serialization preserves order
    output = sheet.to_s

    assert_operator output.index('body'), :<, output.index('@media screen')
    assert_operator output.index('@media screen'), :<, output.index('@media print')
    assert_operator output.index('@media print'), :<, output.rindex('@media screen')
  end

  # ============================================================================
  # Nested media query tests (each_selector behavior)
  # ============================================================================

  def test_nested_media_each_selector
    css = <<~CSS
      @media screen {
        @media (min-width: 500px) {
          .nested { color: red; }
        }
      }
      .normal { color: blue; }
    CSS

    sheet = Cataract::NewStylesheet.parse(css)

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

    # Verify media_index structure (low-level plumbing check)
    assert_equal [0], sheet.media_index[combined_media]
    assert_equal [0], sheet.media_index[:screen]
  end

  # ============================================================================
  # Safety limit tests
  # ============================================================================

  def test_media_query_safety_limit
    # Generate CSS with too many unique media queries
    css = (1..1001).map { |i| "@media (width: #{i}px) { a {} }" }.join("\n")

    assert_raises(Cataract::SizeError) do
      Cataract::NewStylesheet.parse(css)
    end
  end

  # ============================================================================
  # Tests copied from test_stylesheet.rb (missing functionality)
  # ============================================================================

  def test_round_trip_bootstrap
    css = File.read('test/fixtures/bootstrap.css')
    sheet = Cataract::NewStylesheet.parse(css)
    result = sheet.to_s

    # Should be able to parse the result
    sheet2 = Cataract::NewStylesheet.parse(result)

    assert_predicate sheet2.size, :positive?
  end

  def test_charset_round_trip
    css = '@charset "UTF-8";
.test { margin: 5px; }'
    sheet = Cataract::NewStylesheet.parse(css)
    result = sheet.to_s

    # Parse again and verify charset preserved
    sheet2 = Cataract::NewStylesheet.parse(result)

    assert_equal 'UTF-8', sheet2.charset
    assert_equal 1, sheet2.size
  end

  def test_add_block
    css1 = 'body { color: red; }'
    sheet = Cataract::NewStylesheet.parse(css1)

    assert_equal 1, sheet.size

    sheet.add_block('div { margin: 10px; }')

    assert_equal 2, sheet.size
  end

  def test_add_block_with_fix_braces
    sheet = Cataract::NewStylesheet.new
    sheet.add_block('p { color: red;', fix_braces: true)

    rules = sheet.find_by_selector('p')

    assert_equal 1, rules.length
    assert_kind_of Cataract::NewRule, rules.first
    assert_equal 'p', rules.first.selector
    assert_equal 1, rules.first.declarations.length
  end

  def test_each_selector_basic
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_equal %w[body div], sheet.selectors
  end

  def test_finding_by_selector
    css = <<-CSS
      html, body, p { margin: 0px; }
      p { padding: 0px; }
      #content { font: 12px/normal sans-serif; }
      .content { color: red; }
    CSS

    stylesheet = Cataract::NewStylesheet.parse(css)

    # find_by_selector returns array of NewRule objects
    body_rules = stylesheet.find_by_selector('body')

    assert_equal 1, body_rules.size
    assert_kind_of Cataract::NewRule, body_rules[0]
    assert_equal 'body', body_rules[0].selector

    # Can access declarations from the rule
    assert_equal 1, body_rules[0].declarations.length
  end

  def test_adding_a_rule
    sheet = Cataract::NewStylesheet.new
    sheet.add_rule(selector: 'div', declarations: 'color: blue')

    assert_equal 1, sheet.size
  end

  def test_converting_to_hash
    sheet = Cataract::NewStylesheet.new
    hash = sheet.to_h

    assert_kind_of Hash, hash
  end

  def test_selectors_all
    css = 'body { color: red; } .header { padding: 5px; } #main { font-size: 14px; }'
    sheet = Cataract::NewStylesheet.parse(css)
    sels = sheet.selectors

    assert_equal 3, sels.length
    assert_includes sels, 'body'
    assert_includes sels, '.header'
    assert_includes sels, '#main'
  end

  def test_to_css_alias
    css = 'body { color: red; }'
    sheet = Cataract::NewStylesheet.parse(css)

    # to_css should be an alias for to_s
    assert_respond_to sheet, :to_css
    assert_equal sheet.to_s, sheet.to_css
  end

  def test_rules_count_alias
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::NewStylesheet.parse(css)

    assert_respond_to sheet, :rules_count
    assert_equal sheet.size, sheet.rules_count
  end

  def test_load_file_class_method
    require 'tempfile'
    Tempfile.create(['test', '.css']) do |f|
      f.write('.test { color: red; }')
      f.flush

      sheet = Cataract::NewStylesheet.load_file(f.path)

      assert_instance_of Cataract::NewStylesheet, sheet
      assert_equal 1, sheet.size
    end
  end
end
