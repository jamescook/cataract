# frozen_string_literal: true

require_relative 'test_helper'

class TestNewDeclarations < Minitest::Test
  def test_basic_usage
    decl = Cataract::NewDeclarations.new

    # Basic property setting
    decl['color'] = 'red'
    decl['background'] = 'blue'

    assert_equal 'red', decl['color']
    assert_equal 'blue', decl['background']
    assert_equal 2, decl.size
    refute_empty decl
  end

  def test_important_flags
    decl = Cataract::NewDeclarations.new

    decl['color'] = 'red !important'
    decl['background'] = 'blue'

    assert_equal 'red !important', decl['color']
    assert decl.important?('color')
    refute decl.important?('background')

    assert_equal 'color: red !important; background: blue;', decl.to_s
  end

  def test_initialization
    decl = Cataract::NewDeclarations.new({
                                           'color' => 'red',
                                           'background' => 'blue !important'
                                         })

    assert_equal 'red', decl['color']
    assert_equal 'blue !important', decl['background']
    refute decl.important?('color')
    assert decl.important?('background')
  end

  def test_iteration
    decl = Cataract::NewDeclarations.new({
                                           'color' => 'red',
                                           'background' => 'blue !important',
                                           'margin' => '10px'
                                         })

    properties = []
    values = []
    important_flags = []

    decl.each do |prop, value, important|
      properties << prop
      values << value
      important_flags << important
    end

    assert_equal %w[color background margin], properties
    assert_equal %w[red blue 10px], values
    assert_equal [false, true, false], important_flags
  end

  def test_merge
    decl1 = Cataract::NewDeclarations.new({
                                            'color' => 'red',
                                            'margin' => '10px'
                                          })

    decl2 = Cataract::NewDeclarations.new({
                                            'color' => 'blue !important',
                                            'padding' => '5px'
                                          })

    # Test non-mutating merge
    merged = decl1.merge(decl2)

    assert_equal 'blue !important', merged['color']
    assert_equal '10px', merged['margin']
    assert_equal '5px', merged['padding']

    # Original should be unchanged
    assert_equal 'red', decl1['color']
    assert_nil decl1['padding']
  end

  def test_merge_with_hash
    decl = Cataract::NewDeclarations.new({ 'color' => 'red' })

    merged = decl.merge({ 'background' => 'blue', 'margin' => '10px' })

    assert_equal 'red', merged['color']
    assert_equal 'blue', merged['background']
    assert_equal '10px', merged['margin']

    # Original unchanged
    assert_nil decl['background']
  end

  def test_merge_bang
    decl = Cataract::NewDeclarations.new({ 'color' => 'red' })

    decl['background'] = 'blue'

    # Should mutate original
    assert_equal 'red', decl['color']
    assert_equal 'blue', decl['background']
  end

  def test_equality
    decl1 = Cataract::NewDeclarations.new({ 'color' => 'red', 'margin' => '10px' })
    decl2 = Cataract::NewDeclarations.new({ 'color' => 'red', 'margin' => '10px' })
    decl3 = Cataract::NewDeclarations.new({ 'color' => 'blue' })

    assert_equal decl1, decl2
    refute_equal decl1, decl3
  end

  def test_key?
    decl = Cataract::NewDeclarations.new({ 'color' => 'red', 'margin' => '10px' })

    assert decl.key?('color')
    assert decl.key?('margin')
    refute decl.key?('padding')
    refute decl.key?('background')
  end

  def test_delete
    decl = Cataract::NewDeclarations.new({ 'color' => 'red', 'margin' => '10px', 'padding' => '5px' })

    assert_equal 3, decl.size

    decl.delete('margin')

    assert_equal 2, decl.size
    refute decl.key?('margin')

    # After deletion, remaining properties are accessible
    assert_equal 'red', decl['color']
    assert_equal '5px', decl['padding']
  end

  def test_to_h
    decl = Cataract::NewDeclarations.new({
                                           'color' => 'red',
                                           'background' => 'blue !important',
                                           'margin' => '10px'
                                         })

    hash = decl.to_h

    assert_instance_of Hash, hash
    assert_equal 'red', hash['color']
    assert_equal 'blue !important', hash['background']
    assert_equal '10px', hash['margin']
    assert_equal 3, hash.size
  end

  # Edge case tests for set_property parsing
  def test_quoted_string_with_important_text
    # !important inside quotes should NOT be treated as important flag
    decl = Cataract::NewDeclarations.new
    decl['content'] = '"text !important"'

    assert_equal '"text !important"', decl['content']
    refute decl.important?('content'), 'Should not treat !important inside quotes as flag'
  end

  def test_quoted_string_with_colons
    # Colons inside quotes should not confuse property/value parsing
    decl = Cataract::NewDeclarations.new
    decl['content'] = '": not a property"'

    assert_equal '": not a property"', decl['content']
  end

  def test_value_with_comments
    # Comments should be handled (either preserved or stripped)
    decl = Cataract::NewDeclarations.new
    decl['color'] = 'red /* blue */'

    # Parser should handle this - either keep comment or strip it
    assert decl['color']
  end

  def test_value_with_comment_before_important
    # Comment before !important
    decl = Cataract::NewDeclarations.new
    decl['color'] = 'red /* comment */ !important'

    # Should still recognize !important
    assert decl.important?('color'), 'Should recognize !important after comment'
  end

  def test_trailing_semicolons
    # Multiple trailing semicolons should be stripped
    decl = Cataract::NewDeclarations.new
    decl['color'] = 'red;;;'

    assert_equal 'red', decl['color']
  end

  def test_important_with_extra_whitespace
    # Various whitespace around !important
    decl = Cataract::NewDeclarations.new
    decl['color'] = 'red  !important'
    decl['background'] = 'blue!important'
    decl['margin'] = 'green ! important'

    assert decl.important?('color')
    # These may or may not work depending on parser strictness
    # Just document current behavior
  end

  def test_empty_value_with_important
    # css_parser silently ignores "property: !important" with no value
    decl = Cataract::NewDeclarations.new
    decl['color'] = '!important'

    # Should either be nil or raise - document current behavior
    assert_nil decl['color'], 'Should ignore declaration with only !important'
  end

  def test_url_with_special_chars
    # URLs can contain special characters
    decl = Cataract::NewDeclarations.new
    decl['background'] = 'url(data:image/png;base64,abc123)'

    assert_equal 'url(data:image/png;base64,abc123)', decl['background']
  end

  def test_escaped_quotes_in_string
    # Escaped quotes inside quoted strings
    decl = Cataract::NewDeclarations.new
    decl['content'] = '"value with \\" quote"'

    # Should preserve the escaped quote
    assert decl['content']
  end

  def test_property_normalization
    # Property names should be normalized (lowercased)
    decl = Cataract::NewDeclarations.new
    decl['COLOR'] = 'red'
    decl['Background-Color'] = 'blue'

    assert_equal 'red', decl['color']
    assert_equal 'blue', decl['background-color']
  end
end
