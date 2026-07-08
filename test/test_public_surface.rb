# frozen_string_literal: true

require_relative 'test_helper'

# Enforces the small, documented public surface at the Cataract module
# level and on the active backend module, so backend-internal implementation
# details (C plumbing, parser helpers, serializer internals) can't silently
# leak back onto a module that's meant to expose almost nothing directly.
class TestPublicSurface < Minitest::Test
  def test_cataract_module_exposes_only_the_documented_entry_points
    assert_equal %i[flatten parse_css], Cataract.singleton_methods(false).sort
  end

  def test_active_backend_exposes_only_its_primitive_contract
    # Native and pure now expose exactly the same primitive set - no more
    # backend-conditional expectations here.
    expected = %i[calculate_specificity expand_shorthand flatten parse parse_declarations
                  stylesheet_to_formatted_s stylesheet_to_s]

    # Native is a Module exposing module functions (singleton methods on
    # itself); Pure is a frozen instance exposing regular public instance
    # methods defined on its class - check whichever shape applies.
    backend = Cataract::Backends.active
    actual = backend.is_a?(Module) ? backend.singleton_methods(false) : backend.class.public_instance_methods(false)

    assert_equal expected, actual.sort
  end
end
