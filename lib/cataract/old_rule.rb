# frozen_string_literal: true

module Cataract
  # Add Ruby methods to the C-defined Rule struct
  # Rule = Struct.new(:selector, :declarations, :specificity)
  class Rule
    # Property accessor for convenience (delegates to Declarations)
    # @param property_name [String] Property name
    # @return [String, nil] Property value with trailing semicolon, or nil if not found
    def property(property_name)
      declarations_wrapper[property_name]
    end

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

    private

    # @return [Declarations] Wrapped declarations object
    def declarations_wrapper
      @declarations_wrapper ||= Declarations.new(declarations)
    end
  end
end
