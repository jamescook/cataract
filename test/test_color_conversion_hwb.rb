# frozen_string_literal: true

require_relative 'test_helper'

class TestColorConversionHwb < Minitest::Test
  # Helper to parse, convert, and get declarations
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)
    Cataract::Declarations.new(sheet.declarations)
  end

  # Tests targeting hwb/hwba output

  def test_rgb_to_hwb
    decls = convert_and_get_declarations(
      '.test { color: rgb(255, 0, 0) }',
      from: :rgb, to: :hwb
    )
    assert_equal 'hwb(0 0% 0%)', decls['color']
  end

  def test_hex_to_hwb
    decls = convert_and_get_declarations(
      '.test { color: #ff0000 }',
      from: :hex, to: :hwb
    )
    assert_equal 'hwb(0 0% 0%)', decls['color']
  end

  def test_hwba_alias_uses_legacy_syntax
    decls = convert_and_get_declarations(
      '.test { color: #ff000080; }',
      to: :hwba
    )
    # :hwba should produce hwb() with alpha
    assert_match(/^hwb\(\d+ \d+% \d+% \/ 0\.50/, decls['color'])
  end
end
