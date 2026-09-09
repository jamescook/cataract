# frozen_string_literal: true

require 'minitest/autorun'
require 'cataract'

# Comprehensive CSS Specificity Calculation Tests
# Migrated from css_parser gem's test_css_parser_misc.rb
class TestSpecificity < Minitest::Test
  def test_calculating_specificity
    # from http://www.w3.org/TR/CSS21/cascade.html#specificity
    assert_equal 0,   Cataract::Backends.active.calculate_specificity('*')
    assert_equal 1,   Cataract::Backends.active.calculate_specificity('li')
    assert_equal 2,   Cataract::Backends.active.calculate_specificity('li:first-line')
    assert_equal 2,   Cataract::Backends.active.calculate_specificity('ul li')
    assert_equal 3,   Cataract::Backends.active.calculate_specificity('ul ol+li')
    assert_equal 11,  Cataract::Backends.active.calculate_specificity('h1 + *[rel=up]')
    assert_equal 13,  Cataract::Backends.active.calculate_specificity('ul ol li.red')
    assert_equal 21,  Cataract::Backends.active.calculate_specificity('li.red.level')
    assert_equal 100, Cataract::Backends.active.calculate_specificity('#x34y')

    # from http://www.hixie.ch/tests/adhoc/css/cascade/specificity/003.html
    assert_equal Cataract::Backends.active.calculate_specificity('div *'), Cataract::Backends.active.calculate_specificity('p')
    assert_operator Cataract::Backends.active.calculate_specificity('body div *'), :>, Cataract::Backends.active.calculate_specificity('div *')

    # other tests
    assert_equal 11, Cataract::Backends.active.calculate_specificity('h1[id|=123]')
  end

  def test_specificity_with_pseudo_classes
    # Pseudo-classes count as class selectors
    assert_equal 10, Cataract::Backends.active.calculate_specificity(':hover')
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a:hover')
    assert_equal 21, Cataract::Backends.active.calculate_specificity('a:link:visited')
  end

  def test_specificity_with_pseudo_elements
    # Pseudo-elements count as element selectors
    assert_equal 1, Cataract::Backends.active.calculate_specificity('::before')
    assert_equal 2, Cataract::Backends.active.calculate_specificity('p::first-line')
  end

  # Underscore is a valid CSS identifier character, so it must not terminate an
  # identifier in any of the four places specificity parsing consumes one: an id,
  # a class, a type selector, and a pseudo-class/element name. A parser that stops
  # at '_' silently counts the remainder as an extra type selector - which is how
  # ':foo_bar' scores 11 instead of 10, while '#foo_bar' and '.foo_bar' are fine.
  def test_specificity_with_underscores_in_identifiers
    assert_equal 100, Cataract::Backends.active.calculate_specificity('#foo_bar')
    assert_equal 10, Cataract::Backends.active.calculate_specificity('.foo_bar')
    assert_equal 1, Cataract::Backends.active.calculate_specificity('foo_bar')
    assert_equal 10, Cataract::Backends.active.calculate_specificity(':foo_bar')
    assert_equal 1, Cataract::Backends.active.calculate_specificity('::foo_bar')

    # A leading underscore is a valid identifier start, not a separate token.
    assert_equal 10, Cataract::Backends.active.calculate_specificity(':_private')

    # Combined with a type selector, the pseudo-class must still contribute
    # exactly one class-level unit.
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a:foo_bar')
  end

  # ============================================================================
  # Selectors Level 4 specificity - not yet implemented.
  #
  # Both backends currently agree with each other on all of the cases below, so
  # the dual-backend run stays green while both produce the wrong number. These
  # were found by diffing against an external reference implementation; the
  # expectations here are the spec's, not the current behaviour's.
  #
  # Level 4 says the specificity of :is(), :not() and :has() is that of the MOST
  # SPECIFIC selector in its argument list, and that :where() always contributes
  # zero. Note that single-argument cases such as :is(.a) and :has(.a) already
  # return the right number by coincidence - 10 is also what a plain unrecognised
  # pseudo-class scores - so they are not evidence the argument is being read.
  # ============================================================================

  def test_specificity_of_not_uses_most_specific_argument
    skip 'Selectors 4: :not() with a selector list sums its arguments instead of taking the maximum'

    # Single-argument :not() is already correct; the list forms are not.
    assert_equal 10, Cataract::Backends.active.calculate_specificity(':not(.a)')

    # Currently 20, 30 and 110 respectively - the arguments are being summed.
    assert_equal 10, Cataract::Backends.active.calculate_specificity(':not(.a, .b)')
    assert_equal 10, Cataract::Backends.active.calculate_specificity(':not(.a, .b, .c)')
    assert_equal 100, Cataract::Backends.active.calculate_specificity(':not(#a, .b)')
  end

  def test_specificity_of_is_uses_most_specific_argument
    skip 'Selectors 4: :is() argument list is not inspected; it scores as a plain pseudo-class'

    # Currently 10 - the '#b' argument is not counted at all.
    assert_equal 100, Cataract::Backends.active.calculate_specificity(':is(.a, #b)')
    assert_equal 1, Cataract::Backends.active.calculate_specificity(':is(div)')
  end

  def test_specificity_of_where_is_always_zero
    skip 'Selectors 4: :where() is not zeroed; it scores as a plain pseudo-class'

    # Currently 10 in both cases. :where() contributes nothing, whatever it wraps.
    assert_equal 0, Cataract::Backends.active.calculate_specificity(':where(.a)')
    assert_equal 0, Cataract::Backends.active.calculate_specificity(':where(#a)')
    assert_equal 1, Cataract::Backends.active.calculate_specificity('div:where(#a)')
  end

  def test_specificity_of_has_uses_most_specific_argument
    skip 'Selectors 4: :has() argument list is not inspected; it scores as a plain pseudo-class'

    # Currently 10 - the '#a' argument is not counted.
    assert_equal 100, Cataract::Backends.active.calculate_specificity(':has(#a)')
  end

  def test_specificity_with_attribute_selectors
    # Attribute selectors count as class selectors
    assert_equal 10, Cataract::Backends.active.calculate_specificity('[href]')
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a[href]')
    assert_equal 20, Cataract::Backends.active.calculate_specificity('[type][required]')

    # CSS2 attribute operators
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a[href="https://example.com"]')  # Exact match =
    assert_equal 11, Cataract::Backends.active.calculate_specificity('p[lang|="en"]')                  # Hyphen-separated |=
    assert_equal 11, Cataract::Backends.active.calculate_specificity('div[class~="button"]')           # Space-separated ~=

    # CSS3 attribute operators
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a[href^="https"]')   # Starts with ^=
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a[href$=".pdf"]')    # Ends with $=
    assert_equal 11, Cataract::Backends.active.calculate_specificity('a[href*="example"]') # Contains *=

    # Numeric attribute values
    assert_equal 11, Cataract::Backends.active.calculate_specificity('input[tabindex=0]')
    assert_equal 11, Cataract::Backends.active.calculate_specificity('div[data-id=123]')
  end

  def test_specificity_with_id_selectors
    # ID selectors have highest specificity
    assert_equal 100, Cataract::Backends.active.calculate_specificity('#main')
    assert_equal 101, Cataract::Backends.active.calculate_specificity('#main p')
    assert_equal 200, Cataract::Backends.active.calculate_specificity('#header #nav')
  end

  def test_specificity_with_combinators
    # Combinators don't affect specificity
    assert_equal 2, Cataract::Backends.active.calculate_specificity('div p')
    assert_equal 2, Cataract::Backends.active.calculate_specificity('div > p')
    assert_equal 2, Cataract::Backends.active.calculate_specificity('div + p')
    assert_equal 2, Cataract::Backends.active.calculate_specificity('div ~ p')
  end

  def test_specificity_complex_selectors
    # Complex real-world selectors
    assert_equal 111, Cataract::Backends.active.calculate_specificity('#content .post a')
    assert_equal 121, Cataract::Backends.active.calculate_specificity('#content .post a.external')
    assert_equal 103, Cataract::Backends.active.calculate_specificity('#sidebar ul li a') # #sidebar(100) + ul(1) + li(1) + a(1) = 103
    assert_equal 121, Cataract::Backends.active.calculate_specificity('#nav .menu-item:hover a') # #nav(100) + .menu-item(10) + :hover(10) + a(1) = 121
  end

  def test_specificity_with_namespace_prefixes
    # A namespace prefix (css-namespaces-3 qname grammar: prefix? '|' ident)
    # contributes nothing itself - only the local name after '|' counts as
    # the type selector, same as a bare "div" would.
    assert_equal 1, Cataract::Backends.active.calculate_specificity('svg|rect')
    assert_equal 1, Cataract::Backends.active.calculate_specificity('*|rect')  # any namespace
    assert_equal 1, Cataract::Backends.active.calculate_specificity('|rect')   # no namespace

    # The rest of the qualified name still counts normally
    assert_equal 111, Cataract::Backends.active.calculate_specificity('svg|rect.icon#logo')
    assert_equal 2, Cataract::Backends.active.calculate_specificity('svg|rect html|div')

    # Namespaced attribute selectors are unaffected (bracket contents are
    # already opaque to specificity counting)
    assert_equal 10, Cataract::Backends.active.calculate_specificity('[xlink|href]')
    assert_equal 10, Cataract::Backends.active.calculate_specificity('[*|href]')
  end
end
