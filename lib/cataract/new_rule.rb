# frozen_string_literal: true

module Cataract
  # Extension methods for NewRule struct
  # NewRule is defined in C as: Struct.new(:id, :selector, :declarations, :specificity)
  # Media query information is stored in NewStylesheet's @media_index
  class NewRule
    # Silence warning about method redefinition. We redefine below to lazily calculate
    # specificity
    undef_method :specificity if method_defined?(:specificity)

    # Calculate specificity lazily if not set
    # @return [Integer] CSS specificity value
    def specificity
      return self[:specificity] unless self[:specificity].nil?

      # Calculate and cache
      calculated = Cataract.calculate_specificity(selector)
      self[:specificity] = calculated
      calculated
    end

    # NewRule supports each_selector iteration
    # @return [Boolean] true
    def supports_each_selector?
      true
    end
  end
end
