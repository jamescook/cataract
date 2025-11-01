# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Test modern CSS at-rules (CSS3+)
# These use the generic at-rule pattern and should be handled automatically
class TestModernAtRules < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  # @layer tests (Cascade Layers)
  def test_layer_basic
    @sheet.parse(<<~CSS)
      @layer utilities {
        .padding { padding: 1rem; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
    rule = @sheet.each_selector.first

    assert_equal '.padding', rule[0]
  end

  def test_layer_named
    @sheet.parse(<<~CSS)
      @layer framework {
        .button { background: blue; }
      }
      @layer utilities {
        .margin { margin: 0; }
      }
    CSS

    assert_equal 2, @sheet.rules_count
  end

  # @property tests (Custom Properties API / Houdini)
  def test_property_basic
    @sheet.parse(<<~CSS)
      @property --my-color {
        syntax: '<color>';
        inherits: false;
        initial-value: #c0ffee;
      }
    CSS

    assert_equal 1, @sheet.rules_count
    rule = @sheet.each_selector.first

    assert_equal '@property --my-color', rule[0]
  end

  def test_property_with_usage
    @sheet.parse(<<~CSS)
      @property --spacing {
        syntax: '<length>';
        inherits: true;
        initial-value: 0px;
      }

      .box {
        padding: var(--spacing);
      }
    CSS

    assert_equal 2, @sheet.rules_count
  end

  # @container tests (Container Queries)
  def test_container_basic
    @sheet.parse(<<~CSS)
      @container (min-width: 400px) {
        .card { padding: 2rem; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
    rule = @sheet.each_selector.first

    assert_equal '.card', rule[0]
  end

  def test_container_named
    @sheet.parse(<<~CSS)
      @container sidebar (min-width: 300px) {
        .widget { display: grid; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
  end

  # @page tests (Paged Media)
  def test_page_basic
    @sheet.parse(<<~CSS)
      @page {
        margin: 1in;
      }
    CSS

    assert_equal 1, @sheet.rules_count
    rule = @sheet.each_selector.first

    assert_equal '@page', rule[0]
  end

  def test_page_named
    @sheet.parse(<<~CSS)
      @page :first {
        margin-top: 2in;
      }
    CSS

    assert_equal 1, @sheet.rules_count
  end

  # @counter-style tests
  def test_counter_style_basic
    @sheet.parse(<<~CSS)
      @counter-style thumbs {
        system: cyclic;
        symbols: "👍";
        suffix: " ";
      }
    CSS

    assert_equal 1, @sheet.rules_count
    rule = @sheet.each_selector.first

    assert_equal '@counter-style thumbs', rule[0]
  end

  # @scope tests (CSS Scoping)
  def test_scope_basic
    @sheet.parse(<<~CSS)
      @scope (.card) {
        .title { font-size: 1.2rem; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
    rule = @sheet.each_selector.first

    assert_equal '.title', rule[0]
  end

  # Mixed modern at-rules
  def test_mixed_modern_at_rules
    @sheet.parse(<<~CSS)
      @layer base {
        body { margin: 0; }
      }

      @property --theme-color {
        syntax: '<color>';
        inherits: true;
        initial-value: blue;
      }

      @container (min-width: 500px) {
        .responsive { width: 100%; }
      }

      .regular { color: red; }
    CSS

    assert_equal 4, @sheet.rules_count
  end
end
