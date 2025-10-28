require "minitest/autorun"
require "cataract"
require "css_parser"
require "webmock/minitest"
require "tempfile"

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
    @parser.load_string! "a { color: red }"

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "a"
  end

  def test_load_string_accumulates
    @parser.load_string! "a { color: red }"
    @parser.load_string! "b { color: blue }"

    assert_equal 2, @parser.rules_count
    assert_includes @parser.selectors, "a"
    assert_includes @parser.selectors, "b"
  end

  # ============================================================================
  # load_file! - Local file loading
  # ============================================================================

  def test_load_file_basic
    Tempfile.create(['test', '.css']) do |f|
      f.write(".header { font-size: 20px }")
      f.flush

      @parser.load_file!(f.path)

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, ".header"
    end
  end

  def test_load_file_with_base_dir
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, 'style.css')
      File.write(file_path, ".footer { margin: 0 }")

      @parser.load_file!('style.css', dir)

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, ".footer"
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
    stub_request(:get, "http://example.com/style.css")
      .to_return(body: "body { margin: 0 }")

    @parser.load_uri!('http://example.com/style.css')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, "body"
  end

  def test_load_uri_https
    stub_request(:get, "https://example.com/style.css")
      .to_return(body: ".container { width: 100% }")

    @parser.load_uri!('https://example.com/style.css')

    assert_equal 1, @parser.rules_count
    assert_includes @parser.selectors, ".container"
  end

  def test_load_uri_http_error
    stub_request(:get, "http://example.com/missing.css")
      .to_return(status: 404)

    assert_raises(IOError) do
      @parser.load_uri!('http://example.com/missing.css')
    end
  end

  def test_load_uri_http_error_with_io_exceptions_false
    stub_request(:get, "http://example.com/missing.css")
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
      f.write("h1 { font-weight: bold }")
      f.flush

      @parser.load_uri!("file://#{f.path}")

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, "h1"
    end
  end

  def test_load_uri_relative_path
    Tempfile.create(['test', '.css']) do |f|
      f.write("p { line-height: 1.5 }")
      f.flush

      @parser.load_uri!(f.path)

      assert_equal 1, @parser.rules_count
      assert_includes @parser.selectors, "p"
    end
  end

  # ============================================================================
  # Multiple loads accumulate
  # ============================================================================

  def test_multiple_loads_accumulate
    stub_request(:get, "http://example.com/base.css")
      .to_return(body: "body { margin: 0 }")

    Tempfile.create(['local', '.css']) do |f|
      f.write(".header { color: blue }")
      f.flush

      @parser.load_uri!('http://example.com/base.css')
      @parser.load_file!(f.path)
      @parser.load_string! ".footer { padding: 10px }"

      assert_equal 3, @parser.rules_count
      assert_includes @parser.selectors, "body"
      assert_includes @parser.selectors, ".header"
      assert_includes @parser.selectors, ".footer"
    end
  end

  # ============================================================================
  # find_by_selector - css_parser gem API examples
  # ============================================================================

  def test_find_by_selector_basic
    @parser.load_string! "#content { font-size: 13px; line-height: 1.2 }"

    result = @parser.find_by_selector('#content')

    assert_equal ['font-size: 13px; line-height: 1.2;'], result
  end

  def test_find_by_selector_with_media_types_array
    css = %{
      @media screen, handheld {
        #content { font-size: 13px; line-height: 1.2 }
      }
    }
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    result = @parser.find_by_selector('#content', [:screen, :handheld])
    expected = @css_parser.find_by_selector('#content', [:screen, :handheld])

    # Verify we got the expected value (not nil/empty)
    assert_equal ['font-size: 13px; line-height: 1.2;'], result
    # Verify we match css_parser
    assert_equal expected, result
  end

  def test_find_by_selector_with_media_type_symbol
    css = %{
      @media print {
        #content { font-size: 11pt; line-height: 1.2 }
      }
    }
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
    css = %{
      #content { font-size: 13px }
      #content { line-height: 1.2 }
    }
    @parser.load_string!(css)

    result = @parser.find_by_selector('#content')

    assert_equal ['font-size: 13px;', 'line-height: 1.2;'], result
  end

  def test_find_by_selector_bracket_alias
    @parser.load_string! ".header { color: blue }"

    # Test [] alias
    result = @parser['.header']

    assert_equal ['color: blue;'], result
  end

  def test_find_by_selector_no_match
    @parser.load_string! "body { margin: 0 }"

    result = @parser.find_by_selector('#nonexistent')

    assert_equal [], result
  end

  def test_find_by_selector_wrong_media_type
    css = %{
      @media print {
        body { margin: 0 }
      }
    }
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    # Query for screen media type when rule is print-only
    result = @parser.find_by_selector('body', :screen)
    expected = @css_parser.find_by_selector('body', :screen)

    # Verify we got empty result (not nil)
    assert_equal [], result
    # Verify we match css_parser
    assert_equal expected, result
  end

  # ============================================================================
  # each_rule_set - Iterate through RuleSets
  # ============================================================================

  def test_each_rule_set_basic
    @parser.load_string! "body { margin: 0 } .header { color: blue }"

    rule_sets = []
    @parser.each_rule_set do |rule_set, media_types|
      rule_sets << rule_set
    end

    assert_equal 2, rule_sets.length
    assert_equal ["body", ".header"], rule_sets.map(&:selector)
  end

  def test_each_rule_set_with_media_filter
    css = %{
      body { margin: 0 }
      @media print {
        body { margin: 1in }
      }
    }
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    # Compare Cataract
    cataract_rule_sets = []
    @parser.each_rule_set(:print) do |rule_set, media_types|
      cataract_rule_sets << rule_set
    end

    # Compare css_parser
    css_parser_rule_sets = []
    @css_parser.each_rule_set(:print) do |rule_set, media_types|
      css_parser_rule_sets << rule_set
    end

    # Verify we got expected values (only print-specific rule, not universal)
    assert_equal 1, cataract_rule_sets.length
    assert_equal "body", cataract_rule_sets.first.selector
    assert_equal [:print], cataract_rule_sets.first.media_types
    # Verify we match css_parser
    assert_equal css_parser_rule_sets.length, cataract_rule_sets.length
  end

  def test_each_rule_set_returns_enumerator
    @parser.load_string! "a { color: red }"

    enum = @parser.each_rule_set
    assert_kind_of Enumerator, enum
    assert_equal 1, enum.count
  end

  # ============================================================================
  # find_rule_sets - Find RuleSets by selectors
  # ============================================================================

  def test_find_rule_sets_single_selector
    @parser.load_string! "body { margin: 0 } .header { color: blue }"

    rule_sets = @parser.find_rule_sets(['body'])

    assert_equal 1, rule_sets.length
    assert_equal "body", rule_sets.first.selector
  end

  def test_find_rule_sets_multiple_selectors
    @parser.load_string! "body { margin: 0 } .header { color: blue } .footer { padding: 10px }"

    rule_sets = @parser.find_rule_sets(['body', '.footer'])

    assert_equal 2, rule_sets.length
    assert_equal ["body", ".footer"], rule_sets.map(&:selector)
  end

  def test_find_rule_sets_with_media_filter
    css = %{
      body { margin: 0 }
      @media print {
        body { margin: 1in }
        .header { display: none }
      }
    }
    @parser.load_string!(css)
    @css_parser.add_block!(css)

    cataract_rule_sets = @parser.find_rule_sets(['body'], :print)
    css_parser_rule_sets = @css_parser.find_rule_sets(['body'], :print)

    # Verify we got expected values (only print-specific rule, not universal)
    assert_equal 1, cataract_rule_sets.length
    assert_equal "body", cataract_rule_sets.first.selector
    assert_equal [:print], cataract_rule_sets.first.media_types
    # Verify we match css_parser
    assert_equal css_parser_rule_sets.length, cataract_rule_sets.length
  end

  def test_find_rule_sets_normalizes_whitespace
    @parser.load_string! "div   p { color: red }"

    # Should normalize whitespace in selector search
    rule_sets = @parser.find_rule_sets(['div p'])

    assert_equal 1, rule_sets.length
  end

  def test_find_rule_sets_no_duplicates
    @parser.load_string! "body { margin: 0 }"

    # Asking for same selector multiple times shouldn't duplicate
    rule_sets = @parser.find_rule_sets(['body', 'body'])

    assert_equal 1, rule_sets.length
  end

  def test_find_rule_sets_no_matches
    @parser.load_string! "body { margin: 0 }"

    rule_sets = @parser.find_rule_sets(['.nonexistent'])

    assert_equal [], rule_sets
  end
end
