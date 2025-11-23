# frozen_string_literal: true

# Pure Ruby CSS parser - Serialization methods
# NO REGEXP ALLOWED - char-by-char parsing only
#
# @api private
# This module contains internal serialization methods for converting parsed CSS
# back to strings. These methods are called by Stylesheet#to_s and should not be
# used directly. The public API is through the Stylesheet class.

module Cataract
  # @api private
  # Helper: Build media query string from MediaQuery object or list
  # @param media_query [MediaQuery] The MediaQuery object
  # @param media_query_list_id [Integer, nil] Optional list ID if this is part of a comma-separated list
  # @param media_query_lists [Hash] Hash mapping list_id => array of MediaQuery IDs
  # @param media_queries [Array] Array of all MediaQuery objects
  # @return [String] Serialized media query string (e.g., "screen", "screen, print", "screen and (min-width: 768px)")
  def self._build_media_query_string(media_query, media_query_list_id, media_query_lists, media_queries)
    if media_query_list_id
      # Comma-separated list
      mq_ids = media_query_lists[media_query_list_id]
      mq_ids.map do |mq_id|
        mq = media_queries[mq_id]
        if mq.conditions
          mq.type == :all ? mq.conditions : "#{mq.type} and #{mq.conditions}"
        else
          mq.type.to_s
        end
      end.join(', ')
    else
      # Single query
      if media_query.conditions
        media_query.type == :all ? media_query.conditions : "#{media_query.type} and #{media_query.conditions}"
      else
        media_query.type.to_s
      end
    end
  end

  # Serialize stylesheet to compact CSS string
  #
  # @param rules [Array<Rule>] Array of rules
  # @param media_index [Hash] Media query symbol => array of rule IDs
  # @param charset [String, nil] @charset value
  # @param has_nesting [Boolean] Whether any nested rules exist
  # @param selector_lists [Hash] Selector list ID => array of rule IDs (for grouping)
  # @param media_queries [Array<MediaQuery>] Array of MediaQuery objects (optional, for proper serialization)
  # @param media_query_lists [Hash] List ID => array of MediaQuery IDs (optional, for comma-separated queries)
  # @return [String] Compact CSS string
  def self.stylesheet_to_s(rules, media_index, charset, has_nesting, selector_lists = {}, media_queries = [], media_query_lists = {})
    result = +''

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return _stylesheet_to_s_original(rules, media_index, result, selector_lists, media_queries, media_query_lists)
    end

    # Build parent-child relationships
    rule_children = {}
    rules.each do |rule|
      next unless rule.parent_rule_id

      parent_id = rule.parent_rule_id.is_a?(Integer) ? rule.parent_rule_id : rule.parent_rule_id.to_i
      rule_children[parent_id] ||= []
      rule_children[parent_id] << rule
    end

    # Build reverse map: media_query_id => list_id
    mq_id_to_list_id = {}
    media_query_lists.each do |list_id, mq_ids|
      mq_ids.each { |mq_id| mq_id_to_list_id[mq_id] = list_id }
    end

    # Serialize top-level rules only (those without parent_rule_id)
    current_media_query_list_id = nil
    current_media_query = nil
    in_media_block = false

    rules.each do |rule|
      # Skip rules that have a parent (they'll be serialized as nested)
      next if rule.parent_rule_id

      rule_media_query_id = rule.is_a?(Rule) ? rule.media_query_id : nil
      rule_media_query = rule_media_query_id ? media_queries[rule_media_query_id] : nil
      rule_media_query_list_id = rule_media_query_id ? mq_id_to_list_id[rule_media_query_id] : nil

      if rule_media_query.nil?
        # Close any open media block
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media_query = nil
          current_media_query_list_id = nil
        end
      else
        # Check if we need to open a new media block
        # For lists: compare list_id
        # For single queries: compare by content (type + conditions)
        needs_new_block = if rule_media_query_list_id
                            current_media_query_list_id != rule_media_query_list_id
                          else
                            !current_media_query ||
                              current_media_query.type != rule_media_query.type ||
                              current_media_query.conditions != rule_media_query.conditions
                          end

        if needs_new_block
          if in_media_block
            result << "}\n"
          end
          current_media_query = rule_media_query
          current_media_query_list_id = rule_media_query_list_id

          # Serialize the media query (or list)
          media_query_string = _build_media_query_string(rule_media_query, rule_media_query_list_id, media_query_lists, media_queries)
          result << "@media #{media_query_string} {\n"
          in_media_block = true
        end
      end

      _serialize_rule_with_nesting(result, rule, rule_children, media_queries)
    end

    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize rules without nesting support (compact format)
  def self._stylesheet_to_s_original(rules, media_index, result, selector_lists, media_queries = [], media_query_lists = {})
    _serialize_stylesheet_with_grouping(
      rules: rules,
      media_index: media_index,
      result: result,
      selector_lists: selector_lists,
      media_queries: media_queries,
      media_query_lists: media_query_lists,
      opening_brace: ' { ',
      closing_brace: " }\n",
      media_indent: '',
      decl_indent_base: nil,
      decl_indent_media: nil,
      add_blank_lines: false
    )
  end

  # Helper: serialize a rule with its nested children
  def self._serialize_rule_with_nesting(result, rule, rule_children, media_queries)
    # Start selector
    result << "#{rule.selector} { "

    # Serialize declarations
    has_declarations = !rule.declarations.empty?
    if has_declarations
      _serialize_declarations(result, rule.declarations)
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
      nested_selector = _reconstruct_nested_selector(rule.selector, child.selector, child.nesting_style)

      # Check if this child has @media nesting (parent_rule_id present but nesting_style is nil)
      if child.nesting_style.nil? && child.media_query_id && media_queries[child.media_query_id]
        # This is a nested @media rule
        mq = media_queries[child.media_query_id]
        media_query_string = if mq.conditions
                               mq.type == :all ? mq.conditions : "#{mq.type} and #{mq.conditions}"
                             else
                               mq.type.to_s
                             end
        result << "@media #{media_query_string} { "
        _serialize_declarations(result, child.declarations)

        # Recursively serialize any children of this @media rule
        media_children = rule_children[child.id] || []
        media_children.each_with_index do |media_child, media_idx|
          result << ' ' if media_idx > 0 || !child.declarations.empty?

          nested_media_selector = _reconstruct_nested_selector(
            child.selector, media_child.selector,
            media_child.nesting_style
          )

          result << "#{nested_media_selector} { "
          _serialize_declarations(result, media_child.declarations)
          result << ' }'
        end

        result << ' }'
      else
        # Regular nested selector
        result << "#{nested_selector} { "
        _serialize_declarations(result, child.declarations)

        # Recursively serialize any children of this nested rule
        grandchildren = rule_children[child.id] || []
        grandchildren.each_with_index do |grandchild, grandchild_idx|
          result << ' ' if grandchild_idx > 0 || !child.declarations.empty?

          nested_grandchild_selector = _reconstruct_nested_selector(
            child.selector,
            grandchild.selector,
            grandchild.nesting_style
          )

          result << "#{nested_grandchild_selector} { "
          _serialize_declarations(result, grandchild.declarations)
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
  def self._reconstruct_nested_selector(parent_selector, child_selector, nesting_style)
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
  def self._find_groupable_selectors(rule:, rules:, selector_lists:, processed_rule_ids:, current_media_query_id:)
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
      # Direct array access (O(1)) - rules[i].id == i invariant is guaranteed by parser
      other_rule = rules[rid]
      next unless other_rule
      next if processed_rule_ids[rid]

      # Check same media context (compare media_query_id directly)
      next if other_rule.media_query_id != current_media_query_id

      # Check declarations match (compare arrays directly for performance)
      if _declarations_equal?(rule.declarations, other_rule.declarations)
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
    add_blank_lines:,    # false (compact) vs true (formatted)
    media_queries: [],   # Array of MediaQuery objects
    media_query_lists: {} # Hash: list_id => array of MediaQuery IDs
  )
    grouping_enabled = selector_lists && !selector_lists.empty?

    # Build reverse map: media_query_id => list_id
    mq_id_to_list_id = {}
    media_query_lists.each do |list_id, mq_ids|
      mq_ids.each { |mq_id| mq_id_to_list_id[mq_id] = list_id }
    end

    # Track processed rules to avoid duplicates when grouping
    processed_rule_ids = {}

    # Iterate through rules in insertion order, grouping consecutive media queries
    current_media_query_list_id = nil
    current_media_query = nil
    in_media_block = false
    rule_index = 0

    rules.each do |rule|
      # Skip if already processed (when grouped)
      next if processed_rule_ids[rule.id]

      rule_media_query_id = rule.is_a?(Rule) ? rule.media_query_id : nil
      rule_media_query = rule_media_query_id ? media_queries[rule_media_query_id] : nil
      rule_media_query_list_id = rule_media_query_id ? mq_id_to_list_id[rule_media_query_id] : nil
      is_first_rule = (rule_index == 0)

      if rule_media_query.nil?
        # Not in any media query - close any open media block first
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media_query = nil
          current_media_query_list_id = nil
        end

        # Add blank line prefix for non-first rules (formatted only)
        result << "\n" if add_blank_lines && !is_first_rule

        # Try to group with other rules from same selector list
        if grouping_enabled && rule.is_a?(Rule) && rule.selector_list_id
          selectors = _find_groupable_selectors(
            rule: rule,
            rules: rules,
            selector_lists: selector_lists,
            processed_rule_ids: processed_rule_ids,
            current_media_query_id: rule_media_query_id
          )

          # Serialize with grouped selectors
          result << selectors.join(', ') << opening_brace
          if decl_indent_base
            _serialize_declarations_formatted(result, rule.declarations, decl_indent_base)
          else
            _serialize_declarations(result, rule.declarations)
          end
          result << closing_brace
        else
          # Serialize individual rule
          if decl_indent_base
            _serialize_rule_formatted(result, rule, '', true)
          else
            _serialize_rule(result, rule)
          end
          processed_rule_ids[rule.id] = true
        end
      else
        # This rule is in a media query
        # For lists: compare list_id
        # For single queries: compare by content (type + conditions)
        needs_new_block = if rule_media_query_list_id
                            current_media_query_list_id != rule_media_query_list_id
                          else
                            !current_media_query ||
                              current_media_query.type != rule_media_query.type ||
                              current_media_query.conditions != rule_media_query.conditions
                          end

        if needs_new_block
          # Close previous media block if open
          if in_media_block
            result << "}\n"
          end

          # Add blank line prefix for non-first rules (formatted only)
          result << "\n" if add_blank_lines && !is_first_rule

          # Open new media block
          current_media_query = rule_media_query
          current_media_query_list_id = rule_media_query_list_id

          # Serialize the media query (or list)
          media_query_string = _build_media_query_string(rule_media_query, rule_media_query_list_id, media_query_lists, media_queries)
          result << "@media #{media_query_string} {\n"
          in_media_block = true
        end

        # Try to group with other rules from same selector list
        if grouping_enabled && rule.is_a?(Rule) && rule.selector_list_id
          selectors = _find_groupable_selectors(
            rule: rule,
            rules: rules,
            selector_lists: selector_lists,
            processed_rule_ids: processed_rule_ids,
            current_media_query_id: rule_media_query_id
          )

          # Serialize with grouped selectors (with media indent)
          result << media_indent << selectors.join(', ') << opening_brace
          if decl_indent_media
            _serialize_declarations_formatted(result, rule.declarations, decl_indent_media)
          else
            _serialize_declarations(result, rule.declarations)
          end
          result << media_indent << closing_brace
        else
          # Serialize individual rule inside media block
          if decl_indent_media
            _serialize_rule_formatted(result, rule, media_indent, true)
          else
            _serialize_rule(result, rule)
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
  def self._declarations_equal?(decls1, decls2)
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
  def self._serialize_rule(result, rule)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      _serialize_at_rule(result, rule)
      return
    end

    # Regular Rule serialization
    result << "#{rule.selector} { "
    _serialize_declarations(result, rule.declarations)
    result << " }\n"
  end

  # Helper: serialize declarations (compact, single line)
  def self._serialize_declarations(result, declarations)
    declarations.each_with_index do |decl, i|
      important_suffix = decl.important ? ' !important;' : ';'
      separator = i < declarations.length - 1 ? ' ' : ''
      result << "#{decl.property}: #{decl.value}#{important_suffix}#{separator}"
    end
  end

  # Helper: serialize declarations (formatted, one per line)
  def self._serialize_declarations_formatted(result, declarations, indent)
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
  def self._serialize_at_rule(result, at_rule)
    result << "#{at_rule.selector} {\n"

    # Check if content is rules or declarations
    if at_rule.content.length > 0
      first = at_rule.content[0]

      if first.is_a?(Rule)
        # Serialize as nested rules (e.g., @keyframes)
        at_rule.content.each do |nested_rule|
          result << "  #{nested_rule.selector} { "
          _serialize_declarations(result, nested_rule.declarations)
          result << " }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face)
        result << '  '
        _serialize_declarations(result, at_rule.content)
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
  # @param media_queries [Array<MediaQuery>] Array of MediaQuery objects (optional, for proper serialization)
  # @param media_query_lists [Hash] List ID => array of MediaQuery IDs (optional, for comma-separated queries)
  # @return [String] Formatted CSS string
  def self.stylesheet_to_formatted_s(rules, media_index, charset, has_nesting, selector_lists = {}, media_queries = [], media_query_lists = {})
    result = +''

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return _stylesheet_to_formatted_s_original(rules, media_index, result, selector_lists, media_queries, media_query_lists)
    end

    # Build parent-child relationships
    rule_children = {}
    rules.each do |rule|
      next unless rule.parent_rule_id

      parent_id = rule.parent_rule_id.is_a?(Integer) ? rule.parent_rule_id : rule.parent_rule_id.to_i
      rule_children[parent_id] ||= []
      rule_children[parent_id] << rule
    end

    # Build reverse map: media_query_id => list_id
    mq_id_to_list_id = {}
    media_query_lists.each do |list_id, mq_ids|
      mq_ids.each { |mq_id| mq_id_to_list_id[mq_id] = list_id }
    end

    # Serialize top-level rules only
    current_media_query_list_id = nil
    current_media_query = nil
    in_media_block = false

    rules.each do |rule|
      next if rule.parent_rule_id

      rule_media_query_id = rule.is_a?(Rule) ? rule.media_query_id : nil
      rule_media_query = rule_media_query_id ? media_queries[rule_media_query_id] : nil
      rule_media_query_list_id = rule_media_query_id ? mq_id_to_list_id[rule_media_query_id] : nil

      if rule_media_query.nil?
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media_query = nil
          current_media_query_list_id = nil
        end

        # Add blank line before base rule if we just closed a media block (ends with "}\n")
        result << "\n" if result.length > 1 && result.getbyte(-1) == BYTE_NEWLINE && result.getbyte(-2) == BYTE_RBRACE

        _serialize_rule_with_nesting_formatted(result, rule, rule_children, '', media_queries)
      else
        # For lists: compare list_id
        # For single queries: compare by content (type + conditions)
        needs_new_block = if rule_media_query_list_id
                            current_media_query_list_id != rule_media_query_list_id
                          else
                            !current_media_query ||
                              current_media_query.type != rule_media_query.type ||
                              current_media_query.conditions != rule_media_query.conditions
                          end

        if needs_new_block
          if in_media_block
            result << "}\n"
          elsif result.length > 0
            result << "\n"
          end
          current_media_query = rule_media_query
          current_media_query_list_id = rule_media_query_list_id
          # Serialize the media query (or list)
          media_query_string = _build_media_query_string(rule_media_query, rule_media_query_list_id, media_query_lists, media_queries)
          result << "@media #{media_query_string} {\n"
          in_media_block = true
        end

        _serialize_rule_with_nesting_formatted(result, rule, rule_children, '  ', media_queries)
      end
    end

    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: formatted serialization without nesting support
  def self._stylesheet_to_formatted_s_original(rules, media_index, result, selector_lists, media_queries = [], media_query_lists = {})
    _serialize_stylesheet_with_grouping(
      rules: rules,
      media_index: media_index,
      result: result,
      selector_lists: selector_lists,
      media_queries: media_queries,
      media_query_lists: media_query_lists,
      opening_brace: " {\n",
      closing_brace: "}\n",
      media_indent: '  ',
      decl_indent_base: '  ',
      decl_indent_media: '    ',
      add_blank_lines: true
    )
  end

  # Helper: serialize a rule with nested children (formatted)
  def self._serialize_rule_with_nesting_formatted(result, rule, rule_children, indent, media_queries)
    # Selector line with opening brace
    result << indent
    result << rule.selector
    result << " {\n"

    # Serialize declarations (one per line)
    unless rule.declarations.empty?
      _serialize_declarations_formatted(result, rule.declarations, "#{indent}  ")
    end

    # Get nested children
    children = rule_children[rule.id] || []

    # Serialize nested children
    children.each do |child|
      nested_selector = _reconstruct_nested_selector(rule.selector, child.selector, child.nesting_style)

      if child.nesting_style.nil? && child.media_query_id && media_queries[child.media_query_id]
        # Nested @media
        mq = media_queries[child.media_query_id]
        media_query_string = if mq.conditions
                               mq.type == :all ? mq.conditions : "#{mq.type} and #{mq.conditions}"
                             else
                               mq.type.to_s
                             end
        result << indent
        result << "  @media #{media_query_string} {\n"

        unless child.declarations.empty?
          _serialize_declarations_formatted(result, child.declarations, "#{indent}    ")
        end

        # Recursively handle media children
        media_children = rule_children[child.id] || []
        media_children.each do |media_child|
          nested_media_selector = _reconstruct_nested_selector(
            child.selector,
            media_child.selector,
            media_child.nesting_style
          )

          result << indent
          result << "    #{nested_media_selector} {\n"
          unless media_child.declarations.empty?
            _serialize_declarations_formatted(result, media_child.declarations, "#{indent}      ")
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
          _serialize_declarations_formatted(result, child.declarations, "#{indent}    ")
        end

        # Recursively handle grandchildren
        grandchildren = rule_children[child.id] || []
        grandchildren.each do |grandchild|
          nested_grandchild_selector = _reconstruct_nested_selector(
            child.selector,
            grandchild.selector,
            grandchild.nesting_style
          )

          result << indent
          result << "    #{nested_grandchild_selector} {\n"
          unless grandchild.declarations.empty?
            _serialize_declarations_formatted(result, grandchild.declarations, "#{indent}      ")
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
  def self._serialize_rule_formatted(result, rule, indent, is_last_rule = false)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      _serialize_at_rule_formatted(result, rule, indent)
      return
    end

    # Regular Rule serialization with formatting
    # Selector line with opening brace
    result << indent
    result << rule.selector
    result << " {\n"

    # Declarations (one per line)
    _serialize_declarations_formatted(result, rule.declarations, "#{indent}  ")

    # Closing brace - double newline for all except last rule
    result << indent
    result << (is_last_rule ? "}\n" : "}\n\n")
  end

  # Helper: serialize an at-rule with formatting
  def self._serialize_at_rule_formatted(result, at_rule, indent)
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
          _serialize_declarations_formatted(result, nested_rule.declarations, "#{indent}    ")

          # Closing brace (2-space indent)
          result << indent
          result << "  }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face, one per line)
        _serialize_declarations_formatted(result, at_rule.content, "#{indent}  ")
      end
    end

    result << indent
    result << "}\n"
  end

  # Mark helper methods as private (public APIs: stylesheet_to_s, stylesheet_to_formatted_s)
  private_class_method :_build_media_query_string, :_stylesheet_to_s_original, :_serialize_rule_with_nesting,
                       :_reconstruct_nested_selector, :_find_groupable_selectors, :_declarations_equal?,
                       :_serialize_rule, :_serialize_declarations, :_serialize_declarations_formatted,
                       :_serialize_at_rule, :_stylesheet_to_formatted_s_original, :_serialize_rule_with_nesting_formatted,
                       :_serialize_rule_formatted, :_serialize_at_rule_formatted
end
