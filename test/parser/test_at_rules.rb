# frozen_string_literal: true

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
    @sheet.add_block(<<~CSS)
      @font-face {
        font-family: 'MyFont';
        src: url('font.woff2');
      }
    CSS

    assert_equal 1, @sheet.size

    # @font-face should be treated as a selector
    assert_has_selector '@font-face', @sheet

    rule = @sheet.with_selector('@font-face').first

    assert_has_property({ 'font-family': "'MyFont'" }, rule)
    assert_has_property({ src: "url('font.woff2')" }, rule)
  end

  def test_font_face_with_descriptors
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
      @keyframes slide {
        from { left: 0; }
        to { left: 100px; }
      }
    CSS

    assert_equal 1, @sheet.size

    assert_has_selector '@keyframes slide', @sheet
  end

  def test_keyframes_webkit_prefix
    @sheet.add_block(<<~CSS)
      @-webkit-keyframes bounce {
        0% { top: 0; }
        100% { top: 100px; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_keyframes_webkit_from_bootstrap
    # Real pattern from Bootstrap CSS
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
      @supports (display: grid) {
        .grid { display: grid; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_supports_with_not
    @sheet.add_block(<<~CSS)
      @supports not (display: flex) {
        .fallback { display: block; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_supports_with_and
    @sheet.add_block(<<~CSS)
      @supports (display: grid) and (gap: 1rem) {
        .modern { display: grid; gap: 1rem; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_supports_with_or
    @sheet.add_block(<<~CSS)
      @supports (display: flex) or (display: -webkit-flex) {
        .flex { display: flex; }
      }
    CSS

    assert_equal 1, @sheet.size
  end

  # Nested @media tests
  def test_nested_media_queries
    @sheet.add_block(<<~CSS)
      @media screen {
        @media (min-width: 500px) {
          body { color: red; }
        }
      }
    CSS

    assert_equal 1, @sheet.size

    rule = @sheet.rules.first

    assert_equal 'body', rule.selector
    # Should combine media queries: screen AND (min-width: 500px)
    # Check that this rule is accessible via the combined media query
    combined_media = :'screen and (min-width: 500px)'

    assert_equal [rule], @sheet.with_media(combined_media)
  end

  def test_nested_media_complex
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
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

  # Test keyframes serialization round-trip
  def test_keyframes_roundtrip
    css = <<~CSS
      @keyframes fade {
        from { opacity: 0; }
        to { opacity: 1; }
      }
    CSS

    @sheet.add_block(css)
    dumped = @sheet.to_s

    # Verify exact round-trip serialization
    expected = "@keyframes fade {\n  from { opacity: 0; }\n  to { opacity: 1; }\n}\n"

    assert_equal expected, dumped

    # Count braces - should be balanced
    open_braces = dumped.count('{')
    close_braces = dumped.count('}')

    assert_equal open_braces, close_braces, "Braces should be balanced in:\n#{dumped}"
  end

  def test_webkit_keyframes_roundtrip
    css = <<~CSS
      @-webkit-keyframes progress-bar-stripes {
        from { background-position: 1rem 0; }
        to { background-position: 0 0; }
      }
    CSS

    @sheet.add_block(css)
    dumped = @sheet.to_s

    assert_equal css, dumped
  end

  def test_keyframes_with_percentages
    css = <<~CSS
      @keyframes spin {
        0% { transform: rotate(0deg); }
        50% { transform: rotate(180deg); }
        100% { transform: rotate(360deg); }
      }
    CSS

    @sheet.add_block(css)
    dumped = @sheet.to_s

    assert_equal css, dumped
  end

  # Other at-rules tests
  def test_page_rule
    @sheet.add_block(<<~CSS)
      @page {
        margin: 1in;
      }
      @page :first {
        margin-top: 2in;
      }
    CSS

    assert_equal 2, @sheet.size

    # Check both are @page rules with correct selectors
    assert_equal '@page', @sheet.rules[0].selector
    assert_equal '@page :first', @sheet.rules[1].selector

    # Check declarations
    assert_has_property({ margin: '1in' }, @sheet.rules[0])
    assert_has_property({ 'margin-top': '2in' }, @sheet.rules[1])
  end

  def test_layer_rule
    @sheet.add_block(<<~CSS)
      @layer utilities {
        .padding-sm { padding: 0.5rem; }
      }
    CSS

    assert_equal 1, @sheet.size
    assert_has_selector '.padding-sm', @sheet
  end

  def test_container_rule
    @sheet.add_block(<<~CSS)
      @container (min-width: 700px) {
        .card { display: grid; }
      }
    CSS

    assert_equal 1, @sheet.size
    assert_has_selector '.card', @sheet
  end

  def test_scope_rule
    @sheet.add_block(<<~CSS)
      @scope (.card) {
        .title { font-size: 1.2em; }
      }
    CSS

    assert_equal 1, @sheet.size
    assert_has_selector '.title', @sheet
  end

  def test_property_rule
    # @property defines a CSS custom property
    @sheet.add_block(<<~CSS)
      @property --my-color {
        syntax: '<color>';
        inherits: false;
        initial-value: #c0ffee;
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_counter_style_rule
    @sheet.add_block(<<~CSS)
      @counter-style thumbs {
        system: cyclic;
        symbols: "\\1F44D";
        suffix: " ";
      }
    CSS

    assert_equal 1, @sheet.size
  end

  def test_mixed_nested_at_rules
    # Mix of different at-rule types
    @sheet.add_block(<<~CSS)
      @layer base {
        body { margin: 0; }
      }

      @font-face {
        font-family: 'Custom';
        src: url('custom.woff2');
      }

      @keyframes slide {
        from { left: 0; }
        to { left: 100px; }
      }

      @page {
        margin: 1cm;
      }
    CSS

    assert_equal 4, @sheet.size
  end
end
