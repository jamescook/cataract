# frozen_string_literal: true

module Cataract # rubocop:disable Style/Documentation
  # CssParser compatibility layer
  # Provides drop-in replacement for css_parser gem (used by premailer)
  module CssParserCompat
    @mimicked = false

    class << self
      attr_reader :mimicked
    end

    # Install CssParser compatibility shim
    # This allows Cataract to be used as a drop-in replacement for css_parser
    #
    # Strategy: Instead of replacing CssParser module entirely, we:
    # 1. Alias Parser/RuleSet classes to point to Cataract
    # 2. Add our merge method
    # 3. Add expand_shorthand! to RuleSet
    #
    # This way the original css_parser module stays intact and we can restore easily
    #
    # @example
    #   Cataract.mimic_CssParser!
    #   parser = CssParser::Parser.new  # Actually creates Cataract::Parser
    #
    def self.install!
      return if @mimicked

      unless defined?(::CssParser)
        # :nocov:
        raise LoadError, 'CssParser gem not loaded. Mimic requires css_parser to be loaded first.'
        # :nocov:
      end

      # Set marker constant
      ::CssParser.const_set(:CATARACT_SHIM, true) unless ::CssParser.const_defined?(:CATARACT_SHIM)

      # Save originals and replace with Cataract classes
      if defined?(::CssParser::Parser)
        ::CssParser.const_set(:OriginalParser, ::CssParser::Parser)
        ::CssParser.send(:remove_const, :Parser)
      end
      ::CssParser.const_set(:Parser, Cataract::Parser)

      if defined?(::CssParser::RuleSet) || defined?(::CssParser::OriginalRuleSet)
        original_ruleset = ::CssParser::RuleSet if defined?(::CssParser::RuleSet)
        ::CssParser.const_set(:OriginalRuleSet, original_ruleset) if original_ruleset

        # Make declarations public on old RuleSet so Premailer::CachedRuleSet can access it
        original_ruleset&.class_eval { public :declarations }

        ::CssParser.send(:remove_const, :RuleSet) if defined?(::CssParser::RuleSet)
      end
      ::CssParser.const_set(:RuleSet, Cataract::RuleSet)

      # Add module-level merge method
      css_parser_module = ::CssParser
      css_parser_module.define_singleton_method(:merge) do |*rule_sets|
        # Flatten in case called like CssParser.merge([rule1, rule2])
        rule_sets = rule_sets.flatten

        return rule_sets[0] if rule_sets.length == 1

        # Convert RuleSets to Rules for our merge function
        rules = rule_sets.map do |rule_set|
          # Extract declarations - handle both our RuleSet and old css_parser RuleSet
          decl_values = if rule_set.is_a?(Cataract::RuleSet)
                          # Our RuleSet - access @values directly
                          rule_set.declarations.instance_variable_get(:@values)
                        else
                          # Old css_parser RuleSet (Premailer::CachedRuleSet) - build array
                          vals = []
                          rule_set.each_declaration do |prop, val, imp|
                            vals << Cataract::Declarations::Value.new(prop, val, imp)
                          end
                          vals
                        end

          Cataract::Rule.new(
            rule_set.selectors.first,
            decl_values,
            rule_set.specificity
          )
        end

        # Use Cataract's C-based merge - returns array of Declarations::Value structs
        merged_declarations = Cataract.merge_rules(rules)

        # Wrap result in RuleSet for compatibility
        # Use first rule's selector and specificity
        Cataract::RuleSet.new(
          selector: rule_sets[0].selectors.first,
          declarations: merged_declarations,
          specificity: rule_sets[0].specificity
        )
      end

      # NOTE: RuleSet already accepts both 'selector' and 'selectors' parameters
      # Note: RuleSet already has expand_shorthand! method natively
      # Note: Premailer::CachedRuleSet is just a subclass of CssParser::RuleSet, so it inherits everything!
      # No patching needed!

      @mimicked = true
    end

    # Restore original CssParser classes
    # Use this in test teardown to restore the real css_parser gem
    #
    # @example
    #   def teardown
    #     Cataract.restore_CssParser!
    #   end
    #
    def self.restore!
      return unless @mimicked

      # Restore Parser
      if defined?(::CssParser::OriginalParser)
        ::CssParser.send(:remove_const, :Parser) if defined?(::CssParser::Parser)
        ::CssParser.const_set(:Parser, ::CssParser::OriginalParser)
        ::CssParser.send(:remove_const, :OriginalParser)
      end

      # Restore RuleSet
      if defined?(::CssParser::OriginalRuleSet)
        ::CssParser.send(:remove_const, :RuleSet) if defined?(::CssParser::RuleSet)
        ::CssParser.const_set(:RuleSet, ::CssParser::OriginalRuleSet)
        ::CssParser.send(:remove_const, :OriginalRuleSet)
      end

      # Remove marker
      ::CssParser.send(:remove_const, :CATARACT_SHIM) if defined?(::CssParser::CATARACT_SHIM)

      # Remove our merge method (can't easily remove singleton methods, but it won't hurt)

      @mimicked = false
    end
  end

  # Public API: Install CssParser compatibility shim
  def self.mimic_CssParser! # rubocop:disable Naming/MethodName
    CssParserCompat.install!
  end

  # Public API: Restore original CssParser (removes shim)
  def self.restore_CssParser! # rubocop:disable Naming/MethodName
    CssParserCompat.restore!
  end
end
