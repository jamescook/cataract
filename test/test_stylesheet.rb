require 'minitest/autorun'
require_relative '../lib/cataract'

class TestStylesheet < Minitest::Test
  # Shared comprehensive fixture covering:
  # - Multiple selectors (element, class, id)
  # - Multiple declarations
  # - Media queries
  # - Important declarations
  COMPREHENSIVE_CSS = <<~CSS.freeze
    body { color: red; margin: 0; }
    .header { padding: 5px; }
    #main { font-size: 14px !important; }
    @media screen {
      body { color: blue; }
      .nav { display: flex; }
    }
    @media print {
      body { color: black; }
    }
  CSS

  def test_stylesheet_to_s
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    assert_includes result, 'body'
    assert_includes result, 'color: red'
    assert_includes result, 'margin: 10px'
  end

  def test_stylesheet_to_s_with_important
    css = 'div { color: blue !important; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    assert_includes result, 'div'
    assert_includes result, 'color: blue !important'
  end

  def test_stylesheet_add_block
    css1 = 'body { color: red; }'
    sheet = Cataract.parse_css(css1)

    assert_equal 1, sheet.size

    sheet.add_block('div { margin: 10px; }')

    assert_equal 2, sheet.size

    result = sheet.to_s

    assert_includes result, 'body'
    assert_includes result, 'color: red'
    assert_includes result, 'div'
    assert_includes result, 'margin: 10px'
  end

  def test_stylesheet_declarations
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)
    declarations = sheet.declarations

    assert_kind_of Array, declarations
    assert(declarations.all?(Cataract::Declarations::Value))
  end

  def test_stylesheet_inspect
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    inspect_str = sheet.inspect

    assert_includes inspect_str, 'Stylesheet'
    assert_includes inspect_str, '2 rules'
  end

  def test_add_block_with_fix_braces
    sheet = Cataract::Stylesheet.new
    sheet.add_block('p { color: red;', fix_braces: true)

    declarations = sheet.find_by_selector('p').first

    assert_kind_of Cataract::Declarations, declarations
    assert_equal 'color: red;', declarations # String comparison via ==
  end

  def test_round_trip
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # Parse the result again
    sheet2 = Cataract.parse_css(result)

    assert_equal sheet.size, sheet2.size
  end

  def test_round_trip_bootstrap
    css = File.read('test/fixtures/bootstrap.css')
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # Should be able to parse the result
    sheet2 = Cataract.parse_css(result)

    assert_predicate sheet2.size, :positive?
  end

  def test_charset_parsing
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_equal 'UTF-8', sheet.charset
    assert_equal 1, sheet.size
  end

  def test_charset_serialization
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # @charset should be first line
    assert_match(/\A@charset "UTF-8";/, result)
    assert_includes result, 'body'
    assert_includes result, 'color: red'
  end

  def test_no_charset
    css = 'body { color: red; }'
    sheet = Cataract.parse_css(css)

    assert_nil sheet.charset
    refute_includes sheet.to_s, '@charset'
  end

  def test_charset_round_trip
    css = '@charset "UTF-8";
