# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'
require 'css_parser'
require 'webmock/minitest'
require 'tempfile'

# Tests for css_parser gem API compatibility
# Each test compares Cataract's behavior against CssParser gem to ensure compatibility
class TestCssParserCompat < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
    @css_parser = CssParser::Parser.new
  end

  # ============================================================================
  # load_string! - Basic parsing
  # ============================================================================

  def test_load_string
    @parser.load_string! 'a { color: red }'

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'a'
  end

  def test_load_string_accumulates
    @parser.load_string! 'a { color: red }'
    @parser.load_string! 'b { color: blue }'

    assert_equal 2, @parser.rules_count
    assert_includes @parser.selectors, 'a'
    assert_includes @parser.selectors, 'b'
  end

  # ============================================================================
  # load_file! - Local file loading
  # ============================================================================

  def test_load_file_basic
    Tempfile.create(['test', '.css']) do |f|
      f.write('.header { font-size: 20px }')
      f.flush

      @parser.load_file!(f.path)

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, '.header'
    end
  end

  def test_load_file_with_base_dir
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, 'style.css')
      File.write(file_path, '.footer { margin: 0 }')

      @parser.load_file!('style.css', dir)

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, '.footer'
    end
  end

  def test_load_file_not_found
    assert_raises(IOError) do
      @parser.load_file!('nonexistent.css')
    end
  end

  def test_load_file_not_found_with_io_exceptions_false
    parser = Cataract::Parser.new(io_exceptions: false)

    # Should not raise, just return self
    result = parser.load_file!('nonexistent.css')

    assert_equal parser, result
    assert_equal 0, parser.rules_count
  end

  # ============================================================================
  # load_uri! - HTTP loading
  # ============================================================================

  def test_load_uri_http
    stub_request(:get, 'http://example.com/style.css')
      .to_return(body: 'body { margin: 0 }')

    @parser.load_uri!('http://example.com/style.css')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, 'body'
  end

  def test_load_uri_https
    stub_request(:get, 'https://example.com/style.css')
      .to_return(body: '.container { width: 100% }')

    @parser.load_uri!('https://example.com/style.css')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, '.container'
  end

  def test_load_uri_http_error
    stub_request(:get, 'http://example.com/missing.css')
      .to_return(status: 404)

    assert_raises(IOError) do
      @parser.load_uri!('http://example.com/missing.css')
    end
  end

  def test_load_uri_http_error_with_io_exceptions_false
    stub_request(:get, 'http://example.com/missing.css')
      .to_return(status: 404)

    parser = Cataract::Parser.new(io_exceptions: false)
    result = parser.load_uri!('http://example.com/missing.css')

    assert_equal parser, result
    assert_equal 0, parser.rules_count
  end

  # ============================================================================
  # load_uri! - File URI loading
  # ============================================================================

  def test_load_uri_file_scheme
    Tempfile.create(['test', '.css']) do |f|
      f.write('h1 { font-weight: bold }')
      f.flush

      @parser.load_uri!("file://#{f.path}")

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, 'h1'
    end
  end

  def test_load_uri_relative_path
    Tempfile.create(['test', '.css']) do |f|
      f.write('p { line-height: 1.5 }')
      f.flush

      @parser.load_uri!(f.path)

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, 'p'
    end
  end

  # ============================================================================
  # Multiple loads accumulate
  # ============================================================================

  def test_multiple_loads_accumulate
    stub_request(:get, 'http://example.com/base.css')
      .to_return(body: 'body { margin: 0 }')

    Tempfile.create(['local', '.css']) do |f|
      f.write('.header { color: blue }')
      f.flush

      @parser.load_uri!('http://example.com/base.css')
      @parser.load_file!(f.path)
      @parser.load_string! '.footer { padding: 10px }'

      assert_equal 3, @parser.rules_count
      assert_includes @parser.selectors, 'body'
      assert_includes @parser.selectors, '.header'
      assert_includes @parser.selectors, '.footer'
    end
  end

  # ============================================================================
  # find_by_selector - css_parser gem API examples
  # ============================================================================

  def test_find_by_selector_basic
    @parser.load_string! '#content { font-size: 13px; line-height: 1.2 }'

    result = @parser.find_by_selector('#content')

    assert_equal ['font-size: 13px; line-height: 1.2;'], result
  end

  def test_find_by_selector_with_media_types_array
    css = %(
      @media screen, handheld {
        #content { font-size: 13px; line-height: 1.2 }
      }
    )
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    result = @parser.find_by_selector('#content', %i[screen handheld])
    expected = @css_parser.find_by_selector('#content', %i[screen handheld])

    # Verify we got the expected value (not nil/empty)
    assert_equal ['font-size: 13px; line-height: 1.2;'], result
    # Verify we match css_parser
    assert_equal expected, result
  end

  def test_find_by_selector_with_media_type_symbol
    css = %(
      @media print {
        #content { font-size: 11pt; line-height: 1.2 }
      }
    )
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    result = @parser.find_by_selector('#content', :print)
    expected = @css_parser.find_by_selector('#content', :print)

    # Verify we got the expected value (not nil/empty)
    assert_equal ['font-size: 11pt; line-height: 1.2;'], result
    # Verify we match css_parser
    assert_equal expected, result
  end

  def test_find_by_selector_multiple_rules_same_selector
    css = %(
      #content { font-size: 13px }
      #content { line-height: 1.2 }
    )
    @parser.load_string!(css)

    result = @parser.find_by_selector('#content')

    assert_equal ['font-size: 13px;', 'line-height: 1.2;'], result
  end

  def test_find_by_selector_bracket_alias
    @parser.load_string! '.header { color: blue }'

    # Test [] alias
    result = @parser['.header']

    assert_equal ['color: blue;'], result
  end

  def test_find_by_selector_no_match
    @parser.load_string! 'body { margin: 0 }'

    result = @parser.find_by_selector('#nonexistent')

    assert_empty result
  end

  def test_find_by_selector_wrong_media_type
    css = %(
      @media print {
        body { margin: 0 }
      }
    )
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    # Query for screen media type when rule is print-only
    result = @parser.find_by_selector('body', :screen)
    expected = @css_parser.find_by_selector('body', :screen)

    # Verify we got empty result (not nil)
    assert_empty result
    # Verify we match css_parser
    assert_equal expected, result
  end

  # ============================================================================
  # each_rule_set - Iterate through RuleSets
  # ============================================================================

  def test_each_rule_set_basic
    @parser.load_string! 'body { margin: 0 } .header { color: blue }'

    rule_sets = []
    @parser.each_rule_set do |rule_set, _media_types|
      rule_sets << rule_set
    end

    assert_equal 2, rule_sets.length
    assert_equal ['body', '.header'], rule_sets.map(&:selector)
  end

  def test_each_rule_set_with_media_filter
    css = %(
      body { margin: 0 }
      @media print {
        body { margin: 1in }
      }
    )
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    # Compare Cataract
    cataract_rule_sets = []
    @parser.each_rule_set(:print) do |rule_set, _media_types|
      cataract_rule_sets << rule_set
    end

    # Compare css_parser
    css_parser_rule_sets = []
    @css_parser.each_rule_set(:print) do |rule_set, _media_types|
      css_parser_rule_sets << rule_set
    end

    # Verify we got expected values (only print-specific rule, not universal)
    assert_equal 1, cataract_rule_sets.length
    assert_equal 'body', cataract_rule_sets.first.selector
    assert_equal [:print], cataract_rule_sets.first.media_types
    # Verify we match css_parser
    assert_equal css_parser_rule_sets.length, cataract_rule_sets.length
  end

  def test_each_rule_set_returns_enumerator
    @parser.load_string! 'a { color: red }'

    enum = @parser.each_rule_set

    assert_kind_of Enumerator, enum
    assert_equal 1, enum.count
  end

  # ============================================================================
  # find_rule_sets - Find RuleSets by selectors
  # ============================================================================

  def test_find_rule_sets_single_selector
    @parser.load_string! 'body { margin: 0 } .header { color: blue }'

    rule_sets = @parser.find_rule_sets(['body'])

    assert_equal 1, rule_sets.length
    assert_equal 'body', rule_sets.first.selector
  end

  def test_find_rule_sets_multiple_selectors
    @parser.load_string! 'body { margin: 0 } .header { color: blue } .footer { padding: 10px }'

    rule_sets = @parser.find_rule_sets(['body', '.footer'])

    assert_equal 2, rule_sets.length
    assert_equal ['body', '.footer'], rule_sets.map(&:selector)
  end

  def test_find_rule_sets_with_media_filter
    css = %(
      body { margin: 0 }
      @media print {
        body { margin: 1in }
        .header { display: none }
      }
    )
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    cataract_rule_sets = @parser.find_rule_sets(['body'], :print)
    css_parser_rule_sets = @css_parser.find_rule_sets(['body'], :print)

    # Verify we got expected values (only print-specific rule, not universal)
    assert_equal 1, cataract_rule_sets.length
    assert_equal 'body', cataract_rule_sets.first.selector
    assert_equal [:print], cataract_rule_sets.first.media_types
    # Verify we match css_parser
    assert_equal css_parser_rule_sets.length, cataract_rule_sets.length
  end

  def test_find_rule_sets_normalizes_whitespace
    @parser.load_string! 'div   p { color: red }'

    # Should normalize whitespace in selector search
    rule_sets = @parser.find_rule_sets(['div p'])

    assert_equal 1, rule_sets.length
  end

  def test_find_rule_sets_no_duplicates
    @parser.load_string! 'body { margin: 0 }'

    # Asking for same selector multiple times shouldn't duplicate
    rule_sets = @parser.find_rule_sets(%w[body body])

    assert_equal 1, rule_sets.length
  end

  def test_find_rule_sets_no_matches
    @parser.load_string! 'body { margin: 0 }'

    rule_sets = @parser.find_rule_sets(['.nonexistent'])

    assert_empty rule_sets
  end

  # ============================================================================
  # expand_shorthand - Shorthand property expansion (css_parser compat)
  # ============================================================================

  # Helper to expand shorthand using css_parser
  def css_parser_expand(shorthand)
    ruleset = CssParser::RuleSet.new(block: shorthand)
    ruleset.expand_shorthand!
    result = {}
    ruleset.each_declaration { |prop, val, _imp| result[prop] = val }
    result
  end

  def test_expand_shorthand_margin_variants
    # Test various shorthand forms (from css_parser tests)
    ['margin: 0px auto', 'margin: 0px auto 0px', 'margin: 0px auto 0px auto'].each do |shorthand|
      our_result = @parser.expand_shorthand(shorthand)
      css_parser_result = css_parser_expand(shorthand)

      # Check specific values
      assert_equal '0px', our_result['margin-top']
      assert_equal 'auto', our_result['margin-right']
      assert_equal '0px', our_result['margin-bottom']
      assert_equal 'auto', our_result['margin-left']

      # Verify we match css_parser
      assert_equal css_parser_result['margin-top'], our_result['margin-top']
      assert_equal css_parser_result['margin-right'], our_result['margin-right']
      assert_equal css_parser_result['margin-bottom'], our_result['margin-bottom']
      assert_equal css_parser_result['margin-left'], our_result['margin-left']
    end
  end

  def test_expand_shorthand_margin_various_units
    # Test various units (from css_parser tests)
    ['em', 'ex', 'in', 'px', 'pt', 'pc', '%'].each do |unit|
      shorthand = "margin: 0% -0.123#{unit} 9px -.9pc"
      our_result = @parser.expand_shorthand(shorthand)
      css_parser_result = css_parser_expand(shorthand)

      # Check specific values
      assert_equal '0%', our_result['margin-top']
      assert_equal "-0.123#{unit}", our_result['margin-right']
      assert_equal '9px', our_result['margin-bottom']
      assert_equal '-.9pc', our_result['margin-left']

      # Verify we match css_parser
      assert_equal css_parser_result['margin-top'], our_result['margin-top']
      assert_equal css_parser_result['margin-right'], our_result['margin-right']
      assert_equal css_parser_result['margin-bottom'], our_result['margin-bottom']
      assert_equal css_parser_result['margin-left'], our_result['margin-left']
    end
  end

  def test_expand_shorthand_border
    shorthand = 'border: 1px solid red'
    our_result = @parser.expand_shorthand(shorthand)
    css_parser_result = css_parser_expand(shorthand)

    # Check specific values
    assert_equal '1px', our_result['border-top-width']
    assert_equal 'solid', our_result['border-bottom-style']
    assert_equal 'red', our_result['border-left-color']

    # Verify we match css_parser
    assert_equal css_parser_result['border-top-width'], our_result['border-top-width']
    assert_equal css_parser_result['border-bottom-style'], our_result['border-bottom-style']
    assert_equal css_parser_result['border-left-color'], our_result['border-left-color']
  end

  def test_expand_shorthand_border_color_4_values
    shorthand = 'border-color: #000000 #bada55 #ffffff #ff0000'
    our_result = @parser.expand_shorthand(shorthand)
    css_parser_result = css_parser_expand(shorthand)

    # Check specific values
    assert_equal '#000000', our_result['border-top-color']
    assert_equal '#bada55', our_result['border-right-color']
    assert_equal '#ffffff', our_result['border-bottom-color']
    assert_equal '#ff0000', our_result['border-left-color']

    # Verify we match css_parser
    assert_equal css_parser_result['border-top-color'], our_result['border-top-color']
    assert_equal css_parser_result['border-right-color'], our_result['border-right-color']
    assert_equal css_parser_result['border-bottom-color'], our_result['border-bottom-color']
    assert_equal css_parser_result['border-left-color'], our_result['border-left-color']
  end

  def test_expand_shorthand_border_color_3_values
    shorthand = 'border-color: #000000 #bada55 #ffffff'
    our_result = @parser.expand_shorthand(shorthand)
    css_parser_result = css_parser_expand(shorthand)

    # Check specific values
    assert_equal '#000000', our_result['border-top-color']
    assert_equal '#bada55', our_result['border-right-color']
    assert_equal '#ffffff', our_result['border-bottom-color']
    assert_equal '#bada55', our_result['border-left-color']

    # Verify we match css_parser
    assert_equal css_parser_result['border-top-color'], our_result['border-top-color']
    assert_equal css_parser_result['border-right-color'], our_result['border-right-color']
    assert_equal css_parser_result['border-bottom-color'], our_result['border-bottom-color']
    assert_equal css_parser_result['border-left-color'], our_result['border-left-color']
  end

  def test_expand_shorthand_border_color_2_values
    shorthand = 'border-color: #000000 #bada55'
    our_result = @parser.expand_shorthand(shorthand)
    css_parser_result = css_parser_expand(shorthand)

    # Check specific values
    assert_equal '#000000', our_result['border-top-color']
    assert_equal '#bada55', our_result['border-right-color']
    assert_equal '#000000', our_result['border-bottom-color']
    assert_equal '#bada55', our_result['border-left-color']

    # Verify we match css_parser
    assert_equal css_parser_result['border-top-color'], our_result['border-top-color']
    assert_equal css_parser_result['border-right-color'], our_result['border-right-color']
    assert_equal css_parser_result['border-bottom-color'], our_result['border-bottom-color']
    assert_equal css_parser_result['border-left-color'], our_result['border-left-color']
  end

  def test_expand_shorthand_font_size_various_units
    # Test various units (from css_parser tests)
    ['em', 'ex', 'in', 'px', 'pt', 'pc', '%'].each do |unit|
      shorthand = "font: 300 italic 11.25#{unit}/14px verdana, helvetica, sans-serif"
      our_result = @parser.expand_shorthand(shorthand)
      css_parser_result = css_parser_expand(shorthand)

      # Check specific value
      assert_equal "11.25#{unit}", our_result['font-size']

      # Verify we match css_parser
      assert_equal css_parser_result['font-size'], our_result['font-size']
    end
  end

  def test_expand_shorthand_font_size_keywords
    # Test size keywords (from css_parser tests)
    %w[smaller small medium large x-large].each do |keyword|
      shorthand = "font: 300 italic #{keyword}/14px verdana, helvetica, sans-serif"
      our_result = @parser.expand_shorthand(shorthand)
      css_parser_result = css_parser_expand(shorthand)

      # Check specific value
      assert_equal keyword, our_result['font-size']

      # Verify we match css_parser
      assert_equal css_parser_result['font-size'], our_result['font-size']
    end
  end

  def test_expand_shorthand_font_weight_values
    # Test various font weights (from css_parser tests)
    %w[300 bold bolder lighter normal].each do |weight|
      shorthand = "font: #{weight} italic 12px sans-serif"
      our_result = @parser.expand_shorthand(shorthand)
      css_parser_result = css_parser_expand(shorthand)

      # Check specific value
      assert_equal weight, our_result['font-weight']

      # Verify we match css_parser
      assert_equal css_parser_result['font-weight'], our_result['font-weight']
    end
  end

  def test_expand_shorthand_font_weight_defaults_to_normal
    # Ensure normal is the default (from css_parser tests)
    ['font: normal italic 12px sans-serif', 'font: italic 12px sans-serif',
     'font: small-caps normal 12px sans-serif', 'font: 12px/16px sans-serif'].each do |shorthand|
      our_result = @parser.expand_shorthand(shorthand)
      css_parser_result = css_parser_expand(shorthand)

      # Check specific value
      assert_equal 'normal', our_result['font-weight']

      # Verify we match css_parser
      assert_equal css_parser_result['font-weight'], our_result['font-weight']
    end
  end

  def test_expand_shorthand_font_families_with_quotes
    shorthand = "font: 300 italic 12px/14px \"Helvetica-Neue-Light 45\", 'verdana', helvetica, sans-serif"
    our_result = @parser.expand_shorthand(shorthand)
    css_parser_result = css_parser_expand(shorthand)

    # Check specific value
    assert_equal "\"Helvetica-Neue-Light 45\", 'verdana', helvetica, sans-serif", our_result['font-family']

    # Verify we match css_parser
    assert_equal css_parser_result['font-family'], our_result['font-family']
  end
end
