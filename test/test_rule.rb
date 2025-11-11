require_relative 'test_helper'

class TestRule < Minitest::Test
  def test_equality_same_selector_and_declarations
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls2, 10, nil, nil)

    assert_equal rule1, rule2
  end

  def test_equality_different_id_same_content
    # Two rules with different IDs but same selector/declarations are logically equal
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(99, '.foo', decls, 10, nil, nil)

    assert_equal rule1, rule2, 'ID is an implementation detail, not part of logical equality'
  end

  def test_equality_different_specificity_same_selector
    # If selector is the same, specificity MUST be the same (it's derived)
    # But equality check should ignore specificity anyway
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls, 999, nil, nil) # wrong specificity!

    assert_equal rule1, rule2, 'Specificity is derived from selector, not part of equality check'
  end

  def test_equality_different_selector
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.bar', decls, 10, nil, nil)

    refute_equal rule1, rule2
  end

  def test_equality_different_declarations
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [Cataract::Declaration.new('color', 'blue', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls2, 10, nil, nil)

    refute_equal rule1, rule2
  end

  def test_equality_different_declaration_count
    decls1 = [Cataract::Declaration.new('color', 'red', false)]
    decls2 = [
      Cataract::Declaration.new('color', 'red', false),
      Cataract::Declaration.new('margin', '10px', false)
    ]

    rule1 = Cataract::Rule.new(0, '.foo', decls1, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls2, 10, nil, nil)

    refute_equal rule1, rule2
  end

  def test_equality_with_non_rule
    decls = [Cataract::Declaration.new('color', 'red', false)]
    rule = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)

    refute_equal rule, 'not a rule'
    refute_equal rule, nil
  end

  def test_eql_alias
    decls = [Cataract::Declaration.new('color', 'red', false)]

    rule1 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)
    rule2 = Cataract::Rule.new(0, '.foo', decls, 10, nil, nil)

    assert rule1.eql?(rule2), 'eql? should be aliased to =='
  end
end
