# frozen_string_literal: true

module Cataract
  # Chainable query scope for filtering Stylesheet rules.
  #
  # Inspired by ActiveRecord's Relation, StylesheetScope provides a fluent
  # interface for filtering and querying CSS rules. Scopes are lazy - filters
  # are only applied during iteration.
  #
  # @example Chaining filters
  #   sheet.with_media(:print).with_specificity(10..).select(&:selector?)
  #
  # @example Inspect shows results
  #   scope = sheet.with_media(:screen)
  #   scope.inspect #=> "#<Cataract::StylesheetScope [...]>"
  class StylesheetScope
    include Enumerable

    # @private
    def initialize(stylesheet, filters = {})
      @stylesheet = stylesheet
      @filters = filters
    end

    # Filter by media query symbol(s).
    #
    # @param media [Symbol, Array<Symbol>] Media query symbol(s)
    # @return [StylesheetScope] New scope with media filter applied
    #
    # @example
    #   sheet.with_media(:print).with_media(:screen) # overwrites to :screen
    def with_media(media)
      StylesheetScope.new(@stylesheet, @filters.merge(media: media))
    end

    # Filter by CSS specificity.
    #
    # @param specificity [Integer, Range] Specificity value or range
    # @return [StylesheetScope] New scope with specificity filter applied
    #
    # @example
    #   sheet.with_specificity(10)      # exactly 10
    #   sheet.with_specificity(10..)    # 10 or higher
    #   sheet.with_specificity(5...10)  # between 5 and 9
    def with_specificity(specificity)
      StylesheetScope.new(@stylesheet, @filters.merge(specificity: specificity))
    end

    # Filter by CSS selector.
    #
    # @param selector [String, Regexp] CSS selector to match (exact string or pattern)
    # @return [StylesheetScope] New scope with selector filter applied
    #
    # @example Exact string match
    #   sheet.with_selector('body')
    #   sheet.with_media(:print).with_selector('.header')
    #
    # @example Pattern matching
    #   sheet.with_selector(/\.btn-/)  # All .btn-* classes
    #   sheet.with_selector(/^#/)      # All ID selectors
    def with_selector(selector)
      StylesheetScope.new(@stylesheet, @filters.merge(selector: selector))
    end

    # Filter by CSS property name and optional value.
    #
    # @param property [String] CSS property name to match
    # @param value [String, nil] Optional property value to match
    # @param prefix_match [Boolean] Whether to match by prefix (default: false)
    # @return [StylesheetScope] New scope with property filter applied
    #
    # @example Find rules with color property
    #   sheet.with_property('color')
    #
    # @example Find rules with specific property value
    #   sheet.with_property('position', 'absolute')
    #   sheet.with_property('color', 'red')
    #
    # @example Find all margin-related properties (margin, margin-top, etc.)
    #   sheet.with_property('margin', prefix_match: true)
    def with_property(property, value = nil, prefix_match: false)
      StylesheetScope.new(@stylesheet, @filters.merge(property: property, property_value: value, property_prefix_match: prefix_match))
    end

    # Filter to only base rules (rules not inside any @media query).
    #
    # @return [StylesheetScope] New scope with base_only filter applied
    #
    # @example Get base rules only
    #   sheet.base_only.map(&:selector)
    #   sheet.base_only.with_property('color').to_a
    def base_only
      StylesheetScope.new(@stylesheet, @filters.merge(base_only: true))
    end

    # Filter by at-rule type.
    #
    # @param type [Symbol] At-rule type to match (:keyframes, :font_face, etc.)
    # @return [StylesheetScope] New scope with at-rule type filter applied
    #
    # @example Find all @keyframes
    #   sheet.with_at_rule_type(:keyframes)
    #
    # @example Find all @font-face
    #   sheet.with_at_rule_type(:font_face)
    def with_at_rule_type(type)
      StylesheetScope.new(@stylesheet, @filters.merge(at_rule_type: type))
    end

    # Filter to rules with !important declarations.
    #
    # @param property [String, nil] Optional property name to match
    # @return [StylesheetScope] New scope with important filter applied
    #
    # @example Find all rules with any !important
    #   sheet.with_important
    #
    # @example Find rules with color !important
    #   sheet.with_important('color')
    def with_important(property = nil)
      StylesheetScope.new(@stylesheet, @filters.merge(important: true, important_property: property))
    end

    # Iterate over filtered rules.
    #
    # @yield [rule] Each rule matching the filters
    # @yieldparam rule [Rule, AtRule] The rule object
    # @return [Enumerator] Enumerator if no block given
    def each
      return enum_for(:each) unless block_given?

      # Get base rules set
      rules = if @filters[:base_only]
                # Get rules not in any media query (media_query_id is nil)
                @stylesheet.rules.select { |r| r.is_a?(Rule) && r.media_query_id.nil? }
              elsif @filters[:media]
                media_array = Array(@filters[:media])

                # :all is a special case meaning "all rules"
                if media_array.include?(:all)
                  @stylesheet.rules
                else
                  # Use media_index for efficient lookup (it handles compound media queries)
                  matching_rule_ids = Set.new
                  media_array.each do |media_sym|
                    rule_ids = @stylesheet.media_index[media_sym]
                    matching_rule_ids.merge(rule_ids) if rule_ids
                  end
                  # Filter rules by ID
                  @stylesheet.rules.select { |r| matching_rule_ids.include?(r.id) }
                end
              else
                @stylesheet.rules
              end

      # Apply additional filters during iteration
      rules.each do |rule|
        # Specificity filter
        if @filters[:specificity]
          next if rule.specificity.nil? # AtRules have nil specificity
          next unless case @filters[:specificity]
                      when Range
                        @filters[:specificity].cover?(rule.specificity)
                      else
                        @filters[:specificity] == rule.specificity
                      end
        end

        # Selector filter (String or Regexp)
        if @filters[:selector] && !case @filters[:selector]
                                   when String
                                     rule.selector == @filters[:selector]
                                   when Regexp
                                     @filters[:selector] =~ rule.selector
                                   end
          next
        end

        # Property filter
        if @filters[:property]
          prefix_match = @filters.fetch(:property_prefix_match, false)
          unless rule.has_property?(@filters[:property], @filters[:property_value], prefix_match: prefix_match)
            next
          end
        end

        # At-rule type filter
        if @filters[:at_rule_type] && !rule.at_rule_type?(@filters[:at_rule_type])
          next
        end

        # Important filter
        if @filters[:important] && !rule.has_important?(@filters[:important_property])
          next
        end

        yield rule
      end
    end

    # Get the number of rules matching the filters.
    #
    # Forces evaluation of the scope.
    #
    # @return [Integer] Number of matching rules
    def size
      to_a.size
    end
    alias length size

    # Access a rule by index.
    #
    # Forces evaluation of the scope.
    #
    # @param index [Integer] Index of the rule to access
    # @return [Rule, AtRule, nil] Rule at the given index, or nil
    def [](index)
      to_a[index]
    end

    # Check if the scope has no matching rules.
    #
    # Forces evaluation of the scope.
    #
    # @return [Boolean] true if no rules match the filters
    def empty?
      to_a.empty?
    end

    # Compare the scope to another object.
    #
    # Forces evaluation of the scope and compares as an array.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if equal
    def ==(other)
      to_a == other
    end

    # Implicit conversion to Array for Ruby coercion.
    #
    # This allows StylesheetScope to be used transparently as an Array
    # in comparisons and other operations.
    #
    # @return [Array] Array of matching rules
    # @api private
    def to_ary
      to_a
    end

    # Human-readable representation showing filtered results.
    #
    # Forces evaluation of the scope and displays results.
    #
    # @return [String] Inspection string
    def inspect
      rules = to_a
      if rules.empty?
        '#<Cataract::StylesheetScope []>'
      else
        preview = rules.first(3).map(&:selector).join(', ')
        more = rules.length > 3 ? ', ...' : ''
        "#<Cataract::StylesheetScope [#{preview}#{more}] (#{rules.length} rules)>"
      end
    end
  end
end
