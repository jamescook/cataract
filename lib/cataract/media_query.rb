# frozen_string_literal: true

module Cataract
  # MediaQuery represents a CSS media query constraint.
  #
  # Media queries are stored in the Stylesheet and referenced by Rules via media_query_id.
  # This allows efficient tracking of which rules apply to which media contexts.
  #
  # @example Access media query properties
  #   mq = MediaQuery.new(0, :screen, "(min-width: 768px)")
  #   mq.id #=> 0
  #   mq.type #=> :screen
  #   mq.conditions #=> "(min-width: 768px)"
  #   mq.text #=> "screen and (min-width: 768px)"
  #
  # @attr [Integer] id Unique identifier for this media query within the stylesheet
  # @attr [Symbol] type Primary media type (:screen, :print, :all, etc.)
  # @attr [String, nil] conditions Additional conditions like "(min-width: 768px)", or nil if none
  MediaQuery = Struct.new(:id, :type, :conditions) do
    # Create a MediaQuery with keyword arguments for readability.
    #
    # @param id [Integer] Unique ID for this media query
    # @param type [Symbol] Primary media type
    # @param conditions [String, nil] Optional conditions
    # @return [MediaQuery] New media query instance
    #
    # @example Create a simple media query
    #   MediaQuery.make(id: 0, type: :screen, conditions: nil)
    #
    # @example Create a media query with conditions
    #   MediaQuery.make(id: 1, type: :screen, conditions: "(min-width: 768px)")
    def self.make(id:, type:, conditions: nil)
      new(id, type, conditions)
    end

    # Get the full media query text.
    #
    # Reconstructs the media query string from type and conditions.
    #
    # @return [String] Full media query text
    #
    # @example Simple media query
    #   mq = MediaQuery.new(0, :screen, nil)
    #   mq.text #=> "screen"
    #
    # @example Media query with conditions
    #   mq = MediaQuery.new(0, :screen, "(min-width: 768px)")
    #   mq.text #=> "screen and (min-width: 768px)"
    def text
      if conditions
        # If type is :all, just return conditions (don't say "all and ...")
        type == :all ? conditions : "#{type} and #{conditions}"
      else
        type.to_s
      end
    end

    # Compare media queries for equality based on type and conditions.
    #
    # Two media queries are equal if they have the same type and conditions.
    # IDs are not considered since they're internal identifiers.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if media queries match
    def ==(other)
      case other
      when MediaQuery
        type == other.type && conditions == other.conditions
      else
        false
      end
    end
    alias_method :eql?, :==

    # Generate hash code for this media query.
    #
    # Hash is based on type and conditions to match equality semantics.
    #
    # @return [Integer] hash code
    def hash
      [self.class, type, conditions].hash
    end

    # Get a human-readable representation.
    #
    # @return [String] String representation
    def to_s
      text
    end

    # Get detailed inspection string.
    #
    # @return [String] Inspection string
    def inspect
      "#<MediaQuery id=#{id} type=#{type.inspect} conditions=#{conditions.inspect}>"
    end
  end
end