.test { margin: 5px; }'
    sheet = Cataract.parse_css(css)
    result = sheet.to_s

    # Parse again and verify charset preserved
    sheet2 = Cataract.parse_css(result)

    assert_equal 'UTF-8', sheet2.charset
    assert_equal 1, sheet2.size
  end

  def test_bootstrap_charset
    css = File.read('test/fixtures/bootstrap.css')
    sheet = Cataract.parse_css(css)

    # Bootstrap starts with @charset "UTF-8"
    assert_equal 'UTF-8', sheet.charset

    # Verify it's preserved in serialization
    result = sheet.to_s

    assert_match(/\A@charset "UTF-8";/, result)
  end

  # ============================================================================
  # each_selector - Iterator tests
  # ============================================================================

  def test_each_selector_basic
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector do |selector, _declarations, _specificity, _media_types|
      selectors << selector
    end

    assert_equal %w[body div], selectors
  end

  def test_each_selector_yields_all_components
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract.parse_css(css)

    sheet.each_selector do |selector, declarations, specificity, media_types|
      assert_equal 'body', selector
      assert_kind_of Cataract::Declarations, declarations
      assert declarations.key?('color')
      assert declarations.key?('margin')
      assert_equal 'red', declarations['color']
      assert_equal '10px', declarations['margin']
      assert_kind_of Integer, specificity
      assert_equal [:all], media_types
    end
  end

  def test_each_selector_with_important
    css = 'div { color: blue !important; }'
    sheet = Cataract.parse_css(css)

    sheet.each_selector do |_selector, declarations, _specificity, _media_types|
      assert declarations.important?('color')
      assert_equal 'blue !important', declarations['color']
    end
  end

  def test_each_selector_returns_enumerator
    css = 'body { color: red; } div { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    enum = sheet.each_selector

    assert_kind_of Enumerator, enum
    assert_equal 2, enum.count
  end

  def test_each_selector_with_media_all
    css = <<~CSS
      body { color: black; }
      @media print {
        body { color: white; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :all) do |selector, _declarations, _specificity, media_types|
      selectors << [selector, media_types]
    end

    # :all should return ALL rules
    assert_equal 2, selectors.length
    assert_equal ['body', [:all]], selectors[0]
    assert_equal ['body', [:print]], selectors[1]
  end

  def test_each_selector_with_media_print
    css = <<~CSS
      body { color: black; }
      @media print {
        body { color: white; }
      }
      @media screen {
        div { color: blue; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :print) do |selector, _declarations, _specificity, media_types|
      selectors << [selector, media_types]
    end

    # :print should return ONLY print-specific rules (not universal)
    assert_equal 1, selectors.length
    assert_equal ['body', [:print]], selectors[0]
  end

  def test_each_selector_with_media_screen
    css = <<~CSS
      body { color: black; }
      @media screen {
        div { color: blue; }
      }
      @media print {
        body { color: white; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :screen) do |selector, _declarations, _specificity, media_types|
      selectors << [selector, media_types]
    end

    # :screen should return ONLY screen-specific rules
    assert_equal 1, selectors.length
    assert_equal ['div', [:screen]], selectors[0]
  end

  def test_each_selector_with_multiple_media_types
    css = <<~CSS
      @media screen, print {
        .header { color: black; }
      }
      @media print {
        body { margin: 0; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    # Query for both screen and print
    selectors = []
    sheet.each_selector(media: %i[screen print]) do |selector, _declarations, _specificity, _media_types|
      selectors << selector
    end

    assert_equal 2, selectors.length
    assert_includes selectors, '.header'
    assert_includes selectors, 'body'
  end

  def test_each_selector_no_matches
    css = '@media print { body { color: black; } }'
    sheet = Cataract.parse_css(css)

    selectors = []
    sheet.each_selector(media: :screen) do |selector, _declarations, _specificity, _media_types|
      selectors << selector
    end

    assert_empty selectors
  end

  # ============================================================================
  # each_selector with specificity filtering - New feature
  # ============================================================================

  def test_each_selector_with_specificity_exact
    css = <<~CSS
      body { color: red; }
      div { margin: 10px; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity = 1 (element selectors: body, div)
    matches = []
    sheet.each_selector(specificity: 1) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, 'div'
  end

  def test_each_selector_with_specificity_range
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
      #main .btn { margin: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity 10-100 (class and single ID)
    matches = []
    sheet.each_selector(specificity: 10..100) do |selector, _declarations, specificity, _media_types|
      matches << [selector, specificity]
    end

    assert_equal 2, matches.length
    assert_includes matches, ['.header', 10]
    assert_includes matches, ['#main', 100]
  end

  def test_each_selector_with_specificity_open_ended_range
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
      #main .btn { margin: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity >= 100 (high specificity)
    matches = []
    sheet.each_selector(specificity: 100..) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, '#main'
    assert_includes matches, '#main .btn'
  end

  def test_each_selector_with_specificity_upper_bound
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      #main { font-size: 14px; }
      #main .btn { margin: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find rules with specificity <= 10 (low specificity)
    matches = []
    sheet.each_selector(specificity: ..10) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, '.header'
  end

  def test_each_selector_with_specificity_and_media
    css = <<~CSS
      body { color: black; }
      .header { padding: 5px; }
      @media screen {
        body { color: blue; }
        #main { font-size: 20px; }
      }
      @media print {
        .footer { margin: 0; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    # Find low-specificity rules (<=10) in screen media
    matches = []
    sheet.each_selector(specificity: ..10, media: :screen) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 1, matches.length
    assert_equal 'body', matches[0]
  end

  def test_each_selector_with_specificity_no_matches
    css = 'body { color: red; } .header { margin: 10px; }'
    sheet = Cataract.parse_css(css)

    matches = []
    sheet.each_selector(specificity: 100..) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_empty matches
  end

  def test_each_selector_with_specificity_returns_enumerator
    css = 'body { color: red; } .header { margin: 10px; } #main { padding: 5px; }'
    sheet = Cataract.parse_css(css)

    enum = sheet.each_selector(specificity: 100..)

    assert_kind_of Enumerator, enum
    assert_equal 1, enum.count
  end

  # ============================================================================
  # each_selector with property filtering - New feature
  # ============================================================================

  def test_each_selector_with_property_filter
    css = <<~CSS
      body { color: red; margin: 0; }
      .header { padding: 5px; }
      #main { color: blue; font-size: 14px; }
      .footer { position: relative; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find any selector with 'color' property
    matches = []
    sheet.each_selector(property: 'color') do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, '#main'
  end

  def test_each_selector_with_property_value_filter
    css = <<~CSS
      body { position: absolute; }
      .header { position: relative; }
      #main { position: relative; z-index: 10; }
      .footer { display: relative; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find any selector with ANY property that has value 'relative'
    matches = []
    sheet.each_selector(property_value: 'relative') do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 3, matches.length
    assert_includes matches, '.header'
    assert_includes matches, '#main'
    assert_includes matches, '.footer'
  end

  def test_each_selector_with_property_and_value_filter
    css = <<~CSS
      body { position: absolute; }
      .header { position: relative; }
      #main { position: relative; z-index: 10; }
      .footer { display: relative; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find selectors with specifically 'position: relative'
    matches = []
    sheet.each_selector(property: 'position',
                        property_value: 'relative') do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, '.header'
    assert_includes matches, '#main'
    refute_includes matches, '.footer'
  end

  def test_each_selector_with_property_filter_no_matches
    css = 'body { margin: 0; } .header { padding: 5px; }'
    sheet = Cataract.parse_css(css)

    matches = []
    sheet.each_selector(property: 'color') do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_empty matches
  end

  def test_each_selector_with_property_and_media_filter
    css = <<~CSS
      body { color: red; }
      .header { padding: 5px; }
      @media screen {
        body { color: blue; }
        #main { font-size: 20px; }
      }
      @media print {
        .footer { color: black; }
      }
    CSS
    sheet = Cataract.parse_css(css)

    # Find selectors with 'color' in screen media
    matches = []
    sheet.each_selector(property: 'color', media: :screen) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 1, matches.length
    assert_equal 'body', matches[0]
  end

  def test_each_selector_with_property_and_specificity_filter
    css = <<~CSS
      body { color: red; }
      .header { color: blue; }
      #main { color: green; font-size: 14px; }
      #main .btn { padding: 10px; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find high-specificity selectors (>= 100) with 'color' property
    matches = []
    sheet.each_selector(property: 'color', specificity: 100..) do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 1, matches.length
    assert_equal '#main', matches[0]
  end

  def test_each_selector_with_important_property_value
    css = <<~CSS
      body { color: red !important; }
      .header { color: blue; }
      #main { color: red; }
    CSS
    sheet = Cataract.parse_css(css)

    # Find selectors with 'color: red' (should match both with and without !important)
    matches = []
    sheet.each_selector(property: 'color',
                        property_value: 'red') do |selector, _declarations, _specificity, _media_types|
      matches << selector
    end

    assert_equal 2, matches.length
    assert_includes matches, 'body'
    assert_includes matches, '#main'
  end

  # ============================================================================
  # to_formatted_s - Formatted output tests
  # ============================================================================

  def test_to_formatted_s_basic
    input = 'div p { color: red }'
    expected = <<~CSS
      div p {
        color: red;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s

    assert_equal expected, output
  end

  def test_to_formatted_s_multiple_declarations
    input = 'body { color: red; margin: 0; padding: 10px }'
    expected = <<~CSS
      body {
        color: red; margin: 0; padding: 10px;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s

    assert_equal expected, output
  end

  def test_to_formatted_s_multiple_rules
    input = 'body { color: red } .btn { padding: 10px }'
    expected = <<~CSS
      body {
        color: red;
      }
      .btn {
        padding: 10px;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s

    assert_equal expected, output
  end

  def test_to_formatted_s_with_media_query
    input = '@media (min-width: 768px) { .container { width: 750px } }'
    expected = <<~CSS
      @media (min-width: 768px) {
        .container {
          width: 750px;
        }
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s

    assert_equal expected, output
  end

  def test_to_formatted_s_with_charset
    input = '@charset "UTF-8"; body { color: red }'
    expected = <<~CSS
      @charset "UTF-8";
      body {
        color: red;
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s

    assert_equal expected, output
  end

  def test_to_formatted_s_mixed_media_and_universal
    input = 'body { margin: 0 } @media (min-width: 768px) { .container { width: 750px } .btn { padding: 10px } }'
    expected = <<~CSS
      body {
        margin: 0;
      }
      @media (min-width: 768px) {
        .container {
          width: 750px;
        }
        .btn {
          padding: 10px;
        }
      }
    CSS

    output = Cataract.parse_css(input).to_formatted_s

    assert_equal expected, output
  end

  def test_finding_by_selector
    css = <<-CSS
      html, body, p { margin: 0px; }
      p { padding: 0px; }
      #content { font: 12px/normal sans-serif; }
      .content { color: red; }
    CSS

    stylesheet = Cataract::Stylesheet.parse(css)

    # find_by_selector returns array of Declarations objects
    body_decls = stylesheet.find_by_selector('body')

    assert_equal 1, body_decls.size
    assert_equal 'margin: 0px;', body_decls.first

    p_decls = stylesheet.find_by_selector('p')

    assert_equal 2, p_decls.size
    # Compare using Declarations objects
    assert_equal Cataract::Declarations.new('margin: 0px'), p_decls[0]
    assert_equal Cataract::Declarations.new('padding: 0px'), p_decls[1]

    assert_equal 'color: red;', stylesheet.find_by_selector('.content').first
    assert_equal 'font: 12px/normal sans-serif;', stylesheet.find_by_selector('#content').first
  end

  # ============================================================================
  # Mutation tests - add_rule, add_rule_set!, remove_rule_set!
  # ============================================================================

  def test_adding_a_rule
    sheet = Cataract::Stylesheet.new
    sheet.add_rule(selector: 'div', declarations: 'color: blue')

    assert_equal 'color: blue;', sheet.find_by_selector('div').first
  end

  def test_adding_a_rule_set
    sheet = Cataract::Stylesheet.new
    rs = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    sheet.add_rule_set!(rs)

    assert_equal 'color: blue;', sheet.find_by_selector('div').first
  end

  def test_removing_a_rule_set
    sheet = Cataract::Stylesheet.new
    rs = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    sheet.add_rule_set!(rs)
    rs2 = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    sheet.remove_rule_set!(rs2)

    assert_empty sheet.find_by_selector('div')
  end

  def test_converting_to_hash
    sheet = Cataract::Stylesheet.new
    rs = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    sheet.add_rule_set!(rs)
    hash = sheet.to_h

    assert_equal 'blue', hash['all']['div']['color']
  end

  # ============================================================================
  # Additional Parser methods - clear!, selectors, each_rule_set, etc.
  # ============================================================================

  def test_clear
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)

    assert_equal 6, sheet.size

    sheet.clear!

    assert_equal 0, sheet.size
    assert_empty sheet
    assert_nil sheet.charset
  end

  def test_selectors_all
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)
    sels = sheet.selectors(:all)

    assert_equal 6, sels.length
    assert_includes sels, 'body'
    assert_includes sels, '.header'
    assert_includes sels, '#main'
    assert_includes sels, '.nav'
  end

  def test_selectors_with_media_filter
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)
    screen_sels = sheet.selectors(:screen)

    assert_equal 2, screen_sels.length
    assert_includes screen_sels, 'body'
    assert_includes screen_sels, '.nav'
  end

  def test_each_rule_set
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)
    rule_sets = []

    sheet.each_rule_set(:all) do |rule_set, media_types|
      rule_sets << [rule_set.selector, media_types]
    end

    assert_equal 6, rule_sets.length
  end

  def test_each_rule_set_with_media_filter
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)
    rule_sets = []

    sheet.each_rule_set(:print) do |rule_set, _media_types|
      rule_sets << rule_set.selector
    end

    assert_equal 1, rule_sets.length
    assert_includes rule_sets, 'body'
  end

  def test_find_rule_sets
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)
    rule_sets = sheet.find_rule_sets(['body', '.header'])

    assert_equal 4, rule_sets.length # body appears 3 times (universal, screen, print)
    selectors = rule_sets.map(&:selector)

    assert_includes selectors, 'body'
    assert_includes selectors, '.header'
  end

  def test_to_css_alias
    sheet = Cataract::Stylesheet.parse('body { color: red; }')

    assert_respond_to sheet, :to_css
    assert_equal sheet.to_s, sheet.to_css
  end

  def test_rules_count_alias
    sheet = Cataract::Stylesheet.parse(COMPREHENSIVE_CSS)

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
      assert_includes sheet.selectors, '.test'
    end
  end

  def test_load_uri_class_method
    require 'webmock/minitest'

    stub_request(:get, 'https://example.com/style.css')
      .to_return(body: '.remote { color: blue; }', status: 200)

    sheet = Cataract::Stylesheet.load_uri('https://example.com/style.css')

    assert_instance_of Cataract::Stylesheet, sheet
    assert_equal 1, sheet.size
    assert_includes sheet.selectors, '.remote'
  end

  def test_parse_with_import_option_in_constructor
    require 'tempfile'
    require 'webmock/minitest'

    # Create a temporary CSS file to import
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: green; }')

      # CSS with @import
      css = "@import url('file://#{imported_file}');\n.main { color: red; }"

      # Create stylesheet with import option in constructor
      sheet = Cataract::Stylesheet.new(import: { allowed_schemes: ['file'], extensions: ['css'] })
      sheet.parse(css)

      # Should have both imported and main rules
      assert_equal 2, sheet.size
      assert_includes sheet.selectors, '.imported'
      assert_includes sheet.selectors, '.main'
    end
  end
end
