require "minitest/autorun"
require "cataract"

# Media types handling tests
# Based on css_parser gem's test_css_parser_media_types.rb
class TestParserMediaTypes < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
  end

  def test_finding_by_media_type
    # from http://www.w3.org/TR/CSS21/media.html#at-media-rule
    @parser.add_block!(<<-CSS)
      @media print {
        body { font-size: 10pt }
      }
      @media screen {
        body { font-size: 13px }
      }
      @media screen, print {
        body { line-height: 1.2 }
      }
    CSS

    assert_equal 'font-size: 10pt; line-height: 1.2;', @parser.find_by_selector('body', :print).join(' ')
    assert_equal 'font-size: 13px; line-height: 1.2;', @parser.find_by_selector('body', :screen).join(' ')
  end

  def test_with_parenthesized_media_features
    @parser.add_block!(<<-CSS)
      body { color: black }
      @media screen and (width > 500px) {
        body { color: red }
      }
    CSS

    # :all returns ALL rules (css_parser behavior)
    assert_equal 'color: black; color: red;', @parser.find_by_selector('body', :all).join(' ')
    assert_equal 'color: red;', @parser.find_by_selector('body', :screen).join(' ')
  end

  def test_finding_by_multiple_media_types
    @parser.add_block!(<<-CSS)
      @media print {
        body { font-size: 10pt }
      }
      @media handheld {
        body { font-size: 13px }
      }
      @media screen, print {
        body { line-height: 1.2 }
      }
    CSS

    # Query with array of media types
    results = @parser.find_by_selector('body', [:screen, :handheld])
    assert_includes results.join(' '), 'font-size: 13px;'
    assert_includes results.join(' '), 'line-height: 1.2;'
  end

  def test_adding_block_with_media_types
    @parser.add_block!(<<-CSS, media_types: [:screen])
      body { font-size: 10pt }
    CSS

    assert_equal 'font-size: 10pt;', @parser.find_by_selector('body', :screen).join(' ')
    assert @parser.find_by_selector('body', :handheld).empty?
  end

  def test_adding_block_with_media_types_followed_by_general_rule
    @parser.add_block!(<<-CSS)
      @media print {
        body { font-size: 10pt }
      }

      body { color: black }
    CSS

    assert_includes @parser.to_s, 'color: black'
  end

  def test_adding_rule_set_with_media_type
    @parser.add_rule!(selector: 'body', declarations: 'color: black', media_types: [:handheld, :tty])
    @parser.add_rule!(selector: 'body', declarations: 'color: blue', media_types: :screen)
    assert_equal 'color: black;', @parser.find_by_selector('body', :handheld).join(' ')
  end

  def test_selecting_with_all_media_types
    @parser.add_rule!(selector: 'body', declarations: 'color: black', media_types: [:handheld, :tty])
    # :all should match all media-specific rules
    assert_equal 'color: black;', @parser.find_by_selector('body', :all).join(' ')
  end

  def test_to_s_includes_media_queries
    @parser.add_rule!(selector: 'body', declarations: 'color: black', media_types: :screen)
    output = @parser.to_s
    assert_includes output, '@media'
    assert_includes output, 'color: black'
  end

  def test_multiple_media_types_single_rule
    # Test that @media screen, print creates ONE rule with multiple media types
    # NOT multiple rules (one per media type)
    @parser.add_block!(<<-CSS)
      @media screen, print {
        .header { color: blue; }
      }
    CSS

    assert_equal 1, @parser.rules_count

    # Verify the rule appears for both media types
    assert_equal 'color: blue;', @parser.find_by_selector('.header', :screen).join(' ')
    assert_equal 'color: blue;', @parser.find_by_selector('.header', :print).join(' ')
  end

  def test_media_types_rule_counting
    # Ensure rules are counted correctly across different media contexts
    @parser.add_block!(<<-CSS)
      body { margin: 0; }

      @media print {
        body { font-size: 10pt; }
        .header { padding: 10px; }
      }

      @media screen {
        .mobile-menu { display: block; }
      }

      @media screen, print {
        .universal { font-size: 14px; }
        #footer { margin-top: 20px; }
      }

      .sidebar { width: 250px; }
    CSS

    # 1 base body rule
    # 2 print rules (body, .header)
    # 1 screen rule (.mobile-menu)
    # 2 screen,print rules (.universal, #footer)
    # 1 base sidebar rule
    # Total: 7 rules
    assert_equal 7, @parser.rules_count
  end

  def test_duplicate_selectors_different_media_types
    # Same selector should create separate rules for different media types
    @parser.add_block!(<<-CSS)
      body { color: black; }

      @media print {
        body { color: black; background: white; }
      }

      @media screen {
        body { color: #333; background: #fff; }
      }
    CSS

    assert_equal 3, @parser.rules_count

    # All media should return all three rules
    all_body_rules = @parser.find_by_selector('body', :all)
    assert_equal 3, all_body_rules.length

    # Print should return only print-specific rule
    print_body = @parser.find_by_selector('body', :print)
    assert_equal 1, print_body.length
    assert_includes print_body.join(' '), 'background: white'
  end

  def test_nested_rules_within_media_query
    # Test multiple selectors within a single media query
    @parser.add_block!(<<-CSS)
      @media screen {
        .header { color: blue; }
        .footer { color: red; }
        .sidebar { width: 200px; }
      }
    CSS

    assert_equal 3, @parser.rules_count

    # All three should be screen-only
    assert_equal 'color: blue;', @parser.find_by_selector('.header', :screen).join(' ')
    assert_equal 'color: red;', @parser.find_by_selector('.footer', :screen).join(' ')
    assert_equal 'width: 200px;', @parser.find_by_selector('.sidebar', :screen).join(' ')

    # None should appear for print
    assert @parser.find_by_selector('.header', :print).empty?
    assert @parser.find_by_selector('.footer', :print).empty?
    assert @parser.find_by_selector('.sidebar', :print).empty?
  end

  def test_media_types_preserved_in_each_selector
    @parser.add_block!(<<-CSS)
      .base { color: black; }

      @media screen, print {
        .multi { color: blue; }
      }

      @media handheld {
        .handheld { color: red; }
      }
    CSS

    rules = {}
    @parser.each_selector do |selector, declarations, specificity, media_types|
      rules[selector] = media_types
    end

    assert_equal [:all], rules['.base']
    assert_equal [:screen, :print], rules['.multi']
    assert_equal [:handheld], rules['.handheld']
  end
end
