# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Test CSS at-rules support
# Based on W3C specifications:
# - @font-face: https://www.w3.org/TR/css-fonts-3/#font-face-rule
# - @keyframes: https://www.w3.org/TR/css-animations-1/#keyframes
# - @supports: https://www.w3.org/TR/css-conditional-3/#at-supports
# - nested @media: https://www.w3.org/TR/css-conditional-3/#at-media
class TestAtRules < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # @font-face tests
  def test_font_face_basic
    @sheet.parse(<<~CSS)
      @font-face {
        font-family: 'MyFont';
        src: url('font.woff2');
      }
    CSS

    assert_equal 1, @sheet.size

    # @font-face should be treated as a selector
    rule = @sheet.each_selector.first

    assert_equal '@font-face', rule[0]
    # rule[1] is now a Declarations object, check for properties properly
    assert rule[1].key?('font-family')
    assert rule[1].key?('src')
  end

  def test_font_face_with_descriptors
    @sheet.parse(<<~CSS)
      @font-face {
        font-family: 'Open Sans';
        src: url('opensans.woff2') format('woff2'),
             url('opensans.woff') format('woff');
        font-weight: 400;
        font-style: normal;
        unicode-range: U+0020-007F;
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_multiple_font_faces
    @sheet.parse(<<~CSS)
      @font-face {
        font-family: 'Regular';
        src: url('regular.woff2');
      }

      @font-face {
        font-family: 'Bold';
        src: url('bold.woff2');
        font-weight: bold;
      }
    CSS

    assert_equal 2, @sheet.size
  end

  def test_font_face_with_other_rules
    @sheet.parse(<<~CSS)
      body { margin: 0; }

      @font-face {
        font-family: 'MyFont';
        src: url('font.woff2');
      }

      .header { font-family: 'MyFont'; }
    CSS

    assert_equal 3, @sheet.size
  end

  # @keyframes tests
  def test_keyframes_basic
    @sheet.parse(<<~CSS)
      @keyframes slide {
        from { left: 0; }
        to { left: 100px; }
      }
    CSS

    assert_equal 1, @sheet.size

    rule = @sheet.each_selector.first

    assert_equal '@keyframes slide', rule[0]
  end

  def test_keyframes_with_percentages
    @sheet.parse(<<~CSS)
      @keyframes fade {
        0% { opacity: 0; }
        50% { opacity: 0.5; }
        100% { opacity: 1; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_keyframes_webkit_prefix
    @sheet.parse(<<~CSS)
      @-webkit-keyframes bounce {
        0% { top: 0; }
        100% { top: 100px; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_keyframes_webkit_from_bootstrap
    # Real pattern from Bootstrap CSS
    @sheet.parse(<<~CSS)
      @-webkit-keyframes spinner-grow {
        0% {
          transform: scale(0);
        }
        50% {
          opacity: 1;
          transform: none;
        }
      }

      @keyframes spinner-border {
        to {
          transform: rotate(360deg) /* rtl:ignore */;
        }
      }
    CSS

    assert_equal 2, @sheet.size
  end

  def test_webkit_animation_property
    # Bootstrap pattern that fails: -webkit-animation property
    @sheet.parse(<<~CSS)
      @-webkit-keyframes spinner-border {
        to {
          transform: rotate(360deg) /* rtl:ignore */;
        }
      }

      @keyframes spinner-border {
        to {
          transform: rotate(360deg) /* rtl:ignore */;
        }
      }
      .spinner-border {
        display: inline-block;
        width: 2rem;
        height: 2rem;
        vertical-align: -0.125em;
        border: 0.25em solid currentColor;
        border-right-color: transparent;
        border-radius: 50%;
        -webkit-animation: 0.75s linear infinite spinner-border;
        animation: 0.75s linear infinite spinner-border;
      }
    CSS

    assert_equal 3, @sheet.size
  end

  def test_css_custom_properties
    # Bootstrap pattern: CSS custom properties (CSS variables) with -- prefix
    @sheet.parse(<<~CSS)
      .ratio-1x1 {
        --bs-aspect-ratio: 100%;
      }

      .ratio-4x3 {
        --bs-aspect-ratio: calc(3 / 4 * 100%);
      }

      .ratio-16x9 {
        --bs-aspect-ratio: calc(9 / 16 * 100%);
      }

      .ratio-21x9 {
        --bs-aspect-ratio: calc(9 / 21 * 100%);
      }
    CSS

    assert_equal 4, @sheet.size
  end

  # @supports tests
  def test_supports_basic
    @sheet.parse(<<~CSS)
      @supports (display: grid) {
        .grid { display: grid; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_supports_with_not
    @sheet.parse(<<~CSS)
      @supports not (display: flex) {
        .fallback { display: block; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_supports_with_and
    @sheet.parse(<<~CSS)
      @supports (display: grid) and (gap: 1rem) {
        .modern { display: grid; gap: 1rem; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_supports_with_or
    @sheet.parse(<<~CSS)
      @supports (display: flex) or (display: -webkit-flex) {
        .flex { display: flex; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  # Nested @media tests
  def test_nested_media_queries
    @sheet.parse(<<~CSS)
      @media screen {
        @media (min-width: 500px) {
          body { color: red; }
        }
      }
    CSS

    assert_equal 1, @sheet.size

    rule = @sheet.each_selector.first

    assert_equal 'body', rule[0]
    # Should combine media types: screen AND (min-width: 500px)
    assert_includes rule[3], :screen
  end

  def test_nested_media_complex
    @sheet.parse(<<~CSS)
      @media screen {
        .outer { color: blue; }

        @media (min-width: 768px) {
          .inner { color: red; }
        }
      }
    CSS

    assert_equal 2, @sheet.size
  end

  # Mixed at-rules
  def test_mixed_at_rules
    @sheet.parse(<<~CSS)
      @font-face {
        font-family: 'Custom';
        src: url('custom.woff2');
      }

      @keyframes slide {
        from { left: 0; }
        to { left: 100px; }
      }

      @supports (display: grid) {
        .grid { display: grid; }
      }

      @media print {
        body { margin: 0; }
      }

      .header { color: blue; }
    CSS

    assert_equal 5, @sheet.size
  end
end
