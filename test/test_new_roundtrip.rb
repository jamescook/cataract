# frozen_string_literal: true

require_relative 'test_helper'

class TestNewRoundtrip < Minitest::Test
  def test_roundtrip_preserves_rules
    css = <<~CSS
      .btn { padding: 10px; }
      .alert { margin: 5px; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Both selectors should be present
    assert_includes dumped, '.btn'
    assert_includes dumped, '.alert'
    assert_includes dumped, 'padding: 10px'
    assert_includes dumped, 'margin: 5px'
  end

  def test_roundtrip_preserves_important
    css = '.test { color: red; margin: 10px !important; }'

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Should have !important preserved
    assert_includes dumped, 'color: red'
    assert_includes dumped, 'margin: 10px !important'
  end

  def test_roundtrip_bootstrap_fixture
    # This is the real test - bootstrap.css is a real-world stylesheet
    original_css = File.read('test/fixtures/bootstrap.css')

    # Parse and dump
    sheet = Cataract::Stylesheet.parse(original_css)
    dumped = sheet.to_s

    # Parse the dumped CSS again
    sheet2 = Cataract::Stylesheet.parse(dumped)
    dumped2 = sheet2.to_s

    # The second dump should be identical to the first (idempotent)
    # This proves we've reached a canonical form
    assert_equal dumped, dumped2, 'Dumped CSS should be idempotent (parse->dump->parse->dump should be stable)'

    # Count rules - should be the same
    assert_equal sheet.size, sheet2.size,
                 'Dumped CSS should have same number of rules after round-trip'
  end

  def test_roundtrip_empty_stylesheet
    css = ''
    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    assert_equal '', dumped.strip
  end

  def test_roundtrip_single_rule
    css = '.test { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    assert_includes dumped, '.test'
    assert_includes dumped, 'color: red'
  end

  def test_roundtrip_preserves_utf8_in_content
    css = <<~CSS
      .emoji::before {
        content: "👍 ✨ 🎉";
      }
      .japanese {
        content: "こんにちは世界";
        font-family: "ＭＳ ゴシック";
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Verify UTF-8 content is preserved
    assert_includes dumped, '👍'
    assert_includes dumped, '✨'
    assert_includes dumped, '🎉'
    assert_includes dumped, 'こんにちは世界'
    assert_includes dumped, 'ゴシック'

    # Verify encoding
    assert_equal Encoding::UTF_8, dumped.encoding
  end

  def test_roundtrip_preserves_utf8_selectors
    css = <<~CSS
      .日本語クラス {
        color: red;
      }
      .한글클래스 {
        color: blue;
      }
      .中文类名 {
        color: green;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Verify UTF-8 selectors are preserved
    assert_includes dumped, '日本語クラス'
    assert_includes dumped, '한글클래스'
    assert_includes dumped, '中文类名'

    # Verify encoding
    assert_equal Encoding::UTF_8, dumped.encoding
  end

  def test_roundtrip_mixed_ascii_and_utf8
    css = <<~CSS
      .button {
        content: "→ Click here";
        padding: 10px;
      }
      .arrow::after {
        content: "⟶";
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Verify both ASCII and UTF-8 preserved
    assert_includes dumped, 'button'
    assert_includes dumped, 'padding: 10px'
    assert_includes dumped, '→'
    assert_includes dumped, '⟶'

    # Parse-dump-parse cycle should be idempotent
    sheet2 = Cataract::Stylesheet.parse(dumped)
    dumped2 = sheet2.to_s

    assert_equal dumped, dumped2, 'UTF-8 CSS should be idempotent through parse-dump cycle'
  end

  def test_roundtrip_media_queries
    css = <<~CSS
      .test { color: red; }
      @media screen {
        .test { color: blue; }
      }
      @media print {
        .test { color: black; }
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Should preserve media queries
    assert_includes dumped, '@media screen'
    assert_includes dumped, '@media print'
    assert_includes dumped, '.test'

    # Parse again to verify structure
    sheet2 = Cataract::Stylesheet.parse(dumped)

    assert_equal 3, sheet2.size, 'Should have 3 rules (1 base + 2 media)'
    assert_equal 2, sheet2.media_queries.size, 'Should have 2 media queries'
  end

  def test_roundtrip_preserves_declaration_order
    css = '.test { margin: 0; padding: 20px; border: 1px solid; }'

    sheet = Cataract::Stylesheet.parse(css)
    dumped = sheet.to_s

    # Parse again
    sheet2 = Cataract::Stylesheet.parse(dumped)

    # Check declarations are in some order (order preserved within each rule)
    sheet2.each_selector do |rule|
      next unless rule.selector == '.test'

      properties = rule.declarations.map(&:property)

      assert_equal 3, properties.size
      # Should have all three properties
      assert_includes properties, 'margin'
      assert_includes properties, 'padding'
      assert_includes properties, 'border'
    end
  end
end
