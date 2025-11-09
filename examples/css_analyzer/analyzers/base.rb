# frozen_string_literal: true

module CSSAnalyzer
  module Analyzers
    # Base class for all analyzers
    # Each analyzer should implement #analyze method that returns a hash of results
    class Base
      attr_reader :stylesheet, :options

      def initialize(stylesheet, options = {})
        @stylesheet = stylesheet
        @options = options
      end

      # Override in subclasses
      def analyze
        raise NotImplementedError, "#{self.class} must implement #analyze"
      end

      # Helper to get the tab name for this analyzer
      def tab_name
        self.class.name.split('::').last.downcase
      end

      # Helper to get media queries for a specific rule
      # @param rule [Cataract::Rule] The rule to check
      # @return [Array<Symbol>] Array of media query symbols this rule appears in
      def media_queries_for_rule(rule)
        stylesheet.media_index.select { |_media, ids| ids.include?(rule.id) }.keys
      end
    end
  end
end
