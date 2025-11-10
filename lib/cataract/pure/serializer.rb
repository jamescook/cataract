# frozen_string_literal: true

# Pure Ruby CSS parser - Serialization methods
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  # Serialize stylesheet to compact CSS string
  #
  # @param rules [Array<Rule>] Array of rules
  # @param media_index [Hash] Media query symbol => array of rule IDs
  # @param charset [String, nil] @charset value
  # @param has_nesting [Boolean] Whether any nested rules exist
  # @return [String] Compact CSS string
  def self._stylesheet_to_s(rules, media_index, charset, has_nesting)
    result = String.new

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_s_original(rules, media_index, result)
    end

    # TODO: Implement nesting support
    # For now, just use the simple algorithm
    stylesheet_to_s_original(rules, media_index, result)
  end

  # Helper: serialize rules without nesting support
  def self.stylesheet_to_s_original(rules, media_index, result)
    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Iterate through rules in insertion order, grouping consecutive media queries
    current_media = nil
    in_media_block = false

    rules.each do |rule|
      rule_media = rule_to_media[rule.id]

      if rule_media.nil?
        # Not in any media query - close any open media block first
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        # Output rule directly
        serialize_rule(result, rule)
      else
        # This rule is in a media query
        # Check if media query changed from previous rule
        if current_media.nil? || current_media != rule_media
          # Close previous media block if open
          if in_media_block
            result << "}\n"
          end

          # Open new media block
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        # Serialize rule inside media block
        serialize_rule(result, rule)
      end
    end

    # Close final media block if still open
    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize a single rule
  def self.serialize_rule(result, rule)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      serialize_at_rule(result, rule)
      return
    end

    # Regular Rule serialization
    result << rule.selector
    result << " { "
    serialize_declarations(result, rule.declarations)
    result << " }\n"
  end

  # Helper: serialize declarations
  def self.serialize_declarations(result, declarations)
    declarations.each_with_index do |decl, i|
      result << decl.property
      result << ": "
      result << decl.value

      if decl.important
        result << " !important"
      end

      result << ";"

      # Add space after semicolon except for last declaration
      if i < declarations.length - 1
        result << " "
      end
    end
  end

  # Helper: serialize an at-rule (@keyframes, @font-face, etc)
  def self.serialize_at_rule(result, at_rule)
    result << at_rule.selector
    result << " {\n"

    # Check if content is rules or declarations
    if at_rule.content.length > 0
      first = at_rule.content[0]

      if first.is_a?(Rule)
        # Serialize as nested rules (e.g., @keyframes)
        at_rule.content.each do |nested_rule|
          result << "  "
          result << nested_rule.selector
          result << " { "
          serialize_declarations(result, nested_rule.declarations)
          result << " }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face)
        result << "  "
        serialize_declarations(result, at_rule.content)
        result << "\n"
      end
    end

    result << "}\n"
  end

  # Serialize stylesheet to formatted CSS string (with indentation)
  #
  # @param rules [Array<Rule>] Array of rules
  # @param media_index [Hash] Media query symbol => array of rule IDs
  # @param charset [String, nil] @charset value
  # @param has_nesting [Boolean] Whether any nested rules exist
  # @return [String] Formatted CSS string
  def self._stylesheet_to_formatted_s(rules, media_index, charset, has_nesting)
    result = String.new

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_formatted_s_original(rules, media_index, result)
    end

    # TODO: Implement nesting support
    # For now, just use the simple algorithm
    stylesheet_to_formatted_s_original(rules, media_index, result)
  end

  # Helper: formatted serialization without nesting support
  def self.stylesheet_to_formatted_s_original(rules, media_index, result)
    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Iterate through rules, grouping consecutive media queries
    current_media = nil
    in_media_block = false

    rules.each do |rule|
      rule_media = rule_to_media[rule.id]

      if rule_media.nil?
        # Not in any media query - close any open media block first
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        # Output rule with no indentation
        serialize_rule_formatted(result, rule, "")
      else
        # This rule is in a media query
        if current_media.nil? || current_media != rule_media
          # Close previous media block if open
          if in_media_block
            result << "}\n"
          else
            # Add blank line before @media if transitioning from non-media rules
            if result.length > 0
              result << "\n"
            end
          end

          # Open new media block
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        # Serialize rule inside media block with 2-space indentation
        serialize_rule_formatted(result, rule, "  ")
      end
    end

    # Close final media block if still open
    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize a single rule with formatting
  def self.serialize_rule_formatted(result, rule, indent)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      serialize_at_rule_formatted(result, rule, indent)
      return
    end

    # Regular Rule serialization with formatting
    # Selector line with opening brace
    result << indent
    result << rule.selector
    result << " {\n"

    # Declarations on their own line with extra indentation
    result << indent
    result << "  "
    serialize_declarations(result, rule.declarations)
    result << "\n"

    # Closing brace
    result << indent
    result << "}\n"
  end

  # Helper: serialize an at-rule with formatting
  def self.serialize_at_rule_formatted(result, at_rule, indent)
    result << indent
    result << at_rule.selector
    result << " {\n"

    # Check if content is rules or declarations
    if at_rule.content.length > 0
      first = at_rule.content[0]

      if first.is_a?(Rule)
        # Serialize as nested rules (e.g., @keyframes) with formatting
        at_rule.content.each do |nested_rule|
          # Nested selector with opening brace (2-space indent)
          result << indent
          result << "  "
          result << nested_rule.selector
          result << " {\n"

          # Declarations on their own line (4-space indent)
          result << indent
          result << "    "
          serialize_declarations(result, nested_rule.declarations)
          result << "\n"

          # Closing brace (2-space indent)
          result << indent
          result << "  }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face)
        result << indent
        result << "  "
        serialize_declarations(result, at_rule.content)
        result << "\n"
      end
    end

    result << indent
    result << "}\n"
  end
end
