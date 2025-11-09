# frozen_string_literal: true

require_relative 'test_helper'

# W3C Web Platform Tests for Oklab color space
# These tests verify our implementation matches the official W3C test suite
# Reference: https://github.com/web-platform-tests/wpt/tree/master/css/css-color
class TestColorConversionOklabW3c < Minitest::Test
  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-001.html
  # oklab(51.975% -0.1403 0.10768) should equal #008000 (green)
  def test_w3c_oklab_001_green
    decls = convert_and_get_declarations(
      '.test { color: oklab(51.975% -0.1403 0.10768) }',
      from: :oklab, to: :hex
    )

    assert_equal '#008000', decls['color']
  end

  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-002.html
  # oklab(0% 0 0) should equal #000000 (black)
  def test_w3c_oklab_002_black
    decls = convert_and_get_declarations(
      '.test { color: oklab(0% 0 0) }',
      from: :oklab, to: :hex
    )

    assert_equal '#000000', decls['color']
  end

  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-003.html
  # oklab(100% 0 0) should equal #ffffff (white)
  def test_w3c_oklab_003_white
    decls = convert_and_get_declarations(
      '.test { color: oklab(100% 0 0) }',
      from: :oklab, to: :hex
    )

    assert_equal '#ffffff', decls['color']
  end

  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-004.html
  # oklab(50% 0.05 0) should equal rgb(48.477% 34.29% 38.412%)
  def test_w3c_oklab_004_positive_a_axis
    decls = convert_and_get_declarations(
      '.test { color: oklab(50% 0.05 0) }',
      from: :oklab, to: :rgb
    )
    # W3C spec: rgb(48.477% 34.29% 38.412%) ≈ rgb(124 87 98)
    assert_equal 'rgb(48.477% 34.290% 38.412%)', decls['color']
  end

  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-005.html
  # oklab(70% -0.1 0) should equal rgb(29.264% 70.096% 63.017%)
  def test_w3c_oklab_005_negative_a_axis
    decls = convert_and_get_declarations(
      '.test { color: oklab(70% -0.1 0) }',
      from: :oklab, to: :rgb
    )
    # W3C spec: rgb(29.264% 70.096% 63.017%) ≈ rgb(75 179 161)
    assert_equal 'rgb(29.264% 70.096% 63.017%)', decls['color']
  end

  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-006.html
  # oklab(70% 0 0.125) should equal rgb(73.942% 60.484% 19.65%)
  def test_w3c_oklab_006_positive_b_axis
    decls = convert_and_get_declarations(
      '.test { color: oklab(70% 0 0.125) }',
      from: :oklab, to: :rgb
    )
    # W3C spec: rgb(73.942% 60.484% 19.65%) ≈ rgb(189 154 50)
    assert_equal 'rgb(73.942% 60.484% 19.650%)', decls['color']
  end

  # W3C Test: https://github.com/web-platform-tests/wpt/blob/2835fc2170/css/css-color/oklab-007.html
  # oklab(55% 0 -0.2) should equal rgb(27.888% 38.072% 89.414%)
  def test_w3c_oklab_007_negative_b_axis
    decls = convert_and_get_declarations(
      '.test { color: oklab(55% 0 -0.2) }',
      from: :oklab, to: :rgb
    )
    # W3C spec: rgb(27.888% 38.072% 89.414%) ≈ rgb(71 97 228)
    assert_equal 'rgb(27.888% 38.072% 89.414%)', decls['color']
  end
end
