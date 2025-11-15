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
  # @param selector_lists [Hash] Selector list ID => array of rule IDs (for grouping)
  # @return [String] Compact CSS string
  def self._stylesheet_to_s(rules, media_index, charset, has_nesting, selector_lists = {})
    result = +''

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_s_original(rules, media_index, result, selector_lists)
    end

    # Build parent-child relationships
    rule_children = {}
    rules.each do |rule|
      next unless rule.parent_rule_id

      parent_id = rule.parent_rule_id.is_a?(Integer) ? rule.parent_rule_id : rule.parent_rule_id.to_i
      rule_children[parent_id] ||= []
      rule_children[parent_id] << rule
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
      end

      serialize_rule_with_nesting(result, rule, rule_children, rule_to_media)
    end

    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize rules without nesting support (compact format)
  def self.stylesheet_to_s_original(rules, media_index, result, selector_lists)
    _serialize_stylesheet_with_grouping(
      rules: rules,
      media_index: media_index,
      result: result,
      selector_lists: selector_lists,
      opening_brace: ' { ',
      closing_brace: " }\n",
      media_indent: '',
      decl_indent_base: nil,
      decl_indent_media: nil,
      add_blank_lines: false
    )
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

          nested_media_selector = reconstruct_nested_selector(
            child.selector, media_child.selector,
            media_child.nesting_style
          )

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

          nested_grandchild_selector = reconstruct_nested_selector(
            child.selector,
            grandchild.selector,
            grandchild.nesting_style
          )

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
      child_selector.sub(parent_selector, '&')
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

  # Helper: find all selectors from same list with matching declarations
  # Returns array of selectors that can be grouped, marks rules as processed
  def self.find_groupable_selectors(rule:, rules:, selector_lists:, processed_rule_ids:, rule_to_media:, current_media:)
    list_id = rule.selector_list_id
    rule_ids_in_list = selector_lists[list_id]

    # If no other rules in this list, return just this selector
    if rule_ids_in_list.nil? || rule_ids_in_list.size <= 1
      processed_rule_ids[rule.id] = true
      return [rule.selector]
    end

    # Find all rules in this list that have identical declarations AND same media context
    matching_selectors = []
    rule_ids_in_list.each do |rid|
      # Find the rule by ID
      other_rule = rules.find { |r| r.id == rid }
      next unless other_rule
      next if processed_rule_ids[rid]

      # Check same media context
      next if rule_to_media[rid] != current_media

      # Check declarations match (compare arrays directly for performance)
      if declarations_equal?(rule.declarations, other_rule.declarations)
        matching_selectors << other_rule.selector
        processed_rule_ids[rid] = true
      end
    end

    matching_selectors
  end

  # Private shared implementation for stylesheet serialization with optional selector list grouping
  # All formatting behavior controlled by kwargs to avoid mode flags and if/else branches
  def self._serialize_stylesheet_with_grouping(
    rules:,
    media_index:,
    result:,
    selector_lists:,
    opening_brace:,      # ' { ' (compact) vs " {\n" (formatted)
    closing_brace:,      # " }\n" (compact) vs "}\n" (formatted)
    media_indent:,       # '' (compact) vs '  ' (formatted)
    decl_indent_base:,   # nil (compact) vs '  ' (formatted base rules)
    decl_indent_media:,  # nil (compact) vs '    ' (formatted media rules)
    add_blank_lines:     # false (compact) vs true (formatted)
  )
    grouping_enabled = selector_lists && !selector_lists.empty?

    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Track processed rules to avoid duplicates when grouping
    processed_rule_ids = {}

    # Iterate through rules in insertion order, grouping consecutive media queries
    current_media = nil
    in_media_block = false
    rule_index = 0

    rules.each do |rule|
      # Skip if already processed (when grouped)
      next if processed_rule_ids[rule.id]

      rule_media = rule_to_media[rule.id]
      is_first_rule = (rule_index == 0)

      if rule_media.nil?
        # Not in any media query - close any open media block first
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        # Add blank line prefix for non-first rules (formatted only)
        result << "\n" if add_blank_lines && !is_first_rule

        # Try to group with other rules from same selector list
        if grouping_enabled && rule.is_a?(Rule) && rule.selector_list_id
          selectors = find_groupable_selectors(
            rule: rule,
            rules: rules,
            selector_lists: selector_lists,
            processed_rule_ids: processed_rule_ids,
            rule_to_media: rule_to_media,
            current_media: rule_media
          )

          # Serialize with grouped selectors
          result << selectors.join(', ') << opening_brace
          if decl_indent_base
            serialize_declarations_formatted(result, rule.declarations, decl_indent_base)
          else
            serialize_declarations(result, rule.declarations)
          end
          result << closing_brace
        else
          # Serialize individual rule
          if decl_indent_base
            serialize_rule_formatted(result, rule, '', true)
          else
            serialize_rule(result, rule)
          end
          processed_rule_ids[rule.id] = true
        end
      else
        # This rule is in a media query
        if current_media.nil? || current_media != rule_media
          # Close previous media block if open
          if in_media_block
            result << "}\n"
          end

          # Add blank line prefix for non-first rules (formatted only)
          result << "\n" if add_blank_lines && !is_first_rule

          # Open new media block
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        # Try to group with other rules from same selector list
        if grouping_enabled && rule.is_a?(Rule) && rule.selector_list_id
          selectors = find_groupable_selectors(
            rule: rule,
            rules: rules,
            selector_lists: selector_lists,
            processed_rule_ids: processed_rule_ids,
            rule_to_media: rule_to_media,
            current_media: rule_media
          )

          # Serialize with grouped selectors (with media indent)
          result << media_indent << selectors.join(', ') << opening_brace
          if decl_indent_media
            serialize_declarations_formatted(result, rule.declarations, decl_indent_media)
          else
            serialize_declarations(result, rule.declarations)
          end
          result << media_indent << closing_brace
        else
          # Serialize individual rule inside media block
          if decl_indent_media
            serialize_rule_formatted(result, rule, media_indent, true)
          else
            serialize_rule(result, rule)
          end
          processed_rule_ids[rule.id] = true
        end
      end

      rule_index += 1
    end

    # Close final media block if still open
    if in_media_block
      result << "}\n"
    end

    result
  end
  private_class_method :_serialize_stylesheet_with_grouping

  # Helper: check if two declaration arrays are equal
  def self.declarations_equal?(decls1, decls2)
    return false if decls1.size != decls2.size

    decls1.each_with_index do |d1, i|
      d2 = decls2[i]
      return false if d1.property != d2.property
      return false if d1.value != d2.value
      return false if d1.important != d2.important
    end

    true
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
  # @param selector_lists [Hash] Selector list ID => array of rule IDs (for grouping)
  # @return [String] Formatted CSS string
  def self._stylesheet_to_formatted_s(rules, media_index, charset, has_nesting, selector_lists = {})
    result = +''

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_formatted_s_original(rules, media_index, result, selector_lists)
    end

    # Build parent-child relationships
    rule_children = {}
    rules.each do |rule|
      next unless rule.parent_rule_id

      parent_id = rule.parent_rule_id.is_a?(Integer) ? rule.parent_rule_id : rule.parent_rule_id.to_i
      rule_children[parent_id] ||= []
      rule_children[parent_id] << rule
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

        # Add blank line before base rule if we just closed a media block (ends with "}\n")
        result << "\n" if result.length > 1 && result.getbyte(-1) == BYTE_NEWLINE && result.getbyte(-2) == BYTE_RBRACE

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
  def self.stylesheet_to_formatted_s_original(rules, media_index, result, selector_lists)
    _serialize_stylesheet_with_grouping(
      rules: rules,
      media_index: media_index,
      result: result,
      selector_lists: selector_lists,
      opening_brace: " {\n",
      closing_brace: "}\n",
      media_indent: '  ',
      decl_indent_base: '  ',
      decl_indent_media: '    ',
      add_blank_lines: true
    )
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
          nested_media_selector = reconstruct_nested_selector(
            child.selector,
            media_child.selector,
            media_child.nesting_style
          )

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
          nested_grandchild_selector = reconstruct_nested_selector(
            child.selector,
            grandchild.selector,
            grandchild.nesting_style
          )

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
  def self.serialize_rule_formatted(result, rule, indent, is_last_rule = false)
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

    # Closing brace - double newline for all except last rule
    result << indent
    result << (is_last_rule ? "}\n" : "}\n\n")
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
