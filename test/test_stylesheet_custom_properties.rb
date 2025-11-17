# frozen_string_literal: true

require 'test_helper'

class TestStylesheetCustomProperties < Minitest::Test
  def test_custom_property_predicate_on_declaration
    decl = Cataract::Declaration.new('--color', 'red', false)

    assert_predicate decl, :custom_property?
  end

  def test_custom_property_predicate_on_regular_declaration
    decl = Cataract::Declaration.new('color', 'red', false)

    refute_predicate decl, :custom_property?
  end

  def test_custom_property_predicate_with_uppercase
    # Custom properties are case-sensitive per spec
    decl = Cataract::Declaration.new('--Color', 'red', false)

    assert_predicate decl, :custom_property?
  end

  def test_custom_properties_returns_all_definitions
    css = <<~CSS
      :root {
        --primary-color: #007bff;
        --spacing-unit: 8px;
        --font-stack: Arial, sans-serif;
      }
      .card {
        --card-bg: white;
        --card-padding: 1rem;
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties

    assert_equal 1, custom_props.size
    assert_equal 5, custom_props[:root].size
    assert_equal '#007bff', custom_props[:root]['--primary-color']
    assert_equal '8px', custom_props[:root]['--spacing-unit']
    assert_equal 'Arial, sans-serif', custom_props[:root]['--font-stack']
    assert_equal 'white', custom_props[:root]['--card-bg']
    assert_equal '1rem', custom_props[:root]['--card-padding']
  end

  def test_custom_properties_returns_hash
    css = ':root { --color: red; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_instance_of Hash, sheet.custom_properties
    assert_instance_of Hash, sheet.custom_properties[:root]
  end

  def test_custom_properties_empty_when_none_defined
    css = '.btn { color: red; margin: 10px; }'
    sheet = Cataract::Stylesheet.parse(css)

    assert_empty sheet.custom_properties
  end

  def test_custom_properties_with_multiple_rules_same_property
    # Later definitions should override earlier ones within same media context
    css = <<~CSS
      :root { --color: red; }
      .theme-dark { --color: blue; }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties

    # Both rules are in :root context, last one wins
    assert_equal 1, custom_props.size
    assert_equal 'blue', custom_props[:root]['--color']
  end

  def test_custom_properties_with_important
    css = '.btn { --color: red !important; }'
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties

    assert_equal 'red', custom_props[:root]['--color']
  end

  def test_custom_properties_in_media_queries
    css = <<~CSS
      :root { --color: red; }
      @media screen {
        :root { --color: blue; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties

    # Should have both contexts
    assert_equal 2, custom_props.size
    assert_equal 'red', custom_props[:root]['--color']
    assert_equal 'blue', custom_props[:screen]['--color']
  end

  def test_custom_properties_filter_by_media
    css = <<~CSS
      :root { --color: red; }
      @media screen {
        :root { --color: blue; }
      }
      @media print {
        :root { --color: green; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)

    # Filter to just :root
    root_props = sheet.custom_properties(media: :root)

    assert_equal 1, root_props.size
    assert_equal 'red', root_props[:root]['--color']

    # Filter to just :print
    print_props = sheet.custom_properties(media: :print)

    assert_equal 1, print_props.size
    assert_equal 'green', print_props[:print]['--color']

    # Filter to multiple
    multi_props = sheet.custom_properties(media: [:root, :print])

    assert_equal 2, multi_props.size
    assert_equal 'red', multi_props[:root]['--color']
    assert_equal 'green', multi_props[:print]['--color']
  end

  def test_custom_properties_only_in_media_block
    # Custom properties defined only inside @media blocks (no base-level)
    css = <<~CSS
      @media print {
        :root { --print-color: black; }
        .footer { --print-margin: 0; }
      }
      @media screen {
        :root { --screen-color: blue; }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties

    # Should not have :root context since no base-level custom properties
    refute custom_props.key?(:root)

    # Should have both media contexts
    assert_equal 2, custom_props.size
    assert_equal 2, custom_props[:print].size
    assert_equal 'black', custom_props[:print]['--print-color']
    assert_equal '0', custom_props[:print]['--print-margin']
    assert_equal 1, custom_props[:screen].size
    assert_equal 'blue', custom_props[:screen]['--screen-color']
  end

  def test_custom_properties_in_nested_selectors
    css = <<~CSS
      .card {
        --spacing: 1rem;

        .card-header {
          --header-bg: gray;
        }
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties

    assert_equal '1rem', custom_props[:root]['--spacing']
    assert_equal 'gray', custom_props[:root]['--header-bg']
  end

  def test_custom_properties_memoized
    css1 = ':root { --color: red; }'
    sheet = Cataract::Stylesheet.parse(css1)

    # Call twice - should return same object (memoized)
    first_call = sheet.custom_properties
    second_call = sheet.custom_properties

    assert_same first_call, second_call
  end

  def test_custom_properties_updated_after_add_block
    css1 = ':root { --color: red; }'
    css2 = '.btn { --spacing: 8px; }'

    sheet = Cataract::Stylesheet.parse(css1)
    first_props = sheet.custom_properties

    assert_equal 1, first_props.size
    assert_equal 1, first_props[:root].size
    assert_equal 'red', first_props[:root]['--color']

    # Add more CSS
    sheet.add_block(css2)
    second_props = sheet.custom_properties

    # Should have both properties now
    assert_equal 1, second_props.size
    assert_equal 2, second_props[:root].size
    assert_equal 'red', second_props[:root]['--color']
    assert_equal '8px', second_props[:root]['--spacing']
  end

  def test_custom_properties_with_complex_values
    css = <<~CSS
      :root {
        --gradient: linear-gradient(to right, red, blue);
        --shadow: 0 2px 4px rgba(0, 0, 0, 0.1), 0 4px 8px rgba(0, 0, 0, 0.2);
        --calc-value: calc(100% - 2rem);
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties[:root]

    assert_equal 'linear-gradient(to right, red, blue)', custom_props['--gradient']
    assert_equal '0 2px 4px rgba(0, 0, 0, 0.1), 0 4px 8px rgba(0, 0, 0, 0.2)', custom_props['--shadow']
    assert_equal 'calc(100% - 2rem)', custom_props['--calc-value']
  end

  def test_custom_property_names_are_case_sensitive
    css = <<~CSS
      :root {
        --Color: red;
        --color: blue;
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties[:root]

    # CSS custom properties are case-sensitive
    assert_equal 2, custom_props.size
    assert_equal 'red', custom_props['--Color']
    assert_equal 'blue', custom_props['--color']
  end

  def test_custom_properties_with_var_references
    css = <<~CSS
      :root {
        --primary: blue;
        --text: var(--primary);
      }
    CSS
    sheet = Cataract::Stylesheet.parse(css)
    custom_props = sheet.custom_properties[:root]

    # Should preserve the var() reference as-is (no resolution)
    assert_equal 'blue', custom_props['--primary']
    assert_equal 'var(--primary)', custom_props['--text']
  end
end
