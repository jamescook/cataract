# frozen_string_literal: true

# Media types handling tests
# Based on css_parser gem's test_css_parser_media_types.rb
class TestParserMediaTypes < Minitest::Test
  def setup
    @sheet = Cataract::Stylesheet.new
  end

  def test_finding_by_media_type
    # from http://www.w3.org/TR/CSS21/media.html#at-media-rule
    @sheet.add_block(<<-CSS)
      @media print {
        body { font-size: 10pt }
      }
      @media screen {
        body { font-size: 13px }
      }
      @media screen, print {
        body { line-height: 1.2 }
      }
    CSS

    assert_declarations 'font-size: 10pt; line-height: 1.2', @sheet.with_media(:print).with_selector('body')
    assert_declarations 'font-size: 13px; line-height: 1.2', @sheet.with_media(:screen).with_selector('body')
  end

  def test_with_parenthesized_media_features
    @sheet.add_block(<<-CSS)
      body { color: black }
      @media screen and (width > 500px) {
        body { color: red }
      }
    CSS

    # :all returns ALL rules
    assert_declarations 'color: black; color: red', @sheet.with_media(:all).with_selector('body')

    # :screen returns ONLY the screen-specific rule (matches css_parser)
    assert_declarations 'color: red', @sheet.with_media(:screen).with_selector('body')
  end

  def test_finding_by_multiple_media_types
    @sheet.add_block(<<-CSS)
      @media print {
        body { font-size: 10pt }
      }
      @media handheld {
        body { font-size: 13px }
      }
      @media screen, print {
        body { line-height: 1.2 }
      }
    CSS

    # Query with array of media types
    results = @sheet.with_media(%i[screen handheld]).with_selector('body')

    assert_declarations 'font-size: 13px; line-height: 1.2', results
  end

  def test_adding_block_with_media_types
    @sheet.add_block(<<-CSS, media_types: [:screen])
      body { font-size: 10pt }
    CSS

    assert_declarations 'font-size: 10pt', @sheet.with_media(:screen).with_selector('body')
    assert_empty @sheet.with_media(:handheld).with_selector('body')
  end

  def test_adding_block_with_media_types_followed_by_general_rule
    @sheet.add_block(<<-CSS)
      @media print {
        body { font-size: 10pt }
      }

      body { color: black }
    CSS

    assert_includes @sheet.to_s, 'color: black'
  end

  def test_adding_rule_set_with_media_type
    @sheet.add_rule(selector: 'body', declarations: 'color: black', media_types: %i[handheld tty])
    @sheet.add_rule(selector: 'body', declarations: 'color: blue', media_types: :screen)

    assert_declarations 'color: black', @sheet.with_media(:handheld).with_selector('body')
  end

  def test_selecting_with_all_media_types
    @sheet.add_rule(selector: 'body', declarations: 'color: black', media_types: %i[handheld tty])
    # :all should match all media-specific rules
    assert_declarations 'color: black', @sheet.with_media(:all).with_selector('body')
  end

  def test_to_s_includes_media_queries
    @sheet.add_rule(selector: 'body', declarations: 'color: black', media_types: :screen)
    output = @sheet.to_s

    assert_includes output, '@media'
    assert_includes output, 'color: black'
  end

  def test_multiple_media_types_single_rule
    # Test that @media screen, print creates ONE rule with multiple media types
    # NOT multiple rules (one per media type)
    @sheet.add_block(<<-CSS)
      @media screen, print {
        .header { color: blue; }
      }
    CSS

    assert_equal 1, @sheet.rules_count

    # Verify the rule appears for both media types
    assert_declarations 'color: blue', @sheet.with_media(:screen).with_selector('.header')
    assert_declarations 'color: blue', @sheet.with_media(:print).with_selector('.header')
  end

  def test_media_types_rule_counting
    # Ensure rules are counted correctly across different media contexts
    @sheet.add_block(<<-CSS)
      body { margin: 0; }

      @media print {
        body { font-size: 10pt; }
        .header { padding: 10px; }
      }

      @media screen {
        .mobile-menu { display: block; }
      }

      @media screen, print {
        .universal { font-size: 14px; }
        #footer { margin-top: 20px; }
      }

      .sidebar { width: 250px; }
    CSS

    # 1 base body rule
    # 2 print rules (body, .header)
    # 1 screen rule (.mobile-menu)
    # 2 screen,print rules (.universal, #footer)
    # 1 base sidebar rule
    # Total: 7 rules
    assert_equal 7, @sheet.rules_count
  end

  def test_duplicate_selectors_different_media_types
    # Same selector should create separate rules for different media types
    @sheet.add_block(<<-CSS)
      body { color: black; }

      @media print {
        body { color: black; background: white; }
      }

      @media screen {
        body { color: #333; background: #fff; }
      }
    CSS

    assert_equal 3, @sheet.rules_count

    # All media should return all three rules
    all_body_rules = @sheet.with_media(:all).with_selector('body')

    assert_equal 3, all_body_rules.length

    # Print should return ONLY the print-specific rule (matches css_parser)
    print_body = @sheet.with_media(:print).with_selector('body')

    assert_equal 1, print_body.length
    assert_declarations 'background: white; color: black', print_body
  end

  def test_nested_rules_within_media_query
    # Test multiple selectors within a single media query
    @sheet.add_block(<<-CSS)
      @media screen {
        .header { color: blue; }
        .footer { color: red; }
        .sidebar { width: 200px; }
      }
    CSS

    assert_equal 3, @sheet.rules_count

    # All three should be screen-only
    assert_declarations 'color: blue', @sheet.with_media(:screen).with_selector('.header')
    assert_declarations 'color: red', @sheet.with_media(:screen).with_selector('.footer')
    assert_declarations 'width: 200px', @sheet.with_media(:screen).with_selector('.sidebar')

    # None should appear for print
    assert_empty @sheet.with_media(:print).with_selector('.header')
    assert_empty @sheet.with_media(:print).with_selector('.footer')
    assert_empty @sheet.with_media(:print).with_selector('.sidebar')
  end

  def test_media_types_preserved_in_each_selector
    @sheet.add_block(<<-CSS)
      .base { color: black; }

      @media screen, print {
        .multi { color: blue; }
      }

      @media handheld {
        .handheld { color: red; }
      }
    CSS

    base_rule = @sheet.with_selector('.base').first
    multi_rule = @sheet.with_selector('.multi').first
    handheld_rule = @sheet.with_selector('.handheld').first

    assert_media_types [:all], base_rule, @sheet
    assert_media_types %i[screen print], multi_rule, @sheet
    assert_media_types [:handheld], handheld_rule, @sheet
  end

  def test_to_s_with_all_media_types
    @sheet.add_block(<<-CSS)
      body { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .footer { color: red; } }
    CSS

    output = @sheet.to_s(media: :all)

    # Should include all rules
    assert_includes output, 'body { color: black; }'
    assert_includes output, '@media screen'
    assert_includes output, '.header { color: blue; }'
    assert_includes output, '@media print'
    assert_includes output, '.footer { color: red; }'
  end

  def test_to_s_with_screen_media_type_only
    @sheet.add_block(<<-CSS)
      body { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .footer { color: red; } }
    CSS

    output = @sheet.to_s(media: :screen)

    # Should only include screen rules
    assert_includes output, '@media screen'
    assert_includes output, '.header { color: blue; }'

    # Should NOT include universal or print rules
    refute_includes output, 'body { color: black; }'
    refute_includes output, '@media print'
    refute_includes output, '.footer { color: red; }'
  end

  def test_to_s_with_print_media_type_only
    @sheet.add_block(<<-CSS)
      body { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .footer { color: red; } }
    CSS

    output = @sheet.to_s(media: :print)

    # Should only include print rules
    assert_includes output, '@media print'
    assert_includes output, '.footer { color: red; }'

    # Should NOT include universal or screen rules
    refute_includes output, 'body { color: black; }'
    refute_includes output, '@media screen'
    refute_includes output, '.header { color: blue; }'
  end

  def test_to_s_with_multiple_media_types
    @sheet.add_block(<<-CSS)
      body { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .footer { color: red; } }
      @media handheld { .mobile { width: 100%; } }
    CSS

    output = @sheet.to_s(media: %i[screen print])

    # Should include screen and print rules
    assert_includes output, '@media screen'
    assert_includes output, '.header { color: blue; }'
    assert_includes output, '@media print'
    assert_includes output, '.footer { color: red; }'

    # Should NOT include universal or handheld rules
    refute_includes output, 'body { color: black; }'
    refute_includes output, '@media handheld'
    refute_includes output, '.mobile { width: 100%; }'
  end

  def test_add_block_with_media_override_to_existing_group
    # First add some screen rules
    @sheet.add_block(<<-CSS)
      @media screen {
        .header { color: blue; }
      }
    CSS

    assert_equal 1, @sheet.rules_count

    # Now add more CSS to the same screen media group using media_types override
    # This tests the rules_before.key?(query_string) == true branch
    @sheet.add_block('body { margin: 0; }', media_types: :screen)

    assert_equal 2, @sheet.rules_count

    # Both rules should be in screen media
    assert_selector_count 2, @sheet, media: :screen
    assert_has_selector '.header', @sheet, media: :screen
    assert_has_selector 'body', @sheet, media: :screen

    # Verify output groups them under same @media
    output = @sheet.to_s

    assert_includes output, '@media screen'
    assert_includes output, '.header { color: blue; }'
    assert_includes output, 'body { margin: 0; }'
  end

  def test_add_block_with_media_override_adds_to_existing_group_count
    # Start with a screen rule
    @sheet.add_block('@media screen { .header { color: blue; } }')
    initial_count = @sheet.rules_count

    assert_equal 1, initial_count

    # Add another rule to screen using override - should increment count
    @sheet.add_block('.footer { padding: 10px; }', media_types: :screen)

    assert_equal 2, @sheet.rules_count

    # Both should be accessible via screen filter
    assert_selector_count 2, @sheet, media: :screen
    assert_has_selector '.header', @sheet, media: :screen
    assert_has_selector '.footer', @sheet, media: :screen
  end

  def test_add_block_appends_to_existing_media_query_group
    # First add_block creates screen group
    @sheet.add_block('@media screen { .header { color: blue; } }')

    assert_equal 1, @sheet.rules_count

    # Second add_block adds MORE rules to the SAME screen group (not via override, but naturally)
    # This tests the rules_before.key?(query_string) && new_count > old_count branch
    @sheet.add_block('@media screen { .footer { padding: 10px; } .nav { margin: 5px; } }')

    assert_equal 3, @sheet.rules_count

    # All three should be in screen
    assert_selector_count 3, @sheet, media: :screen
    assert_has_selector '.header', @sheet, media: :screen
    assert_has_selector '.footer', @sheet, media: :screen
    assert_has_selector '.nav', @sheet, media: :screen
  end

  def test_add_block_with_override_extracts_from_existing_group
    # Create initial screen group
    @sheet.add_block('@media screen { .header { color: blue; } }')

    assert_equal 1, @sheet.rules_count

    # Add CSS that contains @media screen, but override to :print
    # This should:
    # 1. Parse and temporarily add .footer to screen group
    # 2. Detect screen group existed before (rules_before.key?)
    # 3. Extract the new rules from screen (new_count > old_count)
    # 4. Move them to print group instead
    @sheet.add_block('@media screen { .footer { padding: 10px; } }', media_types: :print)

    assert_equal 2, @sheet.rules_count

    # .header should stay in screen
    assert_selector_count 1, @sheet, media: :screen
    assert_has_selector '.header', @sheet, media: :screen

    # .footer should be in print (moved by override)
    assert_selector_count 1, @sheet, media: :print
    assert_has_selector '.footer', @sheet, media: :print
  end

  # ============================================================================
  # remove_rules! tests
  # ============================================================================

  def test_remove_rules_by_selector
    @sheet.add_block(<<-CSS)
      body { color: black; }
      .header { color: blue; }
      .footer { color: red; }
    CSS

    assert_equal 3, @sheet.rules_count

    @sheet.remove_rules!('.header { }')

    assert_equal 2, @sheet.rules_count
    assert_predicate @sheet.with_selector('body'), :any?
    assert_empty @sheet.with_selector('.header')
    assert_predicate @sheet.with_selector('.footer'), :any?
  end

  def test_remove_rules_by_selector_from_specific_media_type
    @sheet.add_block(<<-CSS)
      .header { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .header { color: red; } }
    CSS

    assert_equal 3, @sheet.rules_count

    # Remove .header only from screen
    @sheet.remove_rules!('.header { }', media_types: :screen)

    assert_equal 2, @sheet.rules_count

    # Universal .header should still exist
    assert_predicate @sheet.with_media(:all).with_selector('.header'), :any?

    # Screen .header should be gone
    assert_empty @sheet.with_media(:screen).with_selector('.header')

    # Print .header should still exist
    assert_predicate @sheet.with_media(:print).with_selector('.header'), :any?
  end

  def test_remove_rules_from_all_media_when_no_media_types_specified
    @sheet.add_block(<<-CSS)
      .header { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .header { color: red; } }
    CSS

    assert_equal 3, @sheet.rules_count

    # Remove .header from ALL media types
    @sheet.remove_rules!('.header { }')

    assert_equal 0, @sheet.rules_count
    assert_empty @sheet.with_media(:all).with_selector('.header')
    assert_empty @sheet.with_media(:screen).with_selector('.header')
    assert_empty @sheet.with_media(:print).with_selector('.header')
  end

  def test_remove_rules_cleans_up_empty_groups
    @sheet.add_block('@media screen { .header { color: blue; } }')

    assert_equal 1, @sheet.rules_count

    # Remove the only rule in the screen group
    @sheet.remove_rules!('.header { }', media_types: :screen)

    assert_equal 0, @sheet.rules_count

    # The screen media query should be completely removed
    assert_empty @sheet.media_queries
  end

  def test_remove_rules_with_multiple_media_types
    @sheet.add_block(<<-CSS)
      .header { color: black; }
      @media screen { .header { color: blue; } }
      @media print { .header { color: red; } }
      @media handheld { .header { color: green; } }
    CSS

    assert_equal 4, @sheet.rules_count

    # Remove .header from screen and print only
    @sheet.remove_rules!('.header { }', media_types: %i[screen print])

    assert_equal 2, @sheet.rules_count

    # Universal and handheld should remain
    assert_predicate @sheet.with_media(:all).with_selector('.header'), :any?
    assert_predicate @sheet.with_media(:handheld).with_selector('.header'), :any?

    # Screen and print should be gone
    assert_empty @sheet.with_media(:screen).with_selector('.header')
    assert_empty @sheet.with_media(:print).with_selector('.header')
  end
end
