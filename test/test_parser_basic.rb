require "minitest/autorun"
require "cataract"

# Basic Parser functionality tests
# Based on css_parser gem's test_css_parser_basic.rb
class TestParserBasic < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
    @css = <<-CSS
      html, body, p { margin: 0px; }
      p { padding: 0px; }
      #content { font: 12px/normal sans-serif; }
      .content { color: red; }
    CSS
  end

  def test_finding_by_selector
    @parser.add_block!(@css)
    assert_equal 'margin: 0px;', @parser.find_by_selector('body').join(' ')
    assert_equal 'margin: 0px; padding: 0px;', @parser.find_by_selector('p').join(' ')
    assert_equal 'color: red;', @parser.find_by_selector('.content').join(' ')
    assert_equal 'font: 12px/normal sans-serif;', @parser.find_by_selector('#content').join(' ')
  end

  def test_adding_block
    @parser.add_block!(@css)
    assert_equal 'margin: 0px;', @parser.find_by_selector('body').join
  end

  def test_adding_block_without_closing_brace
    @parser.add_block!('p { color: red;', fix_braces: true)
    assert_equal 'color: red;', @parser.find_by_selector('p').join
  end

  def test_adding_a_rule
    @parser.add_rule!(selector: 'div', declarations: 'color: blue')
    assert_equal 'color: blue;', @parser.find_by_selector('div').join(' ')
  end

  def test_adding_a_rule_set
    rs = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    @parser.add_rule_set!(rs)
    assert_equal 'color: blue;', @parser.find_by_selector('div').join(' ')
  end

  def test_removing_a_rule_set
    rs = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    @parser.add_rule_set!(rs)
    rs2 = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    @parser.remove_rule_set!(rs2)
    assert_equal '', @parser.find_by_selector('div').join(' ')
  end

  # Skip URL conversion tests for now - those are advanced features
  # def test_toggling_uri_conversion
  #   ...
  # end

  def test_converting_to_hash
    rs = Cataract::RuleSet.new(selector: 'div', declarations: 'color: blue')
    @parser.add_rule_set!(rs)
    hash = @parser.to_h
    assert_equal 'blue', hash['all']['div']['color']
  end
end
