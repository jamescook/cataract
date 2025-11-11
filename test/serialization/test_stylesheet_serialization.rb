class TestStylesheetSerialization < Minitest::Test
  # ============================================================================
  # Charset handling
  # ============================================================================

  def test_no_charset
    css = 'body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_nil sheet.charset
    refute_includes sheet.to_s, '@charset'
  end

  def test_charset_serialization
    css = '@charset "UTF-8";
body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.to_s

    # @charset should be first line
    assert_match(/\A@charset "UTF-8";/, result)
    assert_includes result, 'body'
  end

  # ============================================================================
  # Round-trip tests
  # ============================================================================

  def test_round_trip
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.to_s

    # Parse the result again
    sheet2 = Cataract::Stylesheet.parse(result)

    assert_equal sheet.size, sheet2.size
  end

  # ============================================================================
  # Serialization (to_s) tests
  # ============================================================================

  def test_to_s_basic
    # Normalized fixture matching serialization format
    css = "body { color: red; margin: 10px; }\n"
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 1, sheet.rules.length

    rule = sheet.rules[0]

    assert_equal 'body', rule.selector
    assert_equal 2, rule.declarations.length

    # Check declarations
    color_decl = rule.declarations.find { |d| d.property == 'color' }

    assert_equal 'red', color_decl.value
    refute color_decl.important

    margin_decl = rule.declarations.find { |d| d.property == 'margin' }

    assert_equal '10px', margin_decl.value
    refute margin_decl.important

    # E2E: Round-trip should match exactly
    assert_equal css, sheet.to_s
  end

  def test_to_s_with_important
    # Normalized fixture matching serialization format
    css = "div { color: blue !important; }\n"
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 1, sheet.rules.length

    rule = sheet.rules[0]

    assert_equal 'div', rule.selector
    assert_equal 1, rule.declarations.length

    # Check declaration with !important
    decl = rule.declarations[0]

    assert_equal 'color', decl.property
    assert_equal 'blue', decl.value
    assert decl.important

    # E2E: Round-trip should match exactly
    assert_equal css, sheet.to_s
  end

  def test_to_s_groups_consecutive_media_rules
    # Normalized fixture - consecutive @media rules should group
    css_input = <<~CSS.chomp
      body { color: black; }
      @media screen { h1 { color: red; } }
      @media screen { h2 { color: blue; } }
      div { margin: 0; }
    CSS

    # Expected output groups consecutive screen rules
    css_expected = <<~CSS.chomp
      body { color: black; }
      @media screen {
      h1 { color: red; }
      h2 { color: blue; }
      }
      div { margin: 0; }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)

    # Check parsed structure
    assert_equal 4, sheet.rules.length

    assert_equal 'body', sheet.rules[0].selector

    assert_equal 'h1', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    assert_equal 'div', sheet.rules[3].selector

    # E2E: Should group consecutive @media rules
    assert_equal css_expected, sheet.to_s.chomp
  end

  def test_to_s_separates_non_consecutive_media_rules
    css = <<~CSS
      @media screen { h1 { color: red; } }
      body { color: black; }
      @media screen { h2 { color: blue; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Check parsed structure preserves order
    assert_equal 3, sheet.rules.length

    assert_equal 'h1', sheet.rules[0].selector

    assert_equal 'body', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    # Verify serialization creates TWO separate @media blocks
    # (because body rule interrupts the screen rules)
    output = sheet.to_s
    media_count = output.scan(/@media screen/).length

    assert_equal 2, media_count, 'Should create separate @media blocks when interrupted'

    # Verify order is preserved
    body_pos = output.index('body')
    first_media_pos = output.index('@media screen')
    second_media_pos = output.rindex('@media screen')

    assert_operator first_media_pos, :<, body_pos, 'First @media should come before body'
    assert_operator body_pos, :<, second_media_pos, 'Body should come before second @media'
  end

  def test_to_s_mixed_media_queries
    css = <<~CSS
      body { margin: 0; }
      @media screen { h1 { color: red; } }
      @media print { h2 { color: blue; } }
      @media screen { p { color: green; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Check parsed structure
    assert_equal 4, sheet.rules.length

    assert_equal 'body', sheet.rules[0].selector

    assert_equal 'h1', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    assert_equal 'p', sheet.rules[3].selector

    # Verify serialization preserves order
    output = sheet.to_s

    assert_operator output.index('body'), :<, output.index('@media screen')
    assert_operator output.index('@media screen'), :<, output.index('@media print')
    assert_operator output.index('@media print'), :<, output.rindex('@media screen')
  end

  def test_charset_round_trip
    css = '@charset "UTF-8";
.test { margin: 5px; }'
    sheet = Cataract::Stylesheet.parse(css)
    result = sheet.to_s

    # Parse again and verify charset preserved
    sheet2 = Cataract::Stylesheet.parse(result)

    assert_equal 'UTF-8', sheet2.charset
    assert_equal 1, sheet2.size
  end

  def test_to_css_alias
    css = 'body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    # to_css should be an alias for to_s
    assert_respond_to sheet, :to_css
    assert_equal sheet.to_s, sheet.to_css
  end

  def test_to_formatted_s_basic
    css = 'body { color: red; margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      body {
        color: red;
        margin: 10px;
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_to_formatted_s_with_media_query
    css = '@media print { .footer { color: blue; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      @media print {
        .footer {
          color: blue;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_to_formatted_s_mixed_rules_and_media
    css = 'body { color: red; } @media screen { div { margin: 5px; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      body {
        color: red;
      }

      @media screen {
        div {
          margin: 5px;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_to_formatted_s_with_keyframes
    css = <<~CSS
      @keyframes slideIn {
        0% { transform: translateX(-100%); opacity: 0; }
        100% { transform: translateX(0); opacity: 1; }
      }
      .animated { animation: slideIn 0.5s ease-in; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    formatted = sheet.to_formatted_s

    expected = <<~CSS
      @keyframes slideIn {
        0% {
          transform: translateX(-100%);
          opacity: 0;
        }
        100% {
          transform: translateX(0);
          opacity: 1;
        }
      }
      .animated {
        animation: slideIn 0.5s ease-in;
      }
    CSS

    assert_equal expected, formatted
  end

  def test_to_formatted_s_with_media_filtering
    css = <<~CSS
      body { color: black; }
      @media screen { .screen-only { display: block; } }
      @media print { .print-only { display: none; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Filter to only screen media
    screen_output = sheet.to_formatted_s(media: :screen)
    expected_screen = <<~CSS
      body {
        color: black;
      }

      @media screen {
        .screen-only {
          display: block;
        }
      }
    CSS

    assert_equal expected_screen, screen_output

    # Filter to only print media
    print_output = sheet.to_formatted_s(media: :print)
    expected_print = <<~CSS
      body {
        color: black;
      }

      @media print {
        .print-only {
          display: none;
        }
      }
    CSS

    assert_equal expected_print, print_output
  end

  def test_to_formatted_s_with_multiple_media_filtering
    css = <<~CSS
      body { margin: 0; }
      @media screen { .screen { color: blue; } }
      @media print { .print { color: black; } }
      @media handheld { .handheld { font-size: 12px; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Filter to multiple media types
    output = sheet.to_formatted_s(media: %i[screen print])

    # Should include screen and print, but not handheld
    assert_includes output, '@media screen'
    assert_includes output, '.screen'
    assert_includes output, '@media print'
    assert_includes output, '.print'
    refute_includes output, '@media handheld'
    refute_includes output, '.handheld'
  end
end
