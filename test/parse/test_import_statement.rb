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

    warnings = capture_warnings do
      @sheet = Cataract::Stylesheet.parse(css)
    end

    # First import is valid, second is ignored
    assert_equal 1, @sheet.imports.length
    assert_equal 1, @sheet.size

    import = @sheet.imports[0]

    assert_kind_of Cataract::ImportStatement, import
    assert_equal 'first.css', import.url

    rule = @sheet[0]

    assert_kind_of Cataract::Rule, rule
    assert_equal 'body', rule.selector

    # Should emit a warning about the second @import after rules
    assert_equal 1, warnings.length
    assert_match(/CSS @import ignored.*must appear before all rules/i, warnings.first) # rubocop:disable Cataract/BanAssertIncludes
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

  def test_import_statement_equality
    # Two imports with same url and media are equal
    import1 = Cataract::ImportStatement.new(0, 'styles.css', nil, false)
    import2 = Cataract::ImportStatement.new(99, 'styles.css', nil, true)

    assert_equal import1, import2, 'Imports with same url/media should be equal regardless of id/resolved'

    # Different URL means not equal
    import3 = Cataract::ImportStatement.new(0, 'other.css', nil, false)

    refute_equal import1, import3

    # Different media means not equal
    import4 = Cataract::ImportStatement.new(0, 'styles.css', :print, false)

    refute_equal import1, import4

    # eql? should work the same as ==
    assert import1.eql?(import2)
    refute import1.eql?(import3)
  end

  def test_import_statement_hash_contract
    # Hash contract: objects that are equal must have equal hashes
    import1 = Cataract::ImportStatement.new(0, 'styles.css', :screen, false)
    import2 = Cataract::ImportStatement.new(99, 'styles.css', :screen, true)
    import3 = Cataract::ImportStatement.new(0, 'other.css', :screen, false)

    # Equal objects must have equal hashes
    assert_equal import1, import2
    assert_equal import1.hash, import2.hash, 'Equal objects must have equal hash values'

    # Non-equal objects should (ideally) have different hashes
    refute_equal import1, import3
    # NOTE: We don't assert hash inequality since hash collisions are technically allowed,
    # but in practice they should differ
  end

  def test_import_statement_as_hash_key
    # Test that ImportStatements work properly as hash keys
    import1 = Cataract::ImportStatement.new(0, 'styles.css', nil, false)
    import2 = Cataract::ImportStatement.new(99, 'styles.css', nil, true) # Same url/media, different id
    import3 = Cataract::ImportStatement.new(1, 'other.css', nil, false)

    hash = {}
    hash[import1] = 'value1'
    hash[import3] = 'value3'

    # import2 is equal to import1, so should retrieve the same value
    assert_equal 'value1', hash[import2], 'Equal imports should access same hash entry'
    assert_equal 'value3', hash[import3]

    # Hash should only have 2 entries (import1 and import2 are the same key)
    assert_equal 2, hash.size
  end

  def test_import_statement_in_set
    # Test that ImportStatements work in Sets (requires proper hash/eql?)
    require 'set'

    import1 = Cataract::ImportStatement.new(0, 'styles.css', :screen, false)
    import2 = Cataract::ImportStatement.new(99, 'styles.css', :screen, true) # Equal to import1
    import3 = Cataract::ImportStatement.new(1, 'other.css', :screen, false)

    set = Set.new
    set.add(import1)
    set.add(import2) # Should not add (equal to import1)
    set.add(import3)

    # Set should deduplicate equal imports
    assert_equal 2, set.size, 'Set should deduplicate equal imports'
    assert_member set, import1
    assert_member set, import2, 'Equal import should be found in set'
    assert_member set, import3
  end

  def test_import_statement_array_uniq
    # Test that Array#uniq works with ImportStatements
    import1 = Cataract::ImportStatement.new(0, 'styles.css', nil, false)
    import2 = Cataract::ImportStatement.new(1, 'styles.css', nil, false) # Equal to import1
    import3 = Cataract::ImportStatement.new(2, 'other.css', nil, false)
    import4 = Cataract::ImportStatement.new(3, 'styles.css', nil, false) # Equal to import1

    arr = [import1, import2, import3, import4]
    unique = arr.uniq

    # Should have only 2 unique imports
    assert_equal 2, unique.size
    assert_equal 'styles.css', unique[0].url
    assert_equal 'other.css', unique[1].url
  end
end
