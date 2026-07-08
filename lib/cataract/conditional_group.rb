# frozen_string_literal: true

module Cataract
  # ConditionalGroup represents a CSS "conditional group" at-rule wrapper -
  # @supports, @layer, @container, or @scope.
  #
  # Like MediaQuery, these are stored in the Stylesheet and referenced by
  # Rules/AtRules via conditional_group_id, so the rules they wrap stay flat
  # and queryable in Stylesheet#rules while the wrapper's own name/condition
  # (and nesting inside other conditional groups, via parent_id) survive for
  # round-trip serialization. Cataract never evaluates the condition/name
  # (no feature-query or container-query matching) - it's kept as opaque
  # text.
  #
  # @example Access conditional-group properties
  #   group = ConditionalGroup.new(0, :supports, nil, '(display: grid)', nil)
  #   group.id #=> 0
  #   group.type #=> :supports
  #   group.condition #=> "(display: grid)"
  #
  # @attr [Integer] id Unique identifier for this conditional group within the stylesheet
  # @attr [Symbol] type At-rule kind (:supports, :layer, :container, :scope)
  # @attr [String, nil] name Named form (e.g. `@layer utilities`, `@container sidebar`), nil if unnamed
  # @attr [String, nil] condition Opaque condition/prelude text (feature query, container query, scope root/limit), nil if none
  # @attr [Integer, nil] parent_id Id of the enclosing ConditionalGroup, or nil if not nested inside another one
  ConditionalGroup = Struct.new(:id, :type, :name, :condition, :parent_id) do
    # Create a ConditionalGroup with keyword arguments for readability.
    #
    # @param id [Integer] Unique ID for this conditional group
    # @param type [Symbol] At-rule kind (:supports, :layer, :container, :scope)
    # @param name [String, nil] Named form, if any
    # @param condition [String, nil] Opaque condition/prelude text, if any
    # @param parent_id [Integer, nil] Enclosing ConditionalGroup's id, if nested
    # @return [ConditionalGroup] New conditional group instance
    #
    # @example
    #   ConditionalGroup.make(id: 0, type: :supports, condition: '(display: grid)')
    def self.make(id:, type:, name: nil, condition: nil, parent_id: nil)
      new(id, type, name, condition, parent_id)
    end

    # Compare conditional groups for equality based on type, name, condition,
    # and nesting. IDs are not considered since they're internal identifiers.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if conditional groups match
    def ==(other)
      case other
      when ConditionalGroup
        type == other.type && name == other.name && condition == other.condition
      else
        false
      end
    end
    alias_method :eql?, :==

    # Generate hash code for this conditional group.
    #
    # @return [Integer] hash code
    def hash
      [self.class, type, name, condition].hash
    end

    # Get detailed inspection string.
    #
    # @return [String] Inspection string
    def inspect
      "#<ConditionalGroup id=#{id} type=#{type.inspect} name=#{name.inspect} " \
        "condition=#{condition.inspect} parent_id=#{parent_id.inspect}>"
    end
  end
end
