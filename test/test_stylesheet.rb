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

  def test_each_selector_basic
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal %w[body div], sheet.selectors
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

  def test_selectors_all
    css = 'body { color: red; } .header { padding: 5px; } #main { font-size: 14px; }'
    sheet = Cataract::Stylesheet.parse(css)
    sels = sheet.selectors

    assert_equal 3, sels.length
    assert_member sels, 'body'
    assert_member sels, '.header'
    assert_member sels, '#main'
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
  # Advanced filtering tests (chainable scopes)
  # ============================================================================

  def test_with_property_basic
    css = <<~CSS
      body { color: red; margin: 0; }
      .header { padding: 10px; color: blue; }
      .footer { margin: 5px; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all rules with color property
    color_rules = sheet.with_property('color')

    assert_equal 2, color_rules.size
    assert_equal %w[body .header], color_rules.map(&:selector)

    # Find all rules with margin property
    margin_rules = sheet.with_property('margin')

    assert_equal 2, margin_rules.size
    assert_equal %w[body .footer], margin_rules.map(&:selector)

    # Find rules with padding property
    padding_rules = sheet.with_property('padding')

    assert_equal 1, padding_rules.size
    assert_equal '.header', padding_rules.first.selector
  end

  def test_with_property_and_value
    css = <<~CSS
      body { color: red; }
      .header { color: blue; }
      .footer { color: red; margin: 0; }
      .sidebar { position: absolute; }
      .content { position: relative; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find rules with color: red
    red_rules = sheet.with_property('color', 'red')

    assert_equal 2, red_rules.size
    assert_equal %w[body .footer], red_rules.map(&:selector)

    # Find rules with color: blue
    blue_rules = sheet.with_property('color', 'blue')

    assert_equal 1, blue_rules.size
    assert_equal '.header', blue_rules.first.selector

    # Find rules with position: absolute
    absolute_rules = sheet.with_property('position', 'absolute')

    assert_equal 1, absolute_rules.size
    assert_equal '.sidebar', absolute_rules.first.selector
  end

  def test_with_property_chainable
    css = <<~CSS
      body { color: red; }
      @media screen { .header { color: blue; } }
      @media print { .footer { color: red; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with media filter
    screen_color_rules = sheet.with_media(:screen).with_property('color')

    assert_equal 1, screen_color_rules.size
    assert_equal '.header', screen_color_rules.first.selector

    # Chain with property and value
    print_red_rules = sheet.with_media(:print).with_property('color', 'red')

    assert_equal 1, print_red_rules.size
    assert_equal '.footer', print_red_rules.first.selector
  end

  def test_with_selector_string
    css = <<~CSS
      body { color: red; }
      .header { padding: 10px; }
      .footer { margin: 5px; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find by exact string match
    body_rules = sheet.with_selector('body')

    assert_equal 1, body_rules.size
    assert_equal 'body', body_rules.first.selector

    header_rules = sheet.with_selector('.header')

    assert_equal 1, header_rules.size
    assert_equal '.header', header_rules.first.selector
  end

  def test_with_selector_regexp
    css = <<~CSS
      .btn-primary { color: blue; }
      .btn-secondary { color: gray; }
      .btn-danger { color: red; }
      .header { padding: 10px; }
      #main { margin: 0; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all .btn-* classes using regex
    btn_rules = sheet.with_selector(/\.btn-/)

    assert_equal 3, btn_rules.size
    assert_equal %w[.btn-primary .btn-secondary .btn-danger], btn_rules.map(&:selector)

    # Find all ID selectors
    id_rules = sheet.with_selector(/^#/)

    assert_equal 1, id_rules.size
    assert_equal '#main', id_rules.first.selector

    # Find selectors containing 'header'
    header_rules = sheet.with_selector(/header/)

    assert_equal 1, header_rules.size
    assert_equal '.header', header_rules.first.selector
  end

  def test_with_selector_chainable_with_regexp
    css = <<~CSS
      .btn-primary { color: blue; }
      @media screen { .btn-secondary { color: gray; } }
      @media print { .btn-danger { color: red; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain regex selector with media filter
    screen_btn_rules = sheet.with_media(:screen).with_selector(/\.btn-/)

    assert_equal 1, screen_btn_rules.size
    assert_equal '.btn-secondary', screen_btn_rules.first.selector
  end

  def test_base_only
    css = <<~CSS
      body { color: black; }
      @media screen { .screen { color: blue; } }
      div { margin: 0; }
      @media print { .print { color: red; } }
      p { padding: 5px; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Get only base rules (not in any @media)
    base = sheet.base_only

    assert_equal 3, base.size
    assert_equal %w[body div p], base.map(&:selector)

    # Should be chainable
    assert_kind_of Cataract::StylesheetScope, base
  end

  def test_base_only_chainable
    css = <<~CSS
      body { color: red; }
      div { color: blue; margin: 0; }
      @media screen { .screen { color: green; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with property filter
    base_with_color = sheet.base_only.with_property('color')

    assert_equal 2, base_with_color.size
    assert_equal %w[body div], base_with_color.map(&:selector)

    # Chain with specificity
    base_high_spec = sheet.base_only.with_specificity(1)

    assert_equal 2, base_high_spec.size
  end

  def test_with_at_rule_type_keyframes
    css = <<~CSS
      @keyframes fadeIn { 0% { opacity: 0; } 100% { opacity: 1; } }
      @keyframes slideIn { 0% { transform: translateX(-100%); } }
      body { color: red; }
      @font-face { font-family: 'MyFont'; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all @keyframes
    keyframes = sheet.with_at_rule_type(:keyframes)

    assert_equal 2, keyframes.size
    assert keyframes.all?(&:at_rule?)

    selectors = keyframes.map(&:selector)
    assert_member selectors, '@keyframes fadeIn'
    assert_member selectors, '@keyframes slideIn'
  end

  def test_with_at_rule_type_font_face
    css = <<~CSS
      @font-face { font-family: 'Font1'; src: url('font1.woff'); }
      @font-face { font-family: 'Font2'; src: url('font2.woff'); }
      body { color: red; }
      @keyframes fadeIn { 0% { opacity: 0; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all @font-face
    fonts = sheet.with_at_rule_type(:font_face)

    assert_equal 2, fonts.size
    assert fonts.all?(&:at_rule?)
    assert(fonts.all? { |r| r.selector == '@font-face' })
  end

  def test_with_at_rule_type_chainable
    css = <<~CSS
      @media screen {
        @keyframes slideIn { 0% { transform: translateX(-100%); } }
      }
      @keyframes fadeIn { 0% { opacity: 0; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with media filter
    screen_keyframes = sheet.with_media(:screen).with_at_rule_type(:keyframes)

    assert_equal 1, screen_keyframes.size
    assert_equal '@keyframes slideIn', screen_keyframes.first.selector
  end

  def test_with_important_basic
    css = <<~CSS
      body { color: red; }
      .header { color: blue !important; margin: 10px; }
      .footer { padding: 5px !important; font-size: 14px !important; }
      .sidebar { border: 1px solid; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all rules with any !important declaration
    important_rules = sheet.with_important

    assert_equal 2, important_rules.size
    assert_equal %w[.header .footer], important_rules.map(&:selector)
  end

  def test_with_important_by_property
    css = <<~CSS
      body { color: red; }
      .header { color: blue !important; margin: 10px; }
      .footer { padding: 5px !important; color: green !important; }
      .sidebar { margin: 10px !important; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find rules with color !important
    color_important = sheet.with_important('color')

    assert_equal 2, color_important.size
    assert_equal %w[.header .footer], color_important.map(&:selector)

    # Find rules with margin !important
    margin_important = sheet.with_important('margin')

    assert_equal 1, margin_important.size
    assert_equal '.sidebar', margin_important.first.selector

    # Find rules with padding !important
    padding_important = sheet.with_important('padding')

    assert_equal 1, padding_important.size
    assert_equal '.footer', padding_important.first.selector
  end

  def test_with_important_chainable
    css = <<~CSS
      body { color: red !important; }
      @media screen { .header { color: blue !important; } }
      @media print { .footer { margin: 0; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with media filter
    screen_important = sheet.with_media(:screen).with_important

    assert_equal 1, screen_important.size
    assert_equal '.header', screen_important.first.selector

    # Chain with property
    screen_color_important = sheet.with_media(:screen).with_important('color')

    assert_equal 1, screen_color_important.size
    assert_equal '.header', screen_color_important.first.selector
  end

  def test_complex_filter_chaining
    css = <<~CSS
      body { color: red; z-index: 1; }
      @media screen {
        .header { color: blue !important; z-index: 100; }
        .nav { padding: 10px; }
        #sidebar { color: green; z-index: 150; }
      }
      @media print { .footer { color: black; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Complex chain: screen media + has z-index + high specificity + selector-based rules only
    result = sheet.with_media(:screen)
                  .with_property('z-index')
                  .with_specificity(10..)
                  .select(&:selector?)

    assert_equal 2, result.size
    assert_equal %w[.header #sidebar], result.map(&:selector)

    # Another complex chain: screen + !important + color property
    result2 = sheet.with_media(:screen)
                   .with_important('color')
                   .with_selector(/header/)

    assert_equal 1, result2.size
    assert_equal '.header', result2.first.selector
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

  # ============================================================================
  # Stylesheet subtraction tests (-)
  # ============================================================================

  def test_minus_operator_removes_matching_rules
    sheet1 = Cataract.parse_css('.box { color: red; } .other { margin: 10px; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, '- should remove matching rules'
    assert_equal '.other', result.rules[0].selector
  end

  def test_minus_operator_returns_new_stylesheet
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    result = sheet1 - sheet2

    refute_same sheet1, result, '- should return new stylesheet'
    assert_equal 1, sheet1.rules.size, 'Original should be unchanged'
  end

  def test_minus_operator_uses_shorthand_aware_matching
    # Should remove rule using Rule#== (shorthand-aware)
    sheet1 = Cataract.parse_css('.box { margin: 10px; } .other { color: red; }')
    sheet2 = Cataract.parse_css('.box { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, 'Shorthand should match longhand'
    assert_equal '.other', result.rules[0].selector
  end

  def test_minus_operator_does_not_apply_cascade
    # - should NOT apply cascade, just remove rules
    sheet1 = Cataract.parse_css('.box { color: red; } .box { color: blue; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1 - sheet2

    assert_equal 2, result.rules.size, '- should not apply cascade'
    assert_equal '.box', result.rules[0].selector
    assert_equal '.box', result.rules[1].selector
  end

  def test_minus_operator_no_matching_rules
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.other { margin: 10px; }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, 'Should keep all rules when no matches'
    assert_equal '.box', result.rules[0].selector
  end

  def test_minus_operator_removes_all_rules
    sheet1 = Cataract.parse_css('.box { color: red; }')
    sheet2 = Cataract.parse_css('.box { color: red; }')

    result = sheet1 - sheet2

    assert_equal 0, result.rules.size, 'Should remove all matching rules'
  end

  def test_minus_operator_preserves_media_queries
    # Keep rules with media queries that don't match
    sheet1 = Cataract.parse_css('@media print { .box { color: red; } } @media screen { .other { margin: 10px; } }')
    sheet2 = Cataract.parse_css('@media print { .box { color: red; } }')

    result = sheet1 - sheet2

    assert_equal 1, result.rules.size, 'Should remove matching media rule'
    assert_equal '.other', result.rules[0].selector
    assert_member result.media_queries, :screen
    refute_includes result.media_queries, :print
  end

  def test_minus_operator_updates_media_index_correctly
    # Test that media index IDs are updated when rules are removed
    sheet1 = Cataract.parse_css('.base { color: red; } @media print { .print1 { margin: 10px; } } .middle { padding: 5px; } @media screen { .screen1 { font-size: 16px; } }')
    sheet2 = Cataract.parse_css('.base { color: red; }')

    result = sheet1 - sheet2

    # .base removed (was ID 0), so remaining rules shift down
    assert_equal 3, result.rules.size
    assert_equal '.print1', result.rules[0].selector  # Now ID 0 (was 1)
    assert_equal '.middle', result.rules[1].selector  # Now ID 1 (was 2)
    assert_equal '.screen1', result.rules[2].selector # Now ID 2 (was 3)

    # Media index should have updated IDs
    print_rules = result.with_media(:print).to_a
    assert_equal 1, print_rules.size
    assert_equal 0, print_rules[0].id, 'Media index should reference updated ID'

    screen_rules = result.with_media(:screen).to_a
    assert_equal 1, screen_rules.size
    assert_equal 2, screen_rules[0].id, 'Media index should reference updated ID'
  end

  def test_minus_operator_removes_middle_rule_with_media
    # Remove a rule in the middle and verify IDs update correctly
    sheet1 = Cataract.parse_css('@media print { .first { color: red; } } @media screen { .second { margin: 10px; } } @media print { .third { padding: 5px; } }')
    sheet2 = Cataract.parse_css('@media screen { .second { margin: 10px; } }')

    result = sheet1 - sheet2

    assert_equal 2, result.rules.size
    assert_equal '.first', result.rules[0].selector
    assert_equal '.third', result.rules[1].selector

    # Check media index
    print_rules = result.with_media(:print).to_a
    assert_equal 2, print_rules.size
    assert_equal 0, print_rules[0].id
    assert_equal 1, print_rules[1].id

    # Screen media should be gone
    refute_includes result.media_queries, :screen
  end

  # ============================================================================
  # Stylesheet flattening tests (flatten, cascade)
  # ============================================================================

  def test_flatten_applies_cascade
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.flatten

    assert_equal 1, result.rules.size
    assert result.rules.first.has_property?('color', 'blue'), 'Should apply cascade (last rule wins)'
  end

  def test_flatten_returns_new_stylesheet
    sheet = Cataract.parse_css('.box { color: red; }')

    result = sheet.flatten

    refute_same sheet, result, 'flatten should return new stylesheet'
  end

  def test_flatten_bang_mutates_stylesheet
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')
    original_object_id = sheet.object_id

    result = sheet.flatten!

    assert_same sheet, result, 'flatten! should return self'
    assert_equal original_object_id, sheet.object_id, 'flatten! should mutate in place'
    assert_equal 1, sheet.rules.size
  end

  def test_cascade_alias_for_flatten
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.cascade

    assert_equal 1, result.rules.size
    assert result.rules.first.has_property?('color', 'blue')
  end

  def test_cascade_bang_alias_for_flatten_bang
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.cascade!

    assert_same sheet, result
    assert_equal 1, sheet.rules.size
  end

  def test_merge_alias_still_works
    # Keep for backwards compatibility
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.flatten

    assert_equal 1, result.rules.size
    assert result.rules.first.has_property?('color', 'blue')
  end

  def test_merge_bang_alias_still_works
    # Keep for backwards compatibility
    sheet = Cataract.parse_css('.box { color: red; } .box { color: blue; }')

    result = sheet.flatten!

    assert_same sheet, result
    assert_equal 1, sheet.rules.size
  end
end
