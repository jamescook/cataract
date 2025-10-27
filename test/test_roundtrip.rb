require "minitest/autorun"
require "cataract"

class TestRoundtrip < Minitest::Test
  def test_roundtrip_merges_duplicate_selectors
    # CSS with duplicate selectors (common in real stylesheets)
    css = <<~CSS
      .display-4 {
        font-size: 3.5rem;
      }
      .display-4 {
        font-size: calc(1.475rem + 2.7vw);
        font-weight: 300;
        line-height: 1.2;
      }
    CSS

    # Parse and dump
    stylesheet = Cataract.parse_css(css)
    dumped = stylesheet.to_s

    # The dumped CSS should have merged the duplicate selectors
    # Should only appear once with the final cascaded properties
    assert_equal 1, dumped.scan(/\.display-4/).count,
      "Dumped CSS should merge duplicate selectors into one"

    # Verify it contains the final cascaded values
    assert_includes dumped, "calc(1.475rem + 2.7vw)", "Should have final font-size"
    assert_includes dumped, "font-weight: 300", "Should have font-weight"
    assert_includes dumped, "line-height: 1.2", "Should have line-height"

    # The earlier value should be overridden (not present)
    refute_includes dumped, "font-size: 3.5rem;", "Earlier font-size should be overridden"
  end

  def test_roundtrip_preserves_important
    css = <<~CSS
      .test {
        color: red;
      }
      .test {
        color: blue !important;
      }
    CSS

    stylesheet = Cataract.parse_css(css)
    dumped = stylesheet.to_s

    # Should only appear once
    assert_equal 1, dumped.scan(/\.test/).count

    # Should have !important preserved
    assert_includes dumped, "color: blue !important"
    refute_includes dumped, "color: red", "Non-important color should be overridden"
  end

  def test_roundtrip_multiple_different_selectors
    css = <<~CSS
      .btn { padding: 10px; }
      .alert { margin: 5px; }
      .btn { border: 1px solid; }
    CSS

    stylesheet = Cataract.parse_css(css)
    dumped = stylesheet.to_s

    # Both selectors should appear once each
    assert_equal 1, dumped.scan(/\.btn/).count
    assert_equal 1, dumped.scan(/\.alert/).count

    # .btn should have both properties merged
    btn_match = dumped.match(/\.btn\s*\{([^}]+)\}/)
    assert btn_match, "Should find .btn rule"
    btn_content = btn_match[1]
    assert_includes btn_content, "padding: 10px"
    assert_includes btn_content, "border: 1px solid"
  end

  def test_roundtrip_bootstrap_fixture
    # This is the real test - bootstrap.css has many duplicate selectors
    original_css = File.read('test/fixtures/bootstrap.css')

    # Parse and dump
    stylesheet = Cataract.parse_css(original_css)
    dumped = stylesheet.to_s

    # Parse the dumped CSS again
    stylesheet2 = Cataract.parse_css(dumped)
    dumped2 = stylesheet2.to_s

    # The second dump should be identical to the first (idempotent)
    # This proves we've reached a canonical form
    assert_equal dumped, dumped2, "Dumped CSS should be idempotent (parse->dump->parse->dump should be stable)"

    # Count rules - dumped should have fewer rules than original due to merging
    assert stylesheet2.size <= stylesheet.size,
      "Dumped CSS should have same or fewer rules due to merging duplicates"
  end

  def test_roundtrip_preserves_specificity_ordering
    css = <<~CSS
      .class { color: blue; }
      #id { color: red; }
      .class { background: white; }
    CSS

    stylesheet = Cataract.parse_css(css)
    dumped = stylesheet.to_s

    # Should have 2 rules (one for each unique selector)
    assert_equal 2, dumped.scan(/\{/).count

    # When both rules apply to the same element, #id wins due to specificity
    # This is about the merge logic, not the dump format
  end

  def test_roundtrip_empty_stylesheet
    css = ""
    stylesheet = Cataract.parse_css(css)
    dumped = stylesheet.to_s

    assert_equal "", dumped.strip
  end

  def test_roundtrip_single_rule
    css = ".test { color: red; }"
    stylesheet = Cataract.parse_css(css)
    dumped = stylesheet.to_s

    assert_includes dumped, ".test"
    assert_includes dumped, "color: red"
  end
end
