# frozen_string_literal: true

require_relative 'base'

module CSSAnalyzer
  module Analyzers
    # Analyzes !important usage in CSS
    class Important < Base
      def analyze
        total_declarations = 0
        important_count = 0
        important_by_property = Hash.new(0)
        important_by_selector = Hash.new(0)
        important_examples = []

        # Iterate through all rule sets
        stylesheet.each_rule_set do |rule_set, media_types|
          selector = rule_set.selector
          selector_important_count = 0

          rule_set.declarations.each do |property, value, important|
            total_declarations += 1

            next unless important

            important_count += 1
            important_by_property[property] += 1
            selector_important_count += 1

            important_examples << {
              selector: selector,
              property: property,
              value: value,
              media: media_types
            }
          end

          if selector_important_count.positive?
            important_by_selector[selector] = selector_important_count
          end
        end

        # Sort properties by !important usage
        top_properties = important_by_property.sort_by { |_prop, count| -count }.first(20)

        # Sort selectors by !important count
        top_selectors = important_by_selector.sort_by { |_sel, count| -count }.first(20)

        # Calculate percentage
        important_percentage = if total_declarations.positive?
                                 (important_count.to_f / total_declarations * 100).round(1)
                               else
                                 0.0
                               end

        {
          total_declarations: total_declarations,
          important_count: important_count,
          important_percentage: important_percentage,
          properties_using_important: important_by_property.size,
          selectors_using_important: important_by_selector.size,
          top_properties: top_properties.map do |prop, count|
            {
              property: prop,
              count: count,
              percentage: (count.to_f / important_count * 100).round(1)
            }
          end,
          top_selectors: top_selectors.map do |selector, count|
            {
              selector: selector,
              count: count
            }
          end,
          all_important: important_examples
        }
      end
    end
  end
end
