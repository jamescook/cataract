require_relative 'media_type_matcher'

module Cataract
  # Add Ruby methods to the C-defined Rule struct
  # Rule = Struct.new(:selector, :declarations, :specificity, :media_query)
  class Rule
    include MediaTypeMatcher

    # Alias for css_parser compatibility
    alias_method :media_types, :media_query

    # Note: `declarations` returns Array<Declarations::Value> (the raw C struct field)
    # Wrap it if you need Declarations methods: Declarations.new(rule.declarations)

    # Property accessor for convenience (delegates to Declarations)
    # @param property [String] Property name
    # @return [String, nil] Property value with trailing semicolon, or nil if not found
    def [](property)
      Declarations.new(declarations)[property]
    end

    # Calculate specificity lazily if not set
    # @return [Integer] CSS specificity value
    def specificity
      return self[:specificity] unless self[:specificity].nil?

      # Calculate and cache
      calculated = Cataract.calculate_specificity(selector)
      self[:specificity] = calculated
      calculated
    end
  end
end
