# frozen_string_literal: true

require_relative 'base'

module CSSAnalyzer
  module Analyzers
    # Analyzes color usage in CSS
    class Colors < Base
      # Color properties to search for
      COLOR_PROPERTIES = %w[
        color
        background-color
        border-color
        border-top-color
        border-right-color
        border-bottom-color
        border-left-color
        outline-color
        text-decoration-color
        column-rule-color
        fill
        stroke
      ].freeze

      def analyze
        color_counts = Hash.new(0)
        color_examples = Hash.new { |h, k| h[k] = [] }

        # Iterate through all rules
        stylesheet.rules.each do |rule|
          # Skip AtRules (like @keyframes) - they don't have declarations
          next unless rule.is_a?(Cataract::Rule)

          selector = rule.selector
          media_types = media_queries_for_rule(rule)

          # Check each declaration for color values
          rule.declarations.each do |decl|
            property = decl.property
            value = decl.value

            next unless COLOR_PROPERTIES.include?(property)

            # Extract color values from the declaration
            colors = extract_colors(value)

            colors.each do |color|
              normalized = normalize_color(color)
              color_counts[normalized] += 1

              # Store example (limit to 3 per color)
              next unless color_examples[normalized].length < 3

              color_examples[normalized] << {
                property: property,
                original_value: color,
                selector: selector,
                media: media_types
              }
            end
          end
        end

        # Sort by frequency
        sorted_colors = color_counts.sort_by { |_color, count| -count }

        {
          total_colors: color_counts.values.sum,
          unique_colors: color_counts.size,
          colors: sorted_colors.map do |color, count|
            {
              color: color,
              count: count,
              percentage: (count.to_f / color_counts.values.sum * 100).round(1),
              examples: color_examples[color],
              hex: color_to_hex(color)
            }
          end
        }
      end

      private

      # Extract color values from a CSS value string
      # Handles: hex, rgb(), rgba(), hsl(), hsla(), named colors
      def extract_colors(value)
        colors = []

        # Hex colors: #fff, #ffffff, #ffffffff
        colors += value.scan(/#[0-9a-fA-F]{3,8}\b/)

        # rgb/rgba: rgb(255, 255, 255), rgba(255, 255, 255, 0.5)
        colors += value.scan(/rgba?\([^)]+\)/)

        # hsl/hsla: hsl(120, 100%, 50%), hsla(120, 100%, 50%, 0.5)
        colors += value.scan(/hsla?\([^)]+\)/)

        # Named colors (basic set - extend as needed)
        named_colors = %w[
          transparent currentcolor inherit
          black white red green blue yellow orange purple pink
          gray grey silver maroon olive lime aqua teal navy fuchsia
        ]
        named_colors.each do |named|
          colors << named if value.downcase.include?(named)
        end

        colors.uniq
      end

      # Normalize color to lowercase for grouping
      def normalize_color(color)
        color.downcase.strip
      end

      # Convert color to hex for display (best effort)
      def color_to_hex(color)
        # If already hex, return as-is
        return color if color.start_with?('#')

        # For rgb/rgba, try to extract and convert
        if color.start_with?('rgb')
          # Simple extraction - just return the color for now
          # In future, could parse and convert to hex
          return color
        end

        # For named colors, return as-is (browser will handle)
        color
      end
    end
  end
end
