# frozen_string_literal: true

require_relative 'base'

module CSSAnalyzer
  module Analyzers
    # Analyzes CSS selector specificity
    class Specificity < Base
      def analyze
        specificity_data = []
        specificity_histogram = Hash.new(0)

        # Iterate through all rule sets
        stylesheet.each_rule_set do |rule_set, media_types|
          spec = rule_set.specificity
          specificity_histogram[spec] += 1

          specificity_data << {
            selector: rule_set.selector,
            specificity: spec,
            media: media_types,
            declaration_count: rule_set.declarations.to_a.length
          }
        end

        # Sort by specificity (highest first)
        sorted_by_spec = specificity_data.sort_by { |r| -r[:specificity] }

        # Calculate statistics
        specificities = specificity_data.map { |r| r[:specificity] }
        avg_specificity = specificities.sum.to_f / specificities.length
        max_specificity = specificities.max
        min_specificity = specificities.min

        # Categorize selectors by specificity ranges
        # Specificity guide:
        #   0-10: Element selectors (div, p, etc)
        #   11-100: Class selectors (.class)
        #   101-1000: ID selectors (#id)
        #   1000+: Inline styles or many IDs
        categories = {
          low: specificity_data.count { |r| r[:specificity] <= 10 },
          medium: specificity_data.count { |r| r[:specificity] > 10 && r[:specificity] <= 100 },
          high: specificity_data.count { |r| r[:specificity] > 100 && r[:specificity] <= 1000 },
          very_high: specificity_data.count { |r| r[:specificity] > 1000 }
        }

        # Find problematic selectors (high specificity)
        high_specificity = sorted_by_spec.select { |r| r[:specificity] > 100 }

        {
          total_selectors: specificity_data.length,
          average_specificity: avg_specificity.round(1),
          max_specificity: max_specificity,
          min_specificity: min_specificity,
          categories: categories,
          top_20_highest: sorted_by_spec.first(20),
          high_specificity_count: high_specificity.length,
          histogram: specificity_histogram.sort_by { |spec, _count| -spec }.first(20)
        }
      end
    end
  end
end
