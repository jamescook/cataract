# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

class TestDeclarations < Minitest::Test
  def test_basic_usage
    decl = Cataract::Declarations.new

    # Basic property setting
    decl['color'] = 'red'
    decl['background'] = 'blue'

    assert_equal 'red;', decl['color']
    assert_equal 'blue;', decl['background']
    assert_equal 2, decl.size
    refute_empty decl
  end

  def test_important_flags
    decl = Cataract::Declarations.new

    decl['color'] = 'red !important'
    decl['background'] = 'blue'

    assert_equal 'red !important;', decl['color']
    assert decl.important?('color')
    refute decl.important?('background')

    assert_equal 'color: red !important; background: blue;', decl.to_s
  end

  def test_initialization
    decl = Cataract::Declarations.new({
                                        'color' => 'red',
                                        'background' => 'blue !important'
                                      })

    assert_equal 'red;', decl['color']
    assert_equal 'blue !important;', decl['background']
    refute decl.important?('color')
    assert decl.important?('background')
  end

  def test_iteration
    decl = Cataract::Declarations.new({
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
    decl1 = Cataract::Declarations.new({
                                         'color' => 'red',
                                         'margin' => '10px'
                                       })

    decl2 = Cataract::Declarations.new({
                                         'color' => 'blue !important',
                                         'padding' => '5px'
                                       })

    # Test non-mutating merge
    merged = decl1.merge(decl2)

    assert_equal 'blue !important;', merged['color']
    assert_equal '10px;', merged['margin']
    assert_equal '5px;', merged['padding']

    # Original should be unchanged
    assert_equal 'red;', decl1['color']
    assert_nil decl1['padding']
  end

  def test_merge_with_hash
    decl = Cataract::Declarations.new({ 'color' => 'red' })

    merged = decl.merge({ 'background' => 'blue', 'margin' => '10px' })

    assert_equal 'red;', merged['color']
    assert_equal 'blue;', merged['background']
    assert_equal '10px;', merged['margin']

    # Original unchanged
    assert_nil decl['background']
  end

  def test_merge_bang
    decl = Cataract::Declarations.new({ 'color' => 'red' })

    decl['background'] = 'blue'

    # Should mutate original
    assert_equal 'red;', decl['color']
    assert_equal 'blue;', decl['background']
  end

  def test_equality
    decl1 = Cataract::Declarations.new({ 'color' => 'red', 'margin' => '10px' })
    decl2 = Cataract::Declarations.new({ 'color' => 'red', 'margin' => '10px' })
    decl3 = Cataract::Declarations.new({ 'color' => 'blue' })

    assert_equal decl1, decl2
    refute_equal decl1, decl3
  end

  def test_key?
    decl = Cataract::Declarations.new({ 'color' => 'red', 'margin' => '10px' })

    assert decl.key?('color')
    assert decl.key?('margin')
    refute decl.key?('padding')
    refute decl.key?('background')
  end

  def test_delete
    decl = Cataract::Declarations.new({ 'color' => 'red', 'margin' => '10px', 'padding' => '5px' })

    assert_equal 3, decl.size

    decl.delete('margin')

    assert_equal 2, decl.size
    refute decl.key?('margin')

    # After deletion, remaining properties are accessible
    assert_equal 'red;', decl['color']
    assert_equal '5px;', decl['padding']
  end

  def test_to_h
    decl = Cataract::Declarations.new({
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
end
