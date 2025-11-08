# frozen_string_literal: true

# Test helpers for Stylesheet tests
# Provides high-level assertions that work with parsed CSS structures
module StylesheetTestHelper
  # Assert that an object (NewStylesheet or NewRule) matches a media query
  #
  # @param media [Symbol] Media query symbol (:screen, :print, :all, etc)
  # @param object [NewStylesheet, NewRule] Object to check
  #
  # For NewStylesheet: checks if any rules exist for that media query
  # For NewRule: checks if the rule is indexed under that media query
  def assert_matches_media(media, object)
    case object
    when Cataract::NewStylesheet
      if media == :all
        refute_empty object.rules, 'Expected stylesheet to have rules for :all media'
      else
        rule_ids = object.media_index[media]

        refute_nil rule_ids, "Expected stylesheet to have media index entry for #{media.inspect}"
        refute_empty rule_ids, "Expected stylesheet to have rules for media #{media.inspect}"
      end
    when Cataract::NewRule
      # Need the stylesheet to check media_index - this is a bit awkward
      # Maybe this form isn't as useful for individual rules?
      flunk 'assert_matches_media for NewRule requires stylesheet context - use assert_rule_in_media instead'
    else
      flunk "assert_matches_media expects NewStylesheet or NewRule, got #{object.class}"
    end
  end

  # Assert that a rule is in a specific media query
  #
  # @param rule [NewRule] The rule to check
  # @param media [Symbol] Media query symbol
  # @param stylesheet [NewStylesheet] The stylesheet containing the rule
  def assert_rule_in_media(rule, media, stylesheet)
    rule_ids = stylesheet.media_index[media]

    assert rule_ids, "Expected stylesheet to have media index entry for #{media.inspect}"
    assert_includes rule_ids, rule.id,
                    "Expected rule '#{rule.selector}' (id=#{rule.id}) to be in media #{media.inspect}, but media_index[#{media.inspect}] = #{rule_ids.inspect}"
  end

  # Assert that an object has a CSS property with expected value
  #
  # @param expected [Hash] Hash of property => value (e.g., {color: "red"})
  # @param object [NewRule, AtRule, Array<NewDeclaration>] Object to check
  # @param message [String] Optional failure message
  def assert_has_property(expected, object, message = nil)
    property, value = expected.first
    property = property.to_s

    declarations = case object
                   when Cataract::NewRule
                     object.declarations
                   when Cataract::AtRule
                     object.content # For @font-face, content is Array of NewDeclaration
                   when Array
                     object
                   else
                     flunk "assert_has_property expects NewRule, AtRule, or Array of declarations, got #{object.class}"
                   end

    decl = declarations.find { |d| d.property == property }

    assert decl, message || "Expected to find property '#{property}' in declarations, but got: #{declarations.map(&:property).inspect}" # rubocop:disable Minitest/AssertWithExpectedArgument

    # Combine value with !important flag if present
    actual_value = decl.important ? "#{decl.value} !important" : decl.value

    assert_equal value, actual_value,
                 message || "Expected property '#{property}' to have value #{value.inspect}, but got #{actual_value.inspect}"
  end

  # Assert that a stylesheet has rules matching a selector
  #
  # @param selector [String] CSS selector to find
  # @param stylesheet [NewStylesheet] Stylesheet to search
  # @param media [Symbol] Optional media query filter (default: :all)
  # @param count [Integer, nil] Expected number of matches (nil = any)
  # @param css_preview [String, nil] Optional CSS preview for error messages
  def assert_has_selector(selector, stylesheet, media: :all, count: nil, css_preview: nil)
    rules = stylesheet.find_by_selector(selector, media: media)

    if count
      assert_equal count, rules.length,
                   build_selector_error_message(selector, stylesheet, media, count, rules.length, css_preview)
    else
      refute_empty rules,
                   build_selector_error_message(selector, stylesheet, media, 'at least 1', 0, css_preview)
    end
  end

  # Assert that no rules match a selector
  #
  # @param selector [String] CSS selector that should not exist
  # @param stylesheet [NewStylesheet] Stylesheet to search
  # @param media [Symbol] Optional media query filter (default: :all)
  def assert_no_selector_matches(selector, stylesheet, media: :all)
    rules = stylesheet.find_by_selector(selector, media: media)

    assert_predicate rules, :empty?,
                     "Expected no rules to match selector #{selector.inspect} for media #{media.inspect}, but found #{rules.length}"
  end

  # Assert that each_selector yields expected selectors for a given media query
  #
  # @param expected_selectors [Array<String>] Expected selectors in order
  # @param stylesheet [NewStylesheet] The stylesheet
  # @param media [Symbol] Media query filter (default: :all)
  def assert_selectors_match(expected_selectors, stylesheet, media: :all)
    actual_selectors = []
    stylesheet.each_selector(media: media) do |rule|
      actual_selectors << rule.selector
    end

    assert_equal expected_selectors, actual_selectors,
                 "Expected selectors #{expected_selectors.inspect} for media #{media.inspect}, but got #{actual_selectors.inspect}"
  end

  # Assert that CSS round-trips (parses and serializes to same output)
  #
  # @param css [String] CSS to test
  def assert_round_trip(css)
    sheet = Cataract::NewStylesheet.parse(css)
    expected = css.strip
    actual = sheet.to_s.strip

    assert_equal expected, actual,
                 "CSS did not round-trip correctly.\n\nExpected:\n#{expected}\n\nGot:\n#{actual}"
  end

  # Assert that rules have expected declarations
  #
  # @param expected [String, Array<NewDeclaration>] Expected declarations
  # @param rules [Array<NewRule>] Rules from find_by_selector or similar
  #
  # If expected is a String, it should be semicolon-separated declarations like "color: red; margin: 0"
  # Declaration order doesn't matter - this checks that all expected declarations exist.
  def assert_declarations(expected, rules)
    # Get actual declarations from rules
    actual_decls = rules.flat_map(&:declarations)

    case expected
    when String
      # Parse expected string into individual declarations
      expected_parsed = Cataract::NewStylesheet.parse(".dummy { #{expected} }")
      expected_decls = expected_parsed.rules.first.declarations

      # Check count matches
      assert_equal expected_decls.length, actual_decls.length,
                   "Expected #{expected_decls.length} declarations, got #{actual_decls.length}"

      # Check each expected declaration exists in actual (order-independent)
      expected_decls.each do |exp_decl|
        match = actual_decls.find { |act| act.property == exp_decl.property && act.value == exp_decl.value }

        assert match, "Expected declaration '#{exp_decl.property}: #{exp_decl.value}' not found in actual declarations: #{actual_decls.map { |d| "#{d.property}: #{d.value}" }.join('; ')}"
      end
    when Array
      # If it's an array of declarations, compare directly (order-independent)
      assert_equal expected.length, actual_decls.length,
                   "Expected #{expected.length} declarations, got #{actual_decls.length}"

      expected.each do |exp_decl|
        match = actual_decls.find { |act| act.property == exp_decl.property && act.value == exp_decl.value }

        assert match, "Expected declaration '#{exp_decl.property}: #{exp_decl.value}' not found"
      end
    else
      flunk "assert_declarations expects String or Array, got #{expected.class}"
    end
  end

  # Assert that a selector or rule has expected specificity
  #
  # @param expected [Integer] Expected specificity value
  # @param selector_or_rule [String, NewRule] Either a selector string or a Rule object
  #
  # @example With rule object
  #   rule = @sheet.find_by_selector('div > p').first
  #   assert_specificity(2, rule)
  #
  # @example With selector string
  #   assert_specificity(2, 'div > p')
  def assert_specificity(expected, selector_or_rule)
    rule = case selector_or_rule
           when Cataract::NewRule
             selector_or_rule
           when String
             # Parse selector as CSS to get a rule with specificity
             temp_sheet = Cataract::NewStylesheet.parse("#{selector_or_rule} { color: red; }")

             assert_equal 1, temp_sheet.rules.length, "Failed to parse selector #{selector_or_rule.inspect}"
             temp_sheet.rules.first
           else
             flunk "assert_specificity expects NewRule or String selector, got #{selector_or_rule.class}"
           end

    assert_equal expected, rule.specificity,
                 "Expected selector '#{rule.selector}' to have specificity #{expected}, but got #{rule.specificity}"
  end

  # Assert that stylesheet has expected number of selectors
  #
  # @param expected_count [Integer] Expected number of selectors
  # @param stylesheet [NewStylesheet] Stylesheet to check
  # @param media [Symbol] Optional media query filter (default: :all)
  #
  # @example Check total selector count
  #   assert_selector_count(5, @sheet)
  #
  # @example Check selector count for specific media
  #   assert_selector_count(2, @sheet, media: :screen)
  def assert_selector_count(expected_count, stylesheet, media: :all)
    actual_count = stylesheet.each_selector(media: media).count

    assert_equal expected_count, actual_count,
                 "Expected #{expected_count} selector(s) for media #{media.inspect}, but got #{actual_count}"
  end

  # Assert that a rule has expected media types
  #
  # @param expected [Array<Symbol>] Expected media types (e.g., [:screen, :print] or [:all])
  # @param rule [NewRule] Rule to check
  # @param stylesheet [NewStylesheet] Stylesheet containing the rule
  #
  # @example
  #   rule = @sheet.find_by_selector('.header').first
  #   assert_media_types([:screen, :print], rule, @sheet)
  def assert_media_types(expected, rule, stylesheet)
    # Find which media index entries contain this rule ID
    media_keys = stylesheet.media_index.select { |_media, ids| ids.include?(rule.id) }.keys

    # Extract media types from each key using C parser
    # This handles complex queries like "screen (min-width: 400px)" => [:screen]
    # and compound queries like "screen, print" => [:screen, :print]
    actual = media_keys.flat_map { |key| Cataract.parse_media_types(key) }.uniq.sort

    # If not in any media query, it's a base rule (applies to :all)
    actual = [:all] if actual.empty?

    assert_equal expected.sort, actual,
                 "Expected rule '#{rule.selector}' to have media types #{expected.inspect}, but got #{actual.inspect}"
  end

  private

  # Build a helpful error message for selector assertions
  def build_selector_error_message(selector, stylesheet, media, expected_count, actual_count, css_preview)
    msg = "Expected to find #{expected_count} rule(s) with selector #{selector.inspect}"
    msg += " in media #{media.inspect}" unless media == :all
    msg += ", but found #{actual_count}"

    if css_preview
      preview = css_preview.strip.lines.first(3).join.chomp
      preview += '...' if css_preview.lines.count > 3
      msg += "\n\nCSS preview:\n#{preview}"
    elsif stylesheet
      # Show available selectors
      available = stylesheet.selectors.first(10)
      msg += "\n\nAvailable selectors: #{available.inspect}"
      msg += '...' if stylesheet.selectors.length > 10
    end

    msg
  end
end
