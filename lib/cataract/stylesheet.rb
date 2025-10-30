# frozen_string_literal: true

module Cataract
  # Stylesheet wraps parsed CSS rules grouped by media query
  # Structure: {query_string => {media_types: [...], rules: [...]}}
  # This is analogous to CssParser::Parser
  class Stylesheet
    include Enumerable

    attr_reader :rule_groups, :charset

    def initialize(rule_groups, charset = nil)
      @rule_groups = rule_groups # Hash: {query_string => {media_types: [...], rules: [...]}}
      @charset = charset
      @resolved = nil
      @serialized = nil
    end

    # Iterate over all rules across all media query groups
    def each(&block)
      return enum_for(:each) unless block_given?

      @rule_groups.each_value do |group|
        group[:rules].each(&block)
      end
    end

    # Alias for compatibility
    def rules
      each
    end

    # Compact format
    def to_s
      Cataract.stylesheet_to_s_c(@rule_groups, @charset)
    end

    # Multi-line format with 2-space indentation
    def to_formatted_s
      Cataract.stylesheet_to_formatted_s_c(@rule_groups, @charset)
    end

    # Add more CSS to this stylesheet
    def add_block!(css)
      result = Cataract.parse_css_internal(css)
      # parse_css_internal returns {rules: {query_string => {media_types: [...], rules: [...]}}, charset: "..." | nil}
      # Merge rule groups
      result[:rules].each do |query_string, new_group|
        existing_group = @rule_groups[query_string]
        if existing_group
          # Merge rules arrays
          existing_group[:rules].concat(new_group[:rules])
        else
          @rule_groups[query_string] = new_group
        end
      end
      @resolved = nil
      @serialized = nil
      self
    end

    def declarations
      # Flatten all rules for cascade
      all_rules = []
      @rule_groups.each_value { |group| all_rules.concat(group[:rules]) }
      @declarations ||= Cataract.apply_cascade(all_rules)
    end

    # Iterate over each selector across all rules
    # Yields: selector, declarations_string, specificity, media_types
    #
    # @param media [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    # @param specificity [Integer, Range] Filter by specificity (exact value or range)
    # @param property [String] Filter by CSS property name (e.g., 'color', 'position')
    # @param property_value [String] Filter by CSS property value (e.g., 'relative', 'red')
    # @yield [selector, declarations_string, specificity, media_types]
    # @return [Enumerator] if no block given
    #
    # Examples:
    #   sheet.each_selector { |sel, decls, spec, media| ... }  # All selectors
    #   sheet.each_selector(media: :print) { |sel, decls, spec, media| ... }  # Only print media
    #   sheet.each_selector(specificity: 10) { |sel, decls, spec, media| ... }  # Exact specificity
    #   sheet.each_selector(specificity: 100..) { |sel, decls, spec, media| ... }  # High specificity (>= 100)
    #   sheet.each_selector(property: 'color') { |sel, decls, spec, media| ... }  # Any selector with 'color'
    #   sheet.each_selector(property_value: 'relative') { |sel, decls, spec, media| ... }  # Any property with value 'relative'
    #   sheet.each_selector(property: 'position', property_value: 'relative') { |sel, decls, spec, media| ... }  # Specific property-value
    #   sheet.each_selector(property: 'color', specificity: 100.., media: :print) { |sel, decls, spec, media| ... }  # Combined filters
    def each_selector(media: :all, specificity: nil, property: nil, property_value: nil)
      unless block_given?
        return enum_for(:each_selector, media: media, specificity: specificity, property: property,
                                        property_value: property_value)
      end

      query_media_types = Array(media).map(&:to_sym)

      @rule_groups.each_value do |group|
        # Filter by media types at group level
        group_media_types = group[:media_types] || []

        # :all matches everything
        # But specific media queries (like :screen, :print) should NOT match [:all] groups
        should_include = if query_media_types.include?(:all)
                           # :all means iterate everything
                           true
                         elsif group_media_types.include?(:all)
                           # Group is universal (no media query) - only include if querying for :all
                           false
                         else
                           # Check for intersection
                           group_media_types.intersect?(query_media_types)
                         end

        next unless should_include

        group[:rules].each do |rule|
          # Filter by specificity if provided
          if specificity
            rule_specificity = rule.specificity
            matches = case specificity
                      when Range
                        specificity.cover?(rule_specificity)
                      else
                        specificity == rule_specificity
                      end
            next unless matches
          end

          # Filter by property and/or property_value if provided
          if property || property_value
            has_match = false

            rule.declarations.each do |decl|
              # Check property name match (if specified)
              property_matches = property.nil? || decl.property == property

              # Check property value match (if specified)
              # Compare against raw value (without !important flag)
              value_matches = property_value.nil? || decl.value == property_value

              # If both filters specified, both must match
              # If only one specified, just that one must match
              if property_matches && value_matches
                has_match = true
                break
              end
            end

            next unless has_match
          end

          declarations_str = rule.declarations.map do |decl|
            val = decl.important ? "#{decl.value} !important" : decl.value
            "#{decl.property}: #{val}"
          end.join('; ')

          # Return the group's media_types, not from the rule
          yield rule.selector, declarations_str, rule.specificity, group[:media_types]
        end
      end
    end

    def size
      @rule_groups.values.sum { |group| group[:rules].length }
    end
    alias length size

    def empty?
      @rule_groups.empty? || @rule_groups.values.all? { |group| group[:rules].empty? }
    end

    def inspect
      total_rules = size
      if total_rules.zero?
        '#<Cataract::Stylesheet empty>'
      else
        # Get first 3 rules across all groups
        preview_rules = []
        @rule_groups.each_value do |group|
          preview_rules.concat(group[:rules])
          break if preview_rules.length >= 3
        end
        preview = preview_rules.first(3).map(&:selector).join(', ')
        more = total_rules > 3 ? ', ...' : ''
        resolved_info = @resolved ? ", #{@resolved.length} declarations resolved" : ''
        "#<Cataract::Stylesheet #{total_rules} rules: #{preview}#{more}#{resolved_info}>"
      end
    end
  end
end
