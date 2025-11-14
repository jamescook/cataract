class TestStylesheetSerialization < Minitest::Test
  # ============================================================================
  # Charset handling
  # ============================================================================

  def test_no_charset
    css = 'body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_nil sheet.charset

    expected = "body { color: red; }\n"

    assert_equal expected, sheet.to_s
  end

  def test_charset_serialization
    css = '@charset "UTF-8"; body { color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = "@charset \"UTF-8\";\nbody { color: red; }\n"

    assert_equal expected, sheet.to_s
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
    css_input = <<~CSS
      @media screen { h1 { color: red; } }
      body { color: black; }
      @media screen { h2 { color: blue; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)

    # Check parsed structure preserves order
    assert_equal 3, sheet.rules.length

    assert_equal 'h1', sheet.rules[0].selector

    assert_equal 'body', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    # Verify serialization creates TWO separate @media blocks
    # (because body rule interrupts the screen rules)
    expected = <<~CSS
      @media screen {
      h1 { color: red; }
      }
      body { color: black; }
      @media screen {
      h2 { color: blue; }
      }
    CSS

    assert_equal expected, sheet.to_s
  end

  def test_to_s_mixed_media_queries
    css_input = <<~CSS
      body { margin: 0; }
      @media screen { h1 { color: red; } }
      @media print { h2 { color: blue; } }
      @media screen { p { color: green; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)

    # Check parsed structure
    assert_equal 4, sheet.rules.length

    assert_equal 'body', sheet.rules[0].selector

    assert_equal 'h1', sheet.rules[1].selector

    assert_equal 'h2', sheet.rules[2].selector

    assert_equal 'p', sheet.rules[3].selector

    # Verify serialization preserves order and separates different media types
    expected = <<~CSS
      body { margin: 0; }
      @media screen {
      h1 { color: red; }
      }
      @media print {
      h2 { color: blue; }
      }
      @media screen {
      p { color: green; }
      }
    CSS

    assert_equal expected, sheet.to_s
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

    # Filter to multiple media types - should include screen and print, but not handheld
    expected = <<~CSS
      body {
        margin: 0;
      }

      @media screen {
        .screen {
          color: blue;
        }
      }

      @media print {
        .print {
          color: black;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s(media: %i[screen print])
  end

  def test_to_formatted_s_closes_media_block_before_regular_rule
    # Test that media blocks are properly closed when transitioning to non-media rules
    # This specifically tests the serializer's logic for closing media blocks
    css_input = <<~CSS.chomp
      @media screen { h1 { color: red; } }
      @media screen { h2 { color: blue; } }
      body { margin: 0; }
      p { padding: 0; }
    CSS

    # Expected: media rules should be grouped, then closed before body (formatted style)
    css_expected = <<~CSS
      @media screen {
        h1 {
          color: red;
        }
        h2 {
          color: blue;
        }
      }

      body {
        margin: 0;
      }

      p {
        padding: 0;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)
    output = sheet.to_formatted_s

    assert_equal css_expected, output
  end

  def test_flattened_shorthand_properties_are_present
    # Test that when rules are flattened and shorthands are recreated,
    # all declarations are present with correct values
    css_input = <<~CSS
      .test { color: black; margin: 0px; }
      .test { padding: 5px; }
      .test { border: 1px solid red; }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)
    flattened = sheet.flatten

    # After flatten, all declarations should be present
    result = Cataract::Declarations.new(flattened.rules.first.declarations).to_s

    assert_equal 'color: black; margin: 0px; padding: 5px; border: 1px solid red;', result
  end

  def test_flattened_multiple_shorthands_are_present
    # Test with multiple types of shorthand properties (margin, padding, border, background, font, list-style)
    # all mixed with regular properties
    css_input = <<~CSS
      .box { display: block; margin: 10px; }
      .box { color: blue; padding: 5px; }
      .box { list-style: circle inside; border: 2px solid black; }
      .box { font: bold 14px/1.5 Arial; background: white; }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)
    flattened = sheet.flatten

    # All declarations should be present with correct values
    result = Cataract::Declarations.new(flattened.rules.first.declarations).to_s

    assert_equal 'display: block; color: blue; margin: 10px; padding: 5px; border: 2px solid black; list-style: circle inside; font: bold 14px/1.5 Arial; background: white;', result
  end

  def test_flattened_border_subproperties_are_present
    # Test that border-width, border-style, border-color get flattened into border shorthand
    css_input = <<~CSS
      .element { color: red; border-width: 1px; border-style: solid; border-color: black; }
      .element { margin: 5px; }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)
    flattened = sheet.flatten

    # Border shorthand should be created with all subproperties
    result = Cataract::Declarations.new(flattened.rules.first.declarations).to_s

    assert_equal 'color: red; margin: 5px; border: 1px solid black;', result
  end

  def test_flattened_important_declarations_maintain_order
    # Test that !important declarations maintain proper source order
    css_input = <<~CSS
      .test { color: black !important; margin: 10px; }
      .test { padding: 5px !important; }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)
    flattened = sheet.flatten

    result = Cataract::Declarations.new(flattened.rules.first.declarations).to_s

    assert_equal 'color: black !important; margin: 10px; padding: 5px !important;', result
  end

  # ============================================================================
  # Media query serialization tests
  # ============================================================================

  def test_to_s_media_type_only
    # Simple media type without features
    css = '@media print { .print-only { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media print {
      .print-only { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_single_media_feature
    # Single media feature in parentheses - MUST preserve parentheses per CSS spec
    css = '@media (min-width: 768px) { .wide { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media (min-width: 768px) {
      .wide { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_media_type_and_feature
    # Media type combined with feature using 'and'
    css = '@media screen and (min-width: 768px) { .desktop { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media screen and (min-width: 768px) {
      .desktop { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_multiple_features_with_and
    # Multiple media features combined with 'and'
    css = '@media (min-width: 768px) and (max-width: 1024px) { .tablet { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media (min-width: 768px) and (max-width: 1024px) {
      .tablet { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_media_type_and_multiple_features
    # Media type with multiple features
    css = '@media screen and (min-width: 768px) and (max-width: 1024px) { .tablet { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media screen and (min-width: 768px) and (max-width: 1024px) {
      .tablet { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_media_feature_max_width
    # Test max-width feature
    css = '@media (max-width: 767px) { .mobile { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media (max-width: 767px) {
      .mobile { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_media_feature_orientation
    # Test orientation feature
    css = '@media (orientation: landscape) { .landscape { width: 100%; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media (orientation: landscape) {
      .landscape { width: 100%; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_media_feature_aspect_ratio
    # Test aspect-ratio feature
    css = '@media (aspect-ratio: 16/9) { .widescreen { display: block; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media (aspect-ratio: 16/9) {
      .widescreen { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_media_feature_resolution
    # Test resolution feature
    css = '@media (min-resolution: 2dppx) { .retina { background-size: cover; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS.chomp
      @media (min-resolution: 2dppx) {
      .retina { background-size: cover; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_groups_consecutive_identical_media_queries
    # Consecutive identical media queries should be grouped
    css_input = <<~CSS
      @media (min-width: 768px) { .nav { display: flex; } }
      @media (min-width: 768px) { .header { padding: 20px; } }
      p { margin: 0; }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)

    expected = <<~CSS.chomp
      @media (min-width: 768px) {
      .nav { display: flex; }
      .header { padding: 20px; }
      }
      p { margin: 0; }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_separates_different_media_queries
    # Different media queries should NOT be grouped
    css_input = <<~CSS
      @media (min-width: 768px) { .desktop { display: block; } }
      @media (max-width: 767px) { .mobile { display: block; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)

    expected = <<~CSS.chomp
      @media (min-width: 768px) {
      .desktop { display: block; }
      }
      @media (max-width: 767px) {
      .mobile { display: block; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_s_mixed_media_types_and_queries
    # Mix of simple media types and complex queries
    css_input = <<~CSS
      @media print { .print { color: black; } }
      @media (min-width: 768px) { .wide { max-width: 1200px; } }
      @media screen and (orientation: landscape) { .screen-landscape { display: flex; } }
    CSS

    sheet = Cataract::Stylesheet.parse(css_input)

    expected = <<~CSS.chomp
      @media print {
      .print { color: black; }
      }
      @media (min-width: 768px) {
      .wide { max-width: 1200px; }
      }
      @media screen and (orientation: landscape) {
      .screen-landscape { display: flex; }
      }
    CSS

    assert_equal expected, sheet.to_s.chomp
  end

  def test_to_formatted_s_with_single_media_feature
    css = '@media (orientation: landscape) { .wide { width: 100%; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      @media (orientation: landscape) {
        .wide {
          width: 100%;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end

  def test_to_formatted_s_with_complex_media_query
    css = '@media screen and (min-width: 768px) and (max-width: 1024px) { .tablet { padding: 10px; } }'
    sheet = Cataract::Stylesheet.parse(css)

    expected = <<~CSS
      @media screen and (min-width: 768px) and (max-width: 1024px) {
        .tablet {
          padding: 10px;
        }
      }
    CSS

    assert_equal expected, sheet.to_formatted_s
  end
end
