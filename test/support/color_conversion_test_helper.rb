# frozen_string_literal: true

# Test helpers for color conversion tests
# Provides helpers to work with converted stylesheets
module ColorConversionTestHelper
  # Parse CSS, convert colors, and get declarations
  #
  # This helper merges all rules in the stylesheet and returns the declarations
  # from the merged result, wrapped in a Declarations object for convenient access.
  #
  # @param css [String] CSS to parse
  # @param options [Hash] Options to pass to convert_colors!
  # @return [Declarations] Declarations object with merged declarations
  #
  # @example
  #   decls = convert_and_get_declarations(
  #     '.test { background-color: #ff0000; }',
  #     from: :hex, to: :rgb
  #   )
  #   assert_equal 'rgb(255, 0, 0)', decls['background-color']
  def convert_and_get_declarations(css, **options)
    sheet = Cataract.parse_css(css)
    sheet.convert_colors!(**options)

    # Merge all rules to get final cascaded declarations
    merged = sheet.merge

    # The merged stylesheet should have exactly one rule with all declarations
    assert_equal 1, merged.rules.length, "Expected merged stylesheet to have 1 rule, got #{merged.rules.length}"

    # Return Declarations object from the merged rule
    Cataract::Declarations.new(merged.rules.first.declarations)
  end
end
