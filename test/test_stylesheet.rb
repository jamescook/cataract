require_relative 'test_helper'
require 'webmock/minitest'

class TestStylesheet < Minitest::Test
  # ============================================================================
  # Basic parsing and structure tests
  # ============================================================================

  def test_parse_returns_new_stylesheet
    css = 'body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_instance_of Cataract::Stylesheet, sheet
  end

  def test_parse_css_forwards_options_to_stylesheet
    # Test that Cataract.parse_css forwards kwargs to Stylesheet constructor
    css = "body { background: url('image.png') }"
    sheet = Cataract.parse_css(css, base_uri: 'http://example.com/css/main.css', absolute_paths: true)

    rule = sheet.rules.first
    value = rule.declarations.first.value

    # URL should be resolved to absolute
    assert_equal "url('http://example.com/css/image.png')", value
  end

  def test_parse_creates_flat_array_of_rules
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    # Rules should be a flat array
    assert_kind_of Array, sheet.rules
    # Each rule should be a Rule struct
    sheet.rules.each do |rule|
      assert_kind_of Cataract::Rule, rule
    end
  end

  def test_new_rule_struct_fields
    # Create a Rule manually to test struct definition
    rule = Cataract::Rule.new(
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
    # Create a Declaration manually to test struct definition
    decl = Cataract::Declaration.new(
      'color',    # property
      'red',      # value
      false       # important
    )

    assert_equal 'color', decl.property
    assert_equal 'red', decl.value
    refute decl.important
  end

  def test_empty_stylesheet
    sheet = Cataract::Stylesheet.new

    assert_equal 0, sheet.size
    assert_empty sheet
    assert_empty sheet.rules
  end

  def test_size_and_length
    css = 'body { color: red; } div { margin: 10px; } h1 { color: blue; }'
    sheet = Cataract::Stylesheet.parse(css)

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

    sheet = Cataract::Stylesheet.parse(css)

    # Verify order is preserved: body rule, then h1 rule (in @media print), then p rule
    rules = sheet.to_a
    assert_equal 3, rules.length
    assert_equal 'body', rules[0].selector
    assert_equal 'h1', rules[1].selector
    assert_equal 'p', rules[2].selector

    # Verify h1 is in print media query
    assert_media_types [:print], rules[1], sheet
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

    sheet = Cataract::Stylesheet.parse(css)
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
    sheet = Cataract::Stylesheet.parse(css)

    assert_matches_media :screen, sheet
    assert_has_selector 'body', sheet, media: :screen
  end

  def test_media_query_deduplication
    css = <<~CSS
      @media screen { h1 { color: red; } }
      @media screen { h2 { color: blue; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Both rules should be accessible via screen media query
    screen_rules = sheet.with_media(:screen)

    assert_equal 2, screen_rules.length
    assert_equal 'h1', screen_rules[0].selector
    assert_equal 'h2', screen_rules[1].selector
  end

  def test_multi_media_serialization_no_duplicates
    # Regression test: ensure rules in multi-media queries don't get duplicated
    # when serializing with multiple media types
    css = <<~CSS
      @media screen, print {
        .foo { color: red; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Verify the rule exists with correct properties
    assert_has_selector '.foo', sheet
    foo_rule = sheet.with_selector('.foo').first
    assert_has_property({ color: 'red' }, foo_rule)

    # Serialize with both media types
    output = sheet.to_s(media: [:screen, :print])

    # Count occurrences of .foo - should appear exactly once in serialized output
    foo_count = output.scan(/\.foo/).count
    assert_equal 1, foo_count,
                 "Rule should appear once in serialized output, not duplicated. " \
                 "Parser adds same rule ID to multiple media indexes, but serialization should dedupe."
  end

  # ============================================================================
  # Charset handling
  # ============================================================================

  def test_charset_parsing
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 'UTF-8', sheet.charset
    assert_equal 1, sheet.size
  end

  # ============================================================================
  # Utility methods
  # ============================================================================

  def test_clear
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 2, sheet.size

    sheet.clear!

    assert_equal 0, sheet.size
    assert_empty sheet
    assert_nil sheet.charset
  end

  def test_inspect_empty
    sheet = Cataract::Stylesheet.new

    inspect_str = sheet.inspect

    # Verify inspect format shows empty state
    assert_equal '#<Cataract::Stylesheet empty>', inspect_str
  end

  def test_inspect_with_rules
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    inspect_str = sheet.inspect

    # Verify inspect format shows count and selectors
    assert_equal '#<Cataract::Stylesheet 2 rules: body, div>', inspect_str
  end

  # ============================================================================
  # Safety limit tests
  # ============================================================================

  def test_media_query_safety_limit
    # Generate CSS with too many unique media queries
    css = (1..1001).map { |i| "@media (width: #{i}px) { a {} }" }.join("\n")

    assert_raises(Cataract::SizeError) do
      Cataract::Stylesheet.parse(css)
    end
  end

  # ============================================================================
  # Tests copied from test_stylesheet.rb (missing functionality)
  # ============================================================================

  def test_round_trip_bootstrap
    css = File.read('test/fixtures/bootstrap.css')
    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.to_s

    # Should be able to parse the result
    sheet2 = Cataract::Stylesheet.parse(result)

    assert_predicate sheet2.size, :positive?
  end

  def test_add_block
    css1 = 'body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css1)

    assert_equal 1, sheet.size

    sheet.add_block('div { margin: 10px; }')

    assert_equal 2, sheet.size
  end

  def test_add_block_with_fix_braces
    sheet = Cataract::Stylesheet.new
    sheet.add_block('p { color: red;', fix_braces: true)

    rules = sheet.with_selector('p')

    assert_equal 1, rules.length
    assert_kind_of Cataract::Rule, rules.first
    assert_equal 'p', rules.first.selector
    assert_equal 1, rules.first.declarations.length
  end

  def test_adding_a_rule
    sheet = Cataract::Stylesheet.new
    sheet.add_rule(selector: 'div', declarations: 'color: blue')

    assert_equal 1, sheet.size
  end

  def test_converting_to_hash
    sheet = Cataract::Stylesheet.new
    hash = sheet.to_h

    assert_kind_of Hash, hash
  end

  def test_rules_count_alias
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_respond_to sheet, :rules_count
    assert_equal sheet.size, sheet.rules_count
  end

  def test_load_file_class_method
    require 'tempfile'
    Tempfile.create(['test', '.css']) do |f|
      f.write('.test { color: red; }')
      f.flush

      sheet = Cataract::Stylesheet.load_file(f.path)

      assert_instance_of Cataract::Stylesheet, sheet
      assert_equal 1, sheet.size
    end
  end

  def test_load_uri_https
    css_fixture = <<~CSS
      .button { background: blue; padding: 10px; }
      .header { font-size: 24px; }
    CSS

    stub_request(:get, 'https://example.com/styles.css')
      .to_return(status: 200, body: css_fixture, headers: { 'Content-Type' => 'text/css' })

    sheet = Cataract::Stylesheet.load_uri('https://example.com/styles.css')

    assert_instance_of Cataract::Stylesheet, sheet
    assert_equal 2, sheet.size
    assert_equal %w[.button .header], sheet.select(&:selector?).map(&:selector)
  end

  def test_load_uri_http
    css_fixture = '.link { color: red; }'

    stub_request(:get, 'http://example.com/main.css')
      .to_return(status: 200, body: css_fixture)

    sheet = Cataract::Stylesheet.load_uri('http://example.com/main.css')

    assert_instance_of Cataract::Stylesheet, sheet
    assert_equal 1, sheet.size
    assert_equal '.link', sheet.rules.first.selector
  end

  def test_load_uri_http_error
    stub_request(:get, 'https://example.com/not-found.css')
      .to_return(status: 404, body: 'Not Found')

    assert_raises(IOError) do
      Cataract::Stylesheet.load_uri('https://example.com/not-found.css')
    end
  end

  # ============================================================================
  # Stylesheet equality and hash tests
  # ============================================================================

  def test_stylesheet_equality_same_rules
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    assert_equal sheet1, sheet2
  end

  def test_stylesheet_equality_shorthand_vs_longhand
    # Your example from the discussion
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    assert_equal sheet1, sheet2, 'Shorthand and longhand stylesheets should be equal'
  end

  def test_stylesheet_equality_different_rules
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: blue; }')

    refute_equal sheet1, sheet2
  end

  def test_stylesheet_equality_different_order
    # Order matters for cascade rules
    sheet1 = Cataract.parse_css('.box { color: red; } .box { color: blue; }')
    sheet2 = Cataract.parse_css('.box { color: blue; } .box { color: red; }')

    refute_equal sheet1, sheet2, 'Order matters for CSS cascade'
  end

  def test_stylesheet_equality_with_media_queries
    sheet1 = Cataract.parse_css('@media print { .box { color: red; } }')
    sheet2 = Cataract.parse_css('@media print { .box { color: red; } }')

    assert_equal sheet1, sheet2
  end

  def test_stylesheet_equality_different_media
    sheet1 = Cataract.parse_css('@media print { .box { color: red; } }')
    sheet2 = Cataract.parse_css('@media screen { .box { color: red; } }')

    refute_equal sheet1, sheet2, 'Different media queries should not be equal'
  end

  def test_stylesheet_hash_contract_equal_objects_same_hash
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    assert_equal sheet1, sheet2, 'Stylesheets should be equal'
    assert_equal sheet1.hash, sheet2.hash, 'Equal stylesheets must have same hash'
  end

  def test_stylesheets_as_hash_keys
    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    cache = {}
    cache[sheet1] = 'processed_stylesheet'

    assert_equal 'processed_stylesheet', cache[sheet2], 'Equal stylesheets should work as same Hash key'
  end

  def test_stylesheets_in_set
    require 'set'

    sheet1 = Cataract.parse_css('.box { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    stylesheets = Set.new
    stylesheets << sheet1

    assert_member stylesheets, sheet2, 'Set should recognize equivalent stylesheet'
    assert_equal 1, stylesheets.size

    stylesheets << sheet2
    assert_equal 1, stylesheets.size, 'Set should not add duplicate'
  end

  def test_stylesheet_equality_with_non_stylesheet
    sheet = Cataract.parse_css('.box { color: red; }')

    refute_equal sheet, 'not a stylesheet'
    refute_equal sheet, nil
  end

  # ============================================================================
  # Stylesheet combining tests (concat, +)
  # ============================================================================

  def test_concat_combines_and_applies_cascade
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    sheet1.concat(sheet2)

    assert_equal 2, sheet1.rules.size
    assert_equal '.box', sheet1.rules[0].selector
    assert_equal '.other', sheet1.rules[1].selector
  end

  def test_concat_returns_self
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1.concat(sheet2)

    assert_same sheet1, result, 'concat should return self for chaining'
  end

  def test_concat_applies_cascade_on_conflicts
    # concat SHOULD apply cascade when rules conflict
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: blue; }')

    sheet1.concat(sheet2)

    assert_equal 1, sheet1.rules.size, 'concat should apply cascade'
    assert sheet1.rules[0].has_property?('color', 'blue'), 'Last rule should win'
  end

  def test_concat_merges_non_conflicting_properties
    sheet1 = Cataract.parse_css('.box { color: red; margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { color: blue; padding: 5px; }')

    sheet1.concat(sheet2)

    assert_equal 1, sheet1.rules.size
    assert sheet1.rules[0].has_property?('color', 'blue'), 'Conflicting property: last wins'
    assert sheet1.rules[0].has_property?('margin', '10px'), 'Non-conflicting from sheet1'
    assert sheet1.rules[0].has_property?('padding', '5px'), 'Non-conflicting from sheet2'
  end

  def test_plus_operator_combines_and_applies_cascade
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1 + sheet2

    assert_equal 2, result.rules.size
    assert_equal '.box', result.rules[0].selector
    assert_equal '.other', result.rules[1].selector
  end

  def test_plus_operator_returns_new_stylesheet
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1 + sheet2

    refute_same sheet1, result, '+ should return new stylesheet'
    refute_same sheet2, result, '+ should return new stylesheet'
    assert_equal 1, sheet1.rules.size, 'Original sheet1 should be unchanged'
    assert_equal 1, sheet2.rules.size, 'Original sheet2 should be unchanged'
  end

  def test_plus_operator_applies_cascade_on_conflicts
    # + SHOULD apply cascade when rules conflict
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: blue; }')

    result = sheet1 + sheet2

    assert_equal 1, result.rules.size, '+ should apply cascade'
    assert result.rules[0].has_property?('color', 'blue'), 'Last rule should win'
  end
end
