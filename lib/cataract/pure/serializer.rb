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
    result = +""

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_s_original(rules, media_index, result)
    end

    # Build parent-child relationships
    rule_children = {}
    rules.each do |rule|
      if rule.parent_rule_id
        parent_id = rule.parent_rule_id.is_a?(Integer) ? rule.parent_rule_id : rule.parent_rule_id.to_i
        rule_children[parent_id] ||= []
        rule_children[parent_id] << rule
      end
    end

    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Serialize top-level rules only (those without parent_rule_id)
    current_media = nil
    in_media_block = false

    rules.each do |rule|
      # Skip rules that have a parent (they'll be serialized as nested)
      next if rule.parent_rule_id

      rule_media = rule_to_media[rule.id]

      if rule_media.nil?
        # Close any open media block
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        # Serialize rule with nesting
        serialize_rule_with_nesting(result, rule, rule_children, rule_to_media)
      else
        # Media query
        if current_media.nil? || current_media != rule_media
          if in_media_block
            result << "}\n"
          end
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        serialize_rule_with_nesting(result, rule, rule_children, rule_to_media)
      end
    end

    if in_media_block
      result << "}\n"
    end

    result
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

  # Helper: serialize a rule with its nested children
  def self.serialize_rule_with_nesting(result, rule, rule_children, rule_to_media)
    # Start selector
    result << "#{rule.selector} { "

    # Serialize declarations
    has_declarations = !rule.declarations.empty?
    if has_declarations
      serialize_declarations(result, rule.declarations)
    end

    # Get nested children for this rule
    children = rule_children[rule.id] || []

    # Serialize nested children
    children.each_with_index do |child, index|
      # Add space before nested content
      # - Always add space if we had declarations
      # - Add space between nested rules (not before first if no declarations)
      if has_declarations || index > 0
        result << ' '
      end

      # Determine if we need to reconstruct the nested selector with &
      nested_selector = reconstruct_nested_selector(rule.selector, child.selector, child.nesting_style)

      # Check if this child has @media nesting (parent_rule_id present but nesting_style is nil)
      if child.nesting_style.nil? && rule_to_media[child.id]
        # This is a nested @media rule
        media_sym = rule_to_media[child.id]
        result << "@media #{media_sym} { "
        serialize_declarations(result, child.declarations)

        # Recursively serialize any children of this @media rule
        media_children = rule_children[child.id] || []
        media_children.each_with_index do |media_child, media_idx|
          result << ' ' if media_idx > 0 || !child.declarations.empty?
          nested_media_selector = reconstruct_nested_selector(child.selector, media_child.selector, media_child.nesting_style)
          result << "#{nested_media_selector} { "
          serialize_declarations(result, media_child.declarations)
          result << ' }'
        end

        result << ' }'
      else
        # Regular nested selector
        result << "#{nested_selector} { "
        serialize_declarations(result, child.declarations)

        # Recursively serialize any children of this nested rule
        grandchildren = rule_children[child.id] || []
        grandchildren.each_with_index do |grandchild, grandchild_idx|
          result << ' ' if grandchild_idx > 0 || !child.declarations.empty?
          nested_grandchild_selector = reconstruct_nested_selector(child.selector, grandchild.selector, grandchild.nesting_style)
          result << "#{nested_grandchild_selector} { "
          serialize_declarations(result, grandchild.declarations)
          result << ' }'
        end

        result << ' }'
      end
    end

    result << " }\n"
  end

  # Reconstruct nested selector representation
  # If nesting_style == 1 (explicit), try to use & notation
  # If nesting_style == 0 (implicit), use plain selector
  def self.reconstruct_nested_selector(parent_selector, child_selector, nesting_style)
    return child_selector if nesting_style.nil?

    if nesting_style == 1 # NESTING_STYLE_EXPLICIT
      # Try to reconstruct & notation
      # ".parent .child" with parent ".parent" => "& .child"
      # ".parent:hover" with parent ".parent" => "&:hover"
      if child_selector.start_with?(parent_selector)
        rest = child_selector[parent_selector.length..-1]
        return "&#{rest}"
      end
      # More complex cases like ".parent .foo .child"
      return child_selector.gsub(parent_selector, '&')
    else # NESTING_STYLE_IMPLICIT
      # Remove parent prefix for implicit nesting
      # ".parent .child" with parent ".parent" => ".child"
      if child_selector.start_with?(parent_selector)
        rest = child_selector[parent_selector.length..-1]
        return rest.lstrip
      end
      child_selector
    end
  end

  # Helper: serialize a single rule
  def self.serialize_rule(result, rule)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      serialize_at_rule(result, rule)
      return
    end

    # Regular Rule serialization
    result << "#{rule.selector} { "
    serialize_declarations(result, rule.declarations)
    result << " }\n"
  end

  # Helper: serialize declarations (compact, single line)
  def self.serialize_declarations(result, declarations)
    declarations.each_with_index do |decl, i|
      important_suffix = decl.important ? ' !important;' : ';'
      separator = i < declarations.length - 1 ? ' ' : ''
      result << "#{decl.property}: #{decl.value}#{important_suffix}#{separator}"
    end
  end

  # Helper: serialize declarations (formatted, one per line)
  def self.serialize_declarations_formatted(result, declarations, indent)
    declarations.each do |decl|
      result << indent
      result << decl.property
      result << ': '
      result << decl.value

      if decl.important
        result << ' !important'
      end

      result << ";\n"
    end
  end

  # Helper: serialize an at-rule (@keyframes, @font-face, etc)
  def self.serialize_at_rule(result, at_rule)
    result << "#{at_rule.selector} {\n"

    # Check if content is rules or declarations
    if at_rule.content.length > 0
      first = at_rule.content[0]

      if first.is_a?(Rule)
        # Serialize as nested rules (e.g., @keyframes)
        at_rule.content.each do |nested_rule|
          result << "  #{nested_rule.selector} { "
          serialize_declarations(result, nested_rule.declarations)
          result << " }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face)
        result << '  '
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

    # Build parent-child relationships
    rule_children = {}
    rules.each do |rule|
      if rule.parent_rule_id
        parent_id = rule.parent_rule_id.is_a?(Integer) ? rule.parent_rule_id : rule.parent_rule_id.to_i
        rule_children[parent_id] ||= []
        rule_children[parent_id] << rule
      end
    end

    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Serialize top-level rules only
    current_media = nil
    in_media_block = false

    rules.each do |rule|
      next if rule.parent_rule_id

      rule_media = rule_to_media[rule.id]

      if rule_media.nil?
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        serialize_rule_with_nesting_formatted(result, rule, rule_children, rule_to_media, '')
      else
        if current_media.nil? || current_media != rule_media
          if in_media_block
            result << "}\n"
          elsif result.length > 0
            result << "\n"
          end
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        serialize_rule_with_nesting_formatted(result, rule, rule_children, rule_to_media, '  ')
      end
    end

    if in_media_block
      result << "}\n"
    end

    result
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
        serialize_rule_formatted(result, rule, '')
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
        serialize_rule_formatted(result, rule, '  ')
      end
    end

    # Close final media block if still open
    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize a rule with nested children (formatted)
  def self.serialize_rule_with_nesting_formatted(result, rule, rule_children, rule_to_media, indent)
    # Selector line with opening brace
    result << indent
    result << rule.selector
    result << " {\n"

    # Serialize declarations (one per line)
    unless rule.declarations.empty?
      serialize_declarations_formatted(result, rule.declarations, "#{indent}  ")
    end

    # Get nested children
    children = rule_children[rule.id] || []

    # Serialize nested children
    children.each do |child|
      nested_selector = reconstruct_nested_selector(rule.selector, child.selector, child.nesting_style)

      if child.nesting_style.nil? && rule_to_media[child.id]
        # Nested @media
        media_sym = rule_to_media[child.id]
        result << indent
        result << "  @media #{media_sym} {\n"

        unless child.declarations.empty?
          serialize_declarations_formatted(result, child.declarations, "#{indent}    ")
        end

        # Recursively handle media children
        media_children = rule_children[child.id] || []
        media_children.each do |media_child|
          nested_media_selector = reconstruct_nested_selector(child.selector, media_child.selector, media_child.nesting_style)
          result << indent
          result << "    #{nested_media_selector} {\n"
          unless media_child.declarations.empty?
            serialize_declarations_formatted(result, media_child.declarations, "#{indent}      ")
          end
          result << indent
          result << "    }\n"
        end

        result << indent
        result << "  }\n"
      else
        # Regular nested selector
        result << indent
        result << "  #{nested_selector} {\n"

        unless child.declarations.empty?
          serialize_declarations_formatted(result, child.declarations, "#{indent}    ")
        end

        # Recursively handle grandchildren
        grandchildren = rule_children[child.id] || []
        grandchildren.each do |grandchild|
          nested_grandchild_selector = reconstruct_nested_selector(child.selector, grandchild.selector, grandchild.nesting_style)
          result << indent
          result << "    #{nested_grandchild_selector} {\n"
          unless grandchild.declarations.empty?
            serialize_declarations_formatted(result, grandchild.declarations, "#{indent}      ")
          end
          result << indent
          result << "    }\n"
        end

        result << indent
        result << "  }\n"
      end
    end

    # Closing brace
    result << indent
    result << "}\n"
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

    # Declarations (one per line)
    serialize_declarations_formatted(result, rule.declarations, "#{indent}  ")

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
          result << '  '
          result << nested_rule.selector
          result << " {\n"

          # Declarations (one per line, 4-space indent)
          serialize_declarations_formatted(result, nested_rule.declarations, "#{indent}    ")

          # Closing brace (2-space indent)
          result << indent
          result << "  }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face, one per line)
        serialize_declarations_formatted(result, at_rule.content, "#{indent}  ")
      end
    end

    result << indent
    result << "}\n"
  end
end
