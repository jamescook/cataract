# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class TestRuleIdSequential < Minitest::Test
  # This test verifies that rules are ALWAYS sequential by ID (rules[i].id == i)
  # This invariant is critical for performance optimizations in serialization
  # where we use direct array access (rules[rid]) instead of linear search (rules.find)

  def test_simple_rules_are_sequential
    css = <<~CSS
      .a { color: red; }
      .b { color: blue; }
      .c { color: green; }
    CSS

    sheet = Cataract.parse_css(css)

    assert_rules_sequential(sheet)
  end

  def test_nested_selectors_are_sequential
    css = <<~CSS
      .parent {
        color: red;

        .child {
          color: blue;

          .grandchild {
            color: green;
          }
        }

        .sibling {
          color: yellow;
        }
      }
    CSS

    sheet = Cataract.parse_css(css)

    assert_rules_sequential(sheet)
  end

  def test_media_queries_are_sequential
    css = <<~CSS
      body { color: black; }

      @media screen {
        .screen { display: block; }
      }

      @media print {
        .print { display: none; }
      }

      .footer { margin: 0; }
    CSS

    sheet = Cataract.parse_css(css)

    assert_rules_sequential(sheet)
  end

  def test_nested_imports_are_sequential
    Dir.mktmpdir do |dir|
      # Create nested import structure
      File.write(File.join(dir, 'level3.css'), '.level3 { color: purple; }')
      File.write(File.join(dir, 'level2.css'), "@import url('file://#{File.join(dir, 'level3.css')}'); .level2 { color: blue; }")
      File.write(File.join(dir, 'level1.css'), "@import url('file://#{File.join(dir, 'level2.css')}'); .level1 { color: green; }")

      css = "@import url('file://#{File.join(dir, 'level1.css')}'); .main { color: red; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      assert_rules_sequential(sheet)
    end
  end

  def test_complex_nested_imports_with_media_are_sequential
    Dir.mktmpdir do |dir|
      # Create complex import structure with media queries
      File.write(File.join(dir, 'mobile.css'), <<~CSS)
        .mobile { width: 100%; }
        @media screen {
          .mobile-screen { color: blue; }
        }
      CSS

      File.write(File.join(dir, 'desktop.css'), <<~CSS)
        .desktop { width: 1200px; }
        @media print {
          .desktop-print { display: none; }
        }
      CSS

      css = <<~CSS
        @import url('file://#{File.join(dir, 'mobile.css')}');
        @import url('file://#{File.join(dir, 'desktop.css')}') screen;
        body { margin: 0; }
        @media screen {
          body { padding: 10px; }
        }
      CSS

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      assert_rules_sequential(sheet)
    end
  end

  def test_deeply_nested_selectors_with_media_are_sequential
    css = <<~CSS
      .root {
        color: black;

        @media screen {
          .level1 {
            color: blue;

            .level2 {
              color: green;

              @media print {
                .level3 {
                  color: red;
                }
              }
            }
          }
        }
      }

      .separate { margin: 0; }
    CSS

    sheet = Cataract.parse_css(css)

    assert_rules_sequential(sheet)
  end

  def test_import_with_complex_nesting_and_media_are_sequential
    Dir.mktmpdir do |dir|
      # Create imported stylesheet with complex nesting:
      # - Top-level rules
      # - @media with nested selectors
      # - Nested @media within @media
      # - Nested selectors within nested @media
      File.write(File.join(dir, 'imported.css'), <<~CSS)
        .imported-top { color: black; }

        @media screen {
          .screen-rule {
            background: white;

            .nested-in-media {
              padding: 10px;
            }
          }

          @media (min-width: 768px) {
            .nested-media {
              font-size: 16px;

              .deeply-nested {
                margin: 5px;
              }
            }
          }
        }

        .imported-bottom { color: gray; }
      CSS

      # Main stylesheet also has complex nesting
      css = <<~CSS
        @import url('file://#{File.join(dir, 'imported.css')}');

        .main-top { display: block; }

        @media print {
          .print-rule {
            page-break: avoid;

            .nested-in-print {
              color: black;
            }
          }
        }

        .parent {
          width: 100%;

          @media (max-width: 480px) {
            .mobile-nested {
              width: auto;
            }
          }

          .child {
            height: 50px;
          }
        }

        .main-bottom { margin: 0; }
      CSS

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      # Verify sequential IDs
      assert_rules_sequential(sheet)

      # Verify parent_rule_id relationships are correct
      assert_parent_rule_ids_valid(sheet)
    end
  end

  def test_parent_rule_id_correctness_with_known_relationships
    css = <<~CSS
      .grandparent {
        color: red;

        .parent {
          color: blue;

          .child {
            color: green;
          }
        }
      }

      .root {
        margin: 0;

        @media screen {
          .nested-in-media {
            padding: 10px;
          }
        }
      }
    CSS

    sheet = Cataract.parse_css(css)

    # Build selector -> rule mapping
    rules_by_selector = {}
    sheet.rules.each { |r| rules_by_selector[r.selector] = r }

    # Verify known parent-child relationships
    grandparent = rules_by_selector['.grandparent']
    parent = rules_by_selector['.grandparent .parent']
    child = rules_by_selector['.grandparent .parent .child']

    assert_nil grandparent.parent_rule_id,
               '.grandparent should have no parent (top-level)'

    assert_equal grandparent.id, parent.parent_rule_id,
                 '.grandparent .parent should have .grandparent as parent'

    assert_equal parent.id, child.parent_rule_id,
                 '.grandparent .parent .child should have .grandparent .parent as parent'

    # Verify @media nested selector relationship
    # There are TWO .root rules: one top-level, one inside @media
    root_top_level = sheet.rules.find { |r| r.selector == '.root' && r.media_query_id.nil? }
    root_in_media = sheet.rules.find { |r| r.selector == '.root' && !r.media_query_id.nil? }
    nested_in_media = rules_by_selector['.root .nested-in-media']

    assert_nil root_top_level.parent_rule_id,
               '.root (top-level) should have no parent'

    assert_equal root_top_level.id, root_in_media.parent_rule_id,
                 '.root (in @media) should have .root (top-level) as parent'

    assert_equal root_in_media.id, nested_in_media.parent_rule_id,
                 '.root .nested-in-media should have .root (in @media) as parent'
  end

  def test_bootstrap_fixture_is_sequential
    # Test against real-world CSS
    fixture_path = File.join(__dir__, 'fixtures', 'bootstrap.css')
    return unless File.exist?(fixture_path)

    css = File.read(fixture_path)
    sheet = Cataract.parse_css(css)

    assert_rules_sequential(sheet)
  end

  def test_after_flatten_rules_are_sequential
    css = <<~CSS
      .a { color: red; margin: 10px; }
      .a { color: blue; }
      .b { color: green; }
    CSS

    sheet = Cataract.parse_css(css)
    flattened = Cataract.flatten(sheet)

    assert_rules_sequential(flattened)
  end

  private

  def assert_rules_sequential(stylesheet)
    stylesheet.rules.each_with_index do |rule, index|
      assert_equal index, rule.id,
                   "Rule at index #{index} has id=#{rule.id} (expected #{index}). " \
                   'Rules must be sequential: rules[i].id == i. ' \
                   'This invariant is required for O(1) array access in serialization.'
    end
  end

  def assert_parent_rule_ids_valid(stylesheet)
    stylesheet.rules.each do |rule|
      next if rule.parent_rule_id.nil?

      parent_id = rule.parent_rule_id

      # Verify parent_rule_id points to a valid rule
      assert parent_id >= 0 && parent_id < stylesheet.rules.length,
             "Rule '#{rule.selector}' (id=#{rule.id}) has invalid parent_rule_id=#{parent_id} " \
             "(out of bounds, max=#{stylesheet.rules.length - 1})"

      parent_rule = stylesheet.rules[parent_id]

      # Verify parent rule exists (not nil placeholder)
      refute_nil parent_rule,
                 "Rule '#{rule.selector}' (id=#{rule.id}) has parent_rule_id=#{parent_id} " \
                 "but rules[#{parent_id}] is nil"

      # Verify parent comes before child (parent_id < child_id)
      assert_operator parent_id, :<, rule.id, "Rule '#{rule.selector}' (id=#{rule.id}) has parent_rule_id=#{parent_id} " \
                                              'but parent should come before child in the array'
    end
  end
end
