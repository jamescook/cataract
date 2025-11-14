require_relative '../test_helper'

class TestImportStatement < Minitest::Test
  def test_import_statement_basic
    css = '@import "styles.css";'
    sheet = Cataract::Stylesheet.parse(css)

    # No rules in main stylesheet
    assert_equal 0, sheet.size

    # Import stored in @_imports
    assert_equal 1, sheet.imports.length
    import = sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'styles.css', import.url
    assert_nil import.media
  end

  def test_import_statement_with_url_function
    css = "@import url('styles.css');"
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 0, sheet.size
    assert_equal 1, sheet.imports.length

    import = sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'styles.css', import.url
    assert_nil import.media
  end

  def test_import_statement_with_media_query
    css = '@import "mobile.css" screen and (max-width: 768px);'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 0, sheet.size
    assert_equal 1, sheet.imports.length

    import = sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'mobile.css', import.url
    assert_equal :'screen and (max-width: 768px)', import.media
  end

  def test_import_statement_with_simple_media_type
    css = '@import "print.css" print;'
    sheet = Cataract::Stylesheet.parse(css)

    assert_equal 0, sheet.size
    assert_equal 1, sheet.imports.length

    import = sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'print.css', import.url
    assert_equal :print, import.media
  end

  def test_multiple_imports_at_top
    css = <<~CSS
      @import "reset.css";
      @import "theme.css" screen;
      @import "print.css" print;
      body { color: red; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # 3 imports + 1 rule
    assert_equal 3, sheet.imports.length
    assert_equal 1, sheet.size

    import1 = sheet.imports[0]
    assert_kind_of Cataract::ImportStatement, import1
    assert_equal 'reset.css', import1.url
    assert_nil import1.media

    import2 = sheet.imports[1]
    assert_kind_of Cataract::ImportStatement, import2
    assert_equal 'theme.css', import2.url
    assert_equal :screen, import2.media

    import3 = sheet.imports[2]
    assert_kind_of Cataract::ImportStatement, import3
    assert_equal 'print.css', import3.url
    assert_equal :print, import3.media

    rule = sheet[0]
    assert_kind_of Cataract::Rule, rule
    assert_equal 'body', rule.selector
  end

  def test_import_after_charset_is_valid
    css = <<~CSS
      @charset "UTF-8";
      @import "styles.css";
      body { color: red; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # @charset is extracted separately, not a rule
    assert_equal 1, sheet.imports.length
    assert_equal 1, sheet.size

    import = sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'styles.css', import.url

    rule = sheet.rules.first

    assert_kind_of Cataract::Rule, rule
    assert_equal 'body', rule.selector

    # Charset should be stored on stylesheet
    assert_equal 'UTF-8', sheet.charset
  end

  def test_import_after_rule_is_ignored
    css = <<~CSS
      body { color: red; }
      @import "late.css";
      div { margin: 0; }
    CSS

    silence_warnings do
      sheet = Cataract::Stylesheet.parse(css)

      # Should only have the two rules, @import should be ignored
      assert_equal 0, sheet.imports.length, '@import after rules should be ignored'
      assert_equal 2, sheet.size
      assert_kind_of Cataract::Rule, sheet[0]
      assert_equal 'body', sheet[0].selector
      assert_kind_of Cataract::Rule, sheet[1]
      assert_equal 'div', sheet[1].selector
    end
  end

  def test_import_in_middle_is_ignored
    css = <<~CSS
      @import "first.css";
      body { color: red; }
      @import "second.css";
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # First import is valid, second is ignored
    assert_equal 1, sheet.imports.length
    assert_equal 1, sheet.size

    import = sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'first.css', import.url

    rule = sheet[0]

    assert_kind_of Cataract::Rule, rule
    assert_equal 'body', rule.selector
  end

  def test_import_statement_id_and_insertion_order
    css = <<~CSS
      @import "first.css";
      @import "second.css";
      body { color: red; }
    CSS

    sheet = Cataract::Stylesheet.parse(css)

    # Import IDs should reflect insertion order
    assert_equal 0, sheet.imports[0].id
    assert_equal 1, sheet.imports[1].id

    # Rule ID continues the sequence
    assert_equal 2, sheet.rules.first.id
  end
end
