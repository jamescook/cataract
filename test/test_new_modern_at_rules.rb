# frozen_string_literal: true

require_relative 'test_helper'

# Test modern CSS at-rules (CSS3+)
# These use the generic at-rule pattern and should be handled automatically
class TestNewModernAtRules < Minitest::Test
  def setup
    @sheet = Cataract::NewStylesheet.new
  end

  # @layer tests (Cascade Layers)
  def test_layer_basic
    @sheet.add_block(<<~CSS)
      @layer utilities {
        .padding { padding: 1rem; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
    assert_has_selector '.padding', @sheet

    rule = @sheet.find_by_selector('.padding').first

    assert_has_property({ padding: '1rem' }, rule)
  end

  def test_layer_named
    @sheet.add_block(<<~CSS)
      @layer framework {
        .button { background: blue; }
      }
      @layer utilities {
        .margin { margin: 0; }
      }
    CSS

    assert_equal 2, @sheet.rules_count
    assert_has_selector '.button', @sheet
    assert_has_selector '.margin', @sheet
  end

  # @property tests (Custom Properties API / Houdini)
  def test_property_basic
    @sheet.add_block(<<~CSS)
      @property --my-color {
        syntax: '<color>';
        inherits: false;
        initial-value: #c0ffee;
      }
    CSS

    assert_equal 1, @sheet.rules_count
    assert_has_selector '@property --my-color', @sheet
  end

  def test_property_with_usage
    @sheet.add_block(<<~CSS)
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
    @sheet.add_block(<<~CSS)
      @container (min-width: 400px) {
        .card { padding: 2rem; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
    assert_has_selector '.card', @sheet

    rule = @sheet.find_by_selector('.card').first

    assert_has_property({ padding: '2rem' }, rule)
  end

  def test_container_named
    @sheet.add_block(<<~CSS)
      @container sidebar (min-width: 300px) {
        .widget { display: grid; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
  end

  # @page tests (Paged Media)
  def test_page_basic
    @sheet.add_block(<<~CSS)
      @page {
        margin: 1in;
      }
    CSS

    assert_equal 1, @sheet.rules_count
    assert_has_selector '@page', @sheet
  end

  def test_page_named
    @sheet.add_block(<<~CSS)
      @page :first {
        margin-top: 2in;
      }
    CSS

    assert_equal 1, @sheet.rules_count
  end

  # @counter-style tests
  def test_counter_style_basic
    @sheet.add_block(<<~CSS)
      @counter-style thumbs {
        system: cyclic;
        symbols: "👍";
        suffix: " ";
      }
    CSS

    assert_equal 1, @sheet.rules_count
    assert_has_selector '@counter-style thumbs', @sheet
  end

  # @scope tests (CSS Scoping)
  def test_scope_basic
    @sheet.add_block(<<~CSS)
      @scope (.card) {
        .title { font-size: 1.2rem; }
      }
    CSS

    assert_equal 1, @sheet.rules_count
    assert_has_selector '.title', @sheet

    rule = @sheet.find_by_selector('.title').first

    assert_has_property({ 'font-size': '1.2rem' }, rule)
  end

  # Mixed modern at-rules
  def test_mixed_modern_at_rules
    @sheet.add_block(<<~CSS)
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
    assert_has_selector 'body', @sheet
    assert_has_selector '@property --theme-color', @sheet
    assert_has_selector '.responsive', @sheet
    assert_has_selector '.regular', @sheet
  end
end
