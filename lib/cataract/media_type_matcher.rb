module Cataract
  # Shared logic for checking if a rule applies to given media types
  #
  # Classes including this module must provide a `media_types` or `media_query` method
  # that returns an array of media type symbols (or nil for :all)
  module MediaTypeMatcher
    # Check if this rule applies to given media types
    #
    # Behavior matches css_parser gem:
    # - Rules with media_types: [:all] ONLY match when querying for :all
    # - Querying for :all matches ALL rules
    # - Specific queries (:print, :screen) ONLY match rules with those media types
    #
    # @param media_types [Symbol, Array<Symbol>] Media type(s) to check
    # @return [Boolean] true if rule applies
    def applies_to_media?(query_media_types)
      media_array = Array(query_media_types).map(&:to_sym)

      # Get rule's media types (Rule uses media_query, RuleSet uses media_types)
      rule_media = if respond_to?(:media_query)
                     media_query || [:all]
                   else
                     @media_types || [:all]
                   end

      # If querying for :all, match ALL rules
      return true if media_array.include?(:all)

      # Check for intersection between rule's media types and query
      # Note: Universal rules ([:all]) will NOT match specific queries
      !(rule_media & media_array).empty?
    end
  end
end
