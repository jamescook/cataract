# frozen_string_literal: true

require_relative '../test_helper'

class TestSelectorListFlattenDivergence < Minitest::Test
  include StylesheetTestHelper

  # Test that selector lists are preserved through flatten when rules don't diverge
  def test_selector_list_preserved_when_no_divergence
    css = <<~CSS
      a, b, c, d, e { border: 1px solid red; }
    CSS

    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: true })
    flat = sheet.flatten

    a_rule = flat.with_selector('a').first
    b_rule = flat.with_selector('b').first
    c_rule = flat.with_selector('c').first
    d_rule = flat.with_selector('d').first
    e_rule = flat.with_selector('e').first

    # All should have the same selector_list_id
    refute_nil a_rule.selector_list_id, "Rule 'a' should have selector_list_id"
    assert_equal a_rule.selector_list_id, b_rule.selector_list_id
    assert_equal a_rule.selector_list_id, c_rule.selector_list_id
    assert_equal a_rule.selector_list_id, d_rule.selector_list_id
    assert_equal a_rule.selector_list_id, e_rule.selector_list_id

    # Should be in selector_lists hash
    selector_lists = flat.instance_variable_get(:@_selector_lists)
    list_id = a_rule.selector_list_id

    assert selector_lists.key?(list_id), "Selector list #{list_id} should exist in @_selector_lists"

    rule_ids = selector_lists[list_id]

    assert_equal 5, rule_ids.length, 'Selector list should contain 5 rules'
  end

  # Test the specific bootstrap.css case that was failing
  def test_bootstrap_table_selectors_preserved
    css = <<~CSS
      thead,
      tbody,
      tfoot,
      tr,
      td,
      th {
        border: 0 solid inherit;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: true })
    flat = sheet.flatten

    thead_rule = flat.with_selector('thead').first
    tbody_rule = flat.with_selector('tbody').first
    tfoot_rule = flat.with_selector('tfoot').first
    tr_rule = flat.with_selector('tr').first
    td_rule = flat.with_selector('td').first
    th_rule = flat.with_selector('th').first

    # All should have the same selector_list_id since they all have identical declarations
    refute_nil thead_rule.selector_list_id, "Rule 'thead' should have selector_list_id"
    assert_equal thead_rule.selector_list_id, tbody_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, tfoot_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, tr_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, td_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, th_rule.selector_list_id

    # Should be in selector_lists hash
    selector_lists = flat.instance_variable_get(:@_selector_lists)
    list_id = thead_rule.selector_list_id

    assert selector_lists.key?(list_id), "Selector list #{list_id} should exist in @_selector_lists"

    rule_ids = selector_lists[list_id]

    assert_equal 6, rule_ids.length, 'Selector list should contain 6 rules'
  end

  # Test actual divergence case from bootstrap where one rule gets different declarations
  def test_bootstrap_table_selectors_with_divergence
    css = <<~CSS
      thead,
      tbody,
      tfoot,
      tr,
      td,
      th {
        border: 0 solid inherit;
      }

      th {
        text-align: left;
        border: 1px solid black;
      }
    CSS

    sheet = Cataract::Stylesheet.parse(css, parser: { selector_lists: true })
    flat = sheet.flatten

    thead_rule = flat.with_selector('thead').first
    tbody_rule = flat.with_selector('tbody').first
    tfoot_rule = flat.with_selector('tfoot').first
    tr_rule = flat.with_selector('tr').first
    td_rule = flat.with_selector('td').first
    th_rule = flat.with_selector('th').first

    # First 5 should still be grouped (thead, tbody, tfoot, tr, td)
    refute_nil thead_rule.selector_list_id, "Rule 'thead' should have selector_list_id"
    assert_equal thead_rule.selector_list_id, tbody_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, tfoot_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, tr_rule.selector_list_id
    assert_equal thead_rule.selector_list_id, td_rule.selector_list_id

    # th should have diverged (different declarations after cascade)
    assert_nil th_rule.selector_list_id, "Rule 'th' should NOT have selector_list_id (diverged)"

    # Should have matching declarations for the group
    assert_has_property({ border: '0 solid inherit' }, thead_rule)
    assert_has_property({ border: '0 solid inherit' }, tbody_rule)
    assert_has_property({ border: '0 solid inherit' }, tfoot_rule)
    assert_has_property({ border: '0 solid inherit' }, tr_rule)
    assert_has_property({ border: '0 solid inherit' }, td_rule)

    # th should have different declarations
    assert_has_property({ border: '1px solid black' }, th_rule)
    assert_has_property({ 'text-align': 'left' }, th_rule)

    # Selector list should contain 5 rules (not 6)
    selector_lists = flat.instance_variable_get(:@_selector_lists)
    list_id = thead_rule.selector_list_id
    rule_ids = selector_lists[list_id]

    assert_equal 5, rule_ids.length, 'Selector list should contain 5 rules (th diverged)'
  end
end
