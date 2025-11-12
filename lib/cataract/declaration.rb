# frozen_string_literal: true

module Cataract
  # Represents a CSS property declaration.
  #
  # Declaration is a Struct with fields: (property, value, important)
  #
  # @example Create a declaration
  #   decl = Cataract::Declaration.new('color', 'red', false)
  #   decl.property #=> "color"
  #   decl.value #=> "red"
  #   decl.important #=> false
  #
  # @attr [String] property CSS property name (lowercased)
  # @attr [String] value CSS property value
  # @attr [Boolean] important Whether the declaration has !important
  Declaration = Struct.new(:property, :value, :important) unless const_defined?(:Declaration)
end
