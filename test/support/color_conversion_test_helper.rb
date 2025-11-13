# frozen_string_literal: true

# Test helpers for color conversion tests
# Provides helpers to work with converted stylesheets
module ColorConversionTestHelper
  # Parse CSS, convert colors, and get declarations
  #
  # This helper flattens all rules in the stylesheet and returns the declarations
  # from the flattened result, wrapped in a Declarations object for convenient access.
  #
  # @param css [String] CSS to parse
  # @param options [Hash] Options to pass to convert_colors!
  # @return [Declarations] Declarations object with flattened declarations
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

    # Flatten all rules to get final cascaded declarations
    flattened = sheet.flatten

    # The flattened stylesheet should have exactly one rule with all declarations
    assert_equal 1, flattened.rules.length, "Expected flattened stylesheet to have 1 rule, got #{flattened.rules.length}"

    # Return Declarations object from the flattened rule
    Cataract::Declarations.new(flattened.rules.first.declarations)
  end
end
