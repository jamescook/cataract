require_relative 'test_helper'

class TestBackgroundNoneFlatten < Minitest::Test
  def test_background_none_preserved_after_flatten
    # This is the exact CSS from bootstrap.css that was producing
    # empty background declarations after flattening
    css = <<~CSS
      .nav-tabs .nav-link {
        margin-bottom: -1px;
        background: none;
        border: 1px solid transparent;
        border-top-left-radius: 0.25rem;
        border-top-right-radius: 0.25rem;
      }
      .nav-tabs .nav-link:hover, .nav-tabs .nav-link:focus {
        border-color: #e9ecef #e9ecef #dee2e6;
        isolation: isolate;
      }
      .nav-tabs .nav-link.active,
      .nav-tabs .nav-item.show .nav-link {
        color: #495057;
        background-color: #fff;
        border-color: #dee2e6 #dee2e6 #fff;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    flattened = sheet.flatten
    output = flattened.to_s

    # Parse the flattened output again
    reparsed = Cataract::Stylesheet.parse(output)

    # Get all declarations from flattened sheet
    flattened_decls = []
    flattened.rules.each do |rule|
      next unless rule.is_a?(Cataract::Rule)

      rule.declarations.each do |decl|
        flattened_decls << {
          selector: rule.selector,
          property: decl.property,
          value: decl.value,
          important: decl.important
        }
      end
    end

    # Get all declarations from reparsed sheet
    reparsed_decls = []
    reparsed.rules.each do |rule|
      next unless rule.is_a?(Cataract::Rule)

      rule.declarations.each do |decl|
        reparsed_decls << {
          selector: rule.selector,
          property: decl.property,
          value: decl.value,
          important: decl.important
        }
      end
    end

    # Verify no empty values in flattened
    flattened_decls.each do |decl|
      refute_nil decl[:value], "Flattened should not have nil values: #{decl[:selector]} { #{decl[:property]} }"
      refute_empty decl[:value], "Flattened should not have empty values: #{decl[:selector]} { #{decl[:property]} }"
    end

    # Verify no empty values in reparsed
    reparsed_decls.each do |decl|
      refute_nil decl[:value], "Reparsed should not have nil values: #{decl[:selector]} { #{decl[:property]} }"
      refute_empty decl[:value], "Reparsed should not have empty values: #{decl[:selector]} { #{decl[:property]} }"
    end

    # The declaration counts should match (flattened CSS should round-trip cleanly)
    assert_equal flattened_decls.length, reparsed_decls.length,
                 "Declaration count mismatch: flattened has #{flattened_decls.length}, reparsed has #{reparsed_decls.length}"

    # Verify the declarations match exactly
    assert_equal flattened_decls, reparsed_decls,
                 'Flattened and reparsed declarations should match exactly'
  end

  def test_nav_pills_background_none
    css = <<~CSS
      .nav-pills .nav-link {
        background: none;
        border: 0;
        border-radius: 0.25rem;
      }
      .nav-pills .nav-link.active,
      .nav-pills .show > .nav-link {
        color: #fff;
        background-color: #0d6efd;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css)
    flattened = sheet.flatten
    output = flattened.to_s
    reparsed = Cataract::Stylesheet.parse(output)

    # Count declarations in both
    flattened_count = flattened.rules.sum { |r| r.is_a?(Cataract::Rule) ? r.declarations.length : 0 }
    reparsed_count = reparsed.rules.sum { |r| r.is_a?(Cataract::Rule) ? r.declarations.length : 0 }

    assert_equal flattened_count, reparsed_count,
                 'Declaration counts should match after round-trip'
  end
end
