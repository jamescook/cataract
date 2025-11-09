# frozen_string_literal: true

require_relative 'base'

module CSSAnalyzer
  module Analyzers
    # Analyzes CSS property usage frequency
    class Properties < Base
      def analyze
        property_counts = Hash.new(0)
        property_examples = Hash.new { |h, k| h[k] = [] }

        # Iterate through all rules
        stylesheet.rules.each do |rule|
          # Skip AtRules (like @keyframes) - they don't have declarations
          next unless rule.is_a?(Cataract::Rule)

          selector = rule.selector
          media_types = media_queries_for_rule(rule)

          # Iterate through declarations
          # Each declaration is a struct with property, value, important
          rule.declarations.each do |decl|
            property = decl.property
            value = decl.value
            important = decl.important

            property_counts[property] += 1

            # Store example (limit to 3 examples per property)
            next unless property_examples[property].length < 3

            property_examples[property] << {
              value: value,
              important: important,
              selector: selector,
              media: media_types
            }
          end
        end

        # Sort by frequency and take top N
        top_n = options[:top] || 20
        top_properties = property_counts.sort_by { |_prop, count| -count }.first(top_n)

        {
          total_properties: property_counts.values.sum,
          unique_properties: property_counts.size,
          top_properties: top_properties.map do |property, count|
            {
              name: property,
              count: count,
              percentage: (count.to_f / property_counts.values.sum * 100).round(1),
              examples: property_examples[property]
            }
          end
        }
      end
    end
  end
end
