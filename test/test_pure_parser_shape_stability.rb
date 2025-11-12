# frozen_string_literal: true

require 'test_helper'

class TestPureParserShapeStability < Minitest::Test
  # Test that Stylesheet objects maintain stable shapes for YJIT optimization.
  # Shape stability means:
  # 1. All instance variables are set in initialize (not conditionally added later)
  # 2. Multiple Stylesheet instances have the same ivar layout
  # 3. Parsing CSS doesn't add new ivars (only mutates existing ones)
  #
  # Why this matters:
  # - YJIT can generate monomorphic inline caches for ivar access
  # - Memory layout is predictable at compile time
  # - No shape transition overhead in hot loops
  #
  # Note: We check ivars directly rather than using RubyVM::Shape.of() because
  # that API requires a debug Ruby build (compiled with RUBY_DEBUG macro).
  # Checking ivars is equally effective - shapes are determined by the set of
  # ivars and their order.
  #
  # Works for both C and pure Ruby implementations - both create Ruby Stylesheet
  # objects with instance variables.

  def test_stylesheet_shape_stability_across_css_types
    # Test 1: Empty stylesheet
    sheet1 = Cataract::Stylesheet.new
    ivars1_empty = sheet1.instance_variables.sort

    # Sanity check: should have some ivars
    assert_predicate ivars1_empty.length, :positive?,
                     'Stylesheet should have at least one instance variable'

    # Parse simple CSS
    css_simple = '.foo { color: red; }'
    sheet1.add_block(css_simple)
    ivars1_after = sheet1.instance_variables.sort

    # Test 2: Stylesheet with nested CSS
    css_nested = '.parent { .child { color: blue; } }'
    sheet2 = Cataract::Stylesheet.parse(css_nested)
    ivars2 = sheet2.instance_variables.sort

    # Test 3: Stylesheet with media queries
    css_media = '@media print { .footer { display: none; } }'
    sheet3 = Cataract::Stylesheet.parse(css_media)
    ivars3 = sheet3.instance_variables.sort

    # Assert: All stylesheets have identical ivar sets
    assert_equal ivars1_empty, ivars1_after,
                 'Parsing CSS should not add new ivars to Stylesheet (would cause shape transition)'
    assert_equal ivars1_after, ivars2,
                 'All Stylesheet instances should have identical ivars (shape stability)'
    assert_equal ivars2, ivars3,
                 'All Stylesheet instances should have identical ivars (shape stability)'
  end

  def test_stylesheet_no_conditional_ivars
    # Verify that all ivars are set unconditionally in initialize
    # by checking multiple stylesheets with different initialization parameters

    sheet_default = Cataract::Stylesheet.new
    sheet_with_import = Cataract::Stylesheet.new(import: true)
    sheet_no_exceptions = Cataract::Stylesheet.new(io_exceptions: false)

    ivars_default = sheet_default.instance_variables.sort
    ivars_import = sheet_with_import.instance_variables.sort
    ivars_no_exc = sheet_no_exceptions.instance_variables.sort

    # Sanity check: should have some ivars
    assert_predicate ivars_default.length, :positive?,
                     'Stylesheet should have at least one instance variable'

    assert_equal ivars_default, ivars_import,
                 'Different initialization options should not affect ivar set'
    assert_equal ivars_import, ivars_no_exc,
                 'Different initialization options should not affect ivar set'
  end
end
