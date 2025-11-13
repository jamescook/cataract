class TestStylesheetChainable < Minitest::Test
  def test_with_property_basic
    css = <<~CSS
      body { color: red; margin: 0; }
      .header { padding: 10px; color: blue; }
      .footer { margin: 5px; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all rules with color property
    color_rules = sheet.with_property('color')

    assert_equal 2, color_rules.size
    assert_equal %w[body .header], color_rules.map(&:selector)

    # Find all rules with margin property
    margin_rules = sheet.with_property('margin')

    assert_equal 2, margin_rules.size
    assert_equal %w[body .footer], margin_rules.map(&:selector)

    # Find rules with padding property
    padding_rules = sheet.with_property('padding')

    assert_equal 1, padding_rules.size
    assert_equal '.header', padding_rules.first.selector
  end

  def test_with_property_and_value
    css = <<~CSS
      body { color: red; }
      .header { color: blue; }
      .footer { color: red; margin: 0; }
      .sidebar { position: absolute; }
      .content { position: relative; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find rules with color: red
    red_rules = sheet.with_property('color', 'red')

    assert_equal 2, red_rules.size
    assert_equal %w[body .footer], red_rules.map(&:selector)

    # Find rules with color: blue
    blue_rules = sheet.with_property('color', 'blue')

    assert_equal 1, blue_rules.size
    assert_equal '.header', blue_rules.first.selector

    # Find rules with position: absolute
    absolute_rules = sheet.with_property('position', 'absolute')

    assert_equal 1, absolute_rules.size
    assert_equal '.sidebar', absolute_rules.first.selector
  end

  def test_with_property_chainable
    css = <<~CSS
      body { color: red; }
      @media screen { .header { color: blue; } }
      @media print { .footer { color: red; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with media filter
    screen_color_rules = sheet.with_media(:screen).with_property('color')

    assert_equal 1, screen_color_rules.size
    assert_equal '.header', screen_color_rules.first.selector

    # Chain with property and value
    print_red_rules = sheet.with_media(:print).with_property('color', 'red')

    assert_equal 1, print_red_rules.size
    assert_equal '.footer', print_red_rules.first.selector
  end

  def test_with_selector_string
    css = <<~CSS
      body { color: red; }
      .header { padding: 10px; }
      .footer { margin: 5px; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find by exact string match
    body_rules = sheet.with_selector('body')

    assert_equal 1, body_rules.size
    assert_equal 'body', body_rules.first.selector

    header_rules = sheet.with_selector('.header')

    assert_equal 1, header_rules.size
    assert_equal '.header', header_rules.first.selector
  end

  def test_with_selector_regexp
    css = <<~CSS
      .btn-primary { color: blue; }
      .btn-secondary { color: gray; }
      .btn-danger { color: red; }
      .header { padding: 10px; }
      #main { margin: 0; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all .btn-* classes using regex
    btn_rules = sheet.with_selector(/\.btn-/)

    assert_equal 3, btn_rules.size
    assert_equal %w[.btn-primary .btn-secondary .btn-danger], btn_rules.map(&:selector)

    # Find all ID selectors
    id_rules = sheet.with_selector(/^#/)

    assert_equal 1, id_rules.size
    assert_equal '#main', id_rules.first.selector

    # Find selectors containing 'header'
    header_rules = sheet.with_selector(/header/)

    assert_equal 1, header_rules.size
    assert_equal '.header', header_rules.first.selector
  end

  def test_with_selector_chainable_with_regexp
    css = <<~CSS
      .btn-primary { color: blue; }
      @media screen { .btn-secondary { color: gray; } }
      @media print { .btn-danger { color: red; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain regex selector with media filter
    screen_btn_rules = sheet.with_media(:screen).with_selector(/\.btn-/)

    assert_equal 1, screen_btn_rules.size
    assert_equal '.btn-secondary', screen_btn_rules.first.selector
  end

  def test_base_only
    css = <<~CSS
      body { color: black; }
      @media screen { .screen { color: blue; } }
      div { margin: 0; }
      @media print { .print { color: red; } }
      p { padding: 5px; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Get only base rules (not in any @media)
    base = sheet.base_only

    assert_equal 3, base.size
    assert_equal %w[body div p], base.map(&:selector)

    # Should be chainable
    assert_kind_of Cataract::StylesheetScope, base
  end

  def test_base_only_chainable
    css = <<~CSS
      body { color: red; }
      div { color: blue; margin: 0; }
      @media screen { .screen { color: green; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with property filter
    base_with_color = sheet.base_only.with_property('color')

    assert_equal 2, base_with_color.size
    assert_equal %w[body div], base_with_color.map(&:selector)

    # Chain with specificity
    base_high_spec = sheet.base_only.with_specificity(1)

    assert_equal 2, base_high_spec.size
  end

  def test_with_at_rule_type_keyframes
    css = <<~CSS
      @keyframes fadeIn { 0% { opacity: 0; } 100% { opacity: 1; } }
      @keyframes slideIn { 0% { transform: translateX(-100%); } }
      body { color: red; }
      @font-face { font-family: 'MyFont'; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all @keyframes
    keyframes = sheet.with_at_rule_type(:keyframes)

    assert_equal 2, keyframes.size
    assert keyframes.all?(&:at_rule?)

    selectors = keyframes.map(&:selector)

    assert_member selectors, '@keyframes fadeIn'
    assert_member selectors, '@keyframes slideIn'
  end

  def test_with_at_rule_type_font_face
    css = <<~CSS
      @font-face { font-family: 'Font1'; src: url('font1.woff'); }
      @font-face { font-family: 'Font2'; src: url('font2.woff'); }
      body { color: red; }
      @keyframes fadeIn { 0% { opacity: 0; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all @font-face
    fonts = sheet.with_at_rule_type(:font_face)

    assert_equal 2, fonts.size
    assert fonts.all?(&:at_rule?)
    assert(fonts.all? { |r| r.selector == '@font-face' })
  end

  def test_with_at_rule_type_chainable
    css = <<~CSS
      @media screen {
        @keyframes slideIn { 0% { transform: translateX(-100%); } }
      }
      @keyframes fadeIn { 0% { opacity: 0; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with media filter
    screen_keyframes = sheet.with_media(:screen).with_at_rule_type(:keyframes)

    assert_equal 1, screen_keyframes.size
    assert_equal '@keyframes slideIn', screen_keyframes.first.selector
  end

  def test_with_important_basic
    css = <<~CSS
      body { color: red; }
      .header { color: blue !important; margin: 10px; }
      .footer { padding: 5px !important; font-size: 14px !important; }
      .sidebar { border: 1px solid; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find all rules with any !important declaration
    important_rules = sheet.with_important

    assert_equal 2, important_rules.size
    assert_equal %w[.header .footer], important_rules.map(&:selector)
  end

  def test_with_important_by_property
    css = <<~CSS
      body { color: red; }
      .header { color: blue !important; margin: 10px; }
      .footer { padding: 5px !important; color: green !important; }
      .sidebar { margin: 10px !important; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Find rules with color !important
    color_important = sheet.with_important('color')

    assert_equal 2, color_important.size
    assert_equal %w[.header .footer], color_important.map(&:selector)

    # Find rules with margin !important
    margin_important = sheet.with_important('margin')

    assert_equal 1, margin_important.size
    assert_equal '.sidebar', margin_important.first.selector

    # Find rules with padding !important
    padding_important = sheet.with_important('padding')

    assert_equal 1, padding_important.size
    assert_equal '.footer', padding_important.first.selector
  end

  def test_with_important_chainable
    css = <<~CSS
      body { color: red !important; }
      @media screen { .header { color: blue !important; } }
      @media print { .footer { margin: 0; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Chain with media filter
    screen_important = sheet.with_media(:screen).with_important

    assert_equal 1, screen_important.size
    assert_equal '.header', screen_important.first.selector

    # Chain with property
    screen_color_important = sheet.with_media(:screen).with_important('color')

    assert_equal 1, screen_color_important.size
    assert_equal '.header', screen_color_important.first.selector
  end

  def test_complex_filter_chaining
    css = <<~CSS
      body { color: red; z-index: 1; }
      @media screen {
        .header { color: blue !important; z-index: 100; }
        .nav { padding: 10px; }
        #sidebar { color: green; z-index: 150; }
      }
      @media print { .footer { color: black; } }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Complex chain: screen media + has z-index + high specificity + selector-based rules only
    result = sheet.with_media(:screen)
                  .with_property('z-index')
                  .with_specificity(10..)
                  .select(&:selector?)

    assert_equal 2, result.size
    assert_equal %w[.header #sidebar], result.map(&:selector)

    # Another complex chain: screen + !important + color property
    result2 = sheet.with_media(:screen)
                   .with_important('color')
                   .with_selector(/header/)

    assert_equal 1, result2.size
    assert_equal '.header', result2.first.selector
  end
end
