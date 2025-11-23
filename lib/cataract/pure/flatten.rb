# frozen_string_literal: true

# Pure Ruby CSS flatten implementation
# NO REGEXP ALLOWED - use string manipulation only

module Cataract
  module Flatten
    # Property name constants (US-ASCII for merge output)
    PROP_MARGIN = 'margin'.encode(Encoding::US_ASCII).freeze
    PROP_MARGIN_TOP = 'margin-top'.encode(Encoding::US_ASCII).freeze
    PROP_MARGIN_RIGHT = 'margin-right'.encode(Encoding::US_ASCII).freeze
    PROP_MARGIN_BOTTOM = 'margin-bottom'.encode(Encoding::US_ASCII).freeze
    PROP_MARGIN_LEFT = 'margin-left'.encode(Encoding::US_ASCII).freeze

    PROP_PADDING = 'padding'.encode(Encoding::US_ASCII).freeze
    PROP_PADDING_TOP = 'padding-top'.encode(Encoding::US_ASCII).freeze
    PROP_PADDING_RIGHT = 'padding-right'.encode(Encoding::US_ASCII).freeze
    PROP_PADDING_BOTTOM = 'padding-bottom'.encode(Encoding::US_ASCII).freeze
    PROP_PADDING_LEFT = 'padding-left'.encode(Encoding::US_ASCII).freeze

    PROP_BORDER = 'border'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_WIDTH = 'border-width'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_STYLE = 'border-style'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_COLOR = 'border-color'.encode(Encoding::US_ASCII).freeze

    PROP_BORDER_TOP = 'border-top'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_RIGHT = 'border-right'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_BOTTOM = 'border-bottom'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_LEFT = 'border-left'.encode(Encoding::US_ASCII).freeze

    PROP_BORDER_TOP_WIDTH = 'border-top-width'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_RIGHT_WIDTH = 'border-right-width'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_BOTTOM_WIDTH = 'border-bottom-width'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_LEFT_WIDTH = 'border-left-width'.encode(Encoding::US_ASCII).freeze

    PROP_BORDER_TOP_STYLE = 'border-top-style'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_RIGHT_STYLE = 'border-right-style'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_BOTTOM_STYLE = 'border-bottom-style'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_LEFT_STYLE = 'border-left-style'.encode(Encoding::US_ASCII).freeze

    PROP_BORDER_TOP_COLOR = 'border-top-color'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_RIGHT_COLOR = 'border-right-color'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_BOTTOM_COLOR = 'border-bottom-color'.encode(Encoding::US_ASCII).freeze
    PROP_BORDER_LEFT_COLOR = 'border-left-color'.encode(Encoding::US_ASCII).freeze

    PROP_FONT = 'font'.encode(Encoding::US_ASCII).freeze
    PROP_FONT_STYLE = 'font-style'.encode(Encoding::US_ASCII).freeze
    PROP_FONT_VARIANT = 'font-variant'.encode(Encoding::US_ASCII).freeze
    PROP_FONT_WEIGHT = 'font-weight'.encode(Encoding::US_ASCII).freeze
    PROP_FONT_SIZE = 'font-size'.encode(Encoding::US_ASCII).freeze
    PROP_LINE_HEIGHT = 'line-height'.encode(Encoding::US_ASCII).freeze
    PROP_FONT_FAMILY = 'font-family'.encode(Encoding::US_ASCII).freeze

    PROP_BACKGROUND = 'background'.encode(Encoding::US_ASCII).freeze
    PROP_BACKGROUND_COLOR = 'background-color'.encode(Encoding::US_ASCII).freeze
    PROP_BACKGROUND_IMAGE = 'background-image'.encode(Encoding::US_ASCII).freeze
    PROP_BACKGROUND_REPEAT = 'background-repeat'.encode(Encoding::US_ASCII).freeze
    PROP_BACKGROUND_ATTACHMENT = 'background-attachment'.encode(Encoding::US_ASCII).freeze
    PROP_BACKGROUND_POSITION = 'background-position'.encode(Encoding::US_ASCII).freeze

    PROP_LIST_STYLE = 'list-style'.encode(Encoding::US_ASCII).freeze
    PROP_LIST_STYLE_TYPE = 'list-style-type'.encode(Encoding::US_ASCII).freeze
    PROP_LIST_STYLE_POSITION = 'list-style-position'.encode(Encoding::US_ASCII).freeze
    PROP_LIST_STYLE_IMAGE = 'list-style-image'.encode(Encoding::US_ASCII).freeze

    # Shorthand property families
    MARGIN_SIDES = [PROP_MARGIN_TOP, PROP_MARGIN_RIGHT, PROP_MARGIN_BOTTOM, PROP_MARGIN_LEFT].freeze
    PADDING_SIDES = [PROP_PADDING_TOP, PROP_PADDING_RIGHT, PROP_PADDING_BOTTOM, PROP_PADDING_LEFT].freeze

    BORDER_WIDTHS = [
      PROP_BORDER_TOP_WIDTH,
      PROP_BORDER_RIGHT_WIDTH,
      PROP_BORDER_BOTTOM_WIDTH,
      PROP_BORDER_LEFT_WIDTH
    ].freeze

    BORDER_STYLES = [
      PROP_BORDER_TOP_STYLE,
      PROP_BORDER_RIGHT_STYLE,
      PROP_BORDER_BOTTOM_STYLE,
      PROP_BORDER_LEFT_STYLE
    ].freeze

    BORDER_COLORS = [
      PROP_BORDER_TOP_COLOR,
      PROP_BORDER_RIGHT_COLOR,
      PROP_BORDER_BOTTOM_COLOR,
      PROP_BORDER_LEFT_COLOR
    ].freeze

    # Side name constants (for string operations, not CSS properties)
    SIDE_TOP = 'top'
    SIDE_RIGHT = 'right'
    SIDE_BOTTOM = 'bottom'
    SIDE_LEFT = 'left'
    BORDER_SIDES = [SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM, SIDE_LEFT].freeze

    FONT_PROPERTIES = [
      PROP_FONT_STYLE,
      PROP_FONT_VARIANT,
      PROP_FONT_WEIGHT,
      PROP_FONT_SIZE,
      PROP_LINE_HEIGHT,
      PROP_FONT_FAMILY
    ].freeze

    BACKGROUND_PROPERTIES = [
      PROP_BACKGROUND_COLOR,
      PROP_BACKGROUND_IMAGE,
      PROP_BACKGROUND_REPEAT,
      PROP_BACKGROUND_POSITION,
      PROP_BACKGROUND_ATTACHMENT
    ].freeze

    LIST_STYLE_PROPERTIES = [PROP_LIST_STYLE_TYPE, PROP_LIST_STYLE_POSITION, PROP_LIST_STYLE_IMAGE].freeze
    BORDER_ALL = (BORDER_WIDTHS + BORDER_STYLES + BORDER_COLORS).freeze

    # Shorthand property lookup (Hash is faster than Array#include? or Set)
    # Used for fast-path check to avoid calling expand_shorthand for non-shorthands
    SHORTHAND_PROPERTIES = {
      'margin' => true,
      'padding' => true,
      'border' => true,
      'border-top' => true,
      'border-right' => true,
      'border-bottom' => true,
      'border-left' => true,
      'border-width' => true,
      'border-style' => true,
      'border-color' => true,
      'font' => true,
      'background' => true,
      'list-style' => true
    }.freeze

    # List style keywords
    LIST_STYLE_POSITION_KEYWORDS = %w[inside outside].freeze

    # Border property keywords
    BORDER_WIDTH_KEYWORDS = %w[thin medium thick].freeze
    BORDER_STYLE_KEYWORDS = %w[none hidden dotted dashed solid double groove ridge inset outset].freeze

    # Font property keywords
    FONT_SIZE_KEYWORDS = %w[xx-small x-small small medium large x-large xx-large smaller larger].freeze
    FONT_STYLE_KEYWORDS = %w[normal italic oblique].freeze
    FONT_VARIANT_KEYWORDS = %w[normal small-caps].freeze
    FONT_WEIGHT_KEYWORDS = %w[normal bold bolder lighter 100 200 300 400 500 600 700 800 900].freeze

    # Background property keywords
    BACKGROUND_REPEAT_KEYWORDS = %w[repeat repeat-x repeat-y no-repeat space round].freeze
    BACKGROUND_ATTACHMENT_KEYWORDS = %w[scroll fixed local].freeze
    BACKGROUND_POSITION_KEYWORDS = %w[left right center top bottom].freeze

    # Merge stylesheet according to CSS cascade rules
    #
    # @param stylesheet [Stylesheet] Stylesheet to merge
    # @param mutate [Boolean] If true, mutate the stylesheet; otherwise create new one
    # @return [Stylesheet] Merged stylesheet
    def self.flatten(stylesheet, mutate: false)
      # Separate AtRules (pass-through) from regular Rules (to merge)
      at_rules = []
      regular_rules = []

      stylesheet.rules.each do |rule|
        if rule.at_rule?
          at_rules << rule
        else
          regular_rules << rule
        end
      end

      # Expand shorthands in regular rules only (AtRules don't have declarations)
      # NOTE: Using manual each + concat instead of .flat_map for performance.
      # The concise form (.flat_map) is ~5-10% slower depending on number of shorthands to expand.
      # NOTE: Fast-path check for shorthands (Hash lookup) avoids calling expand_shorthand
      # for declarations that are not shorthands (~20% faster than calling method unconditionally).
      regular_rules.each do |rule|
        expanded = []
        rule.declarations.each do |decl|
          if SHORTHAND_PROPERTIES[decl.property]
            expanded.concat(expand_shorthand(decl))
          else
            expanded << decl
          end
        end
        rule.declarations.replace(expanded)
      end

      merged_rules = []

      # Group by (selector, media_query_id) instead of just selector
      # Rules with same selector but different media contexts should NOT be merged
      # NOTE: Using manual each instead of .group_by to avoid intermediate hash allocation.
      by_selector_and_media = {}
      regular_rules.each do |rule|
        media_query_id = rule.media_query_id
        key = [rule.selector, media_query_id]
        (by_selector_and_media[key] ||= []) << rule
      end

      # Track old rule ID to new merged rule index mapping (only for rules in media queries)
      old_to_new_id = {}
      by_selector_and_media.each do |(_selector, media_query_id), rules|
        merged_rule = flatten_rules_for_selector(rules.first.selector, rules)
        next unless merged_rule

        # Only build mapping for rules that are in media queries
        if media_query_id
          new_index = merged_rules.length

          rules.each do |old_rule|
            old_to_new_id[old_rule.id] = new_index
          end
        end
        merged_rules << merged_rule
      end

      # Recreate shorthands where possible
      merged_rules.each { |rule| recreate_shorthands!(rule) }

      # Assign new IDs before checking divergence (so we can build correct selector_lists hash)
      merged_rules.each_with_index { |rule, i| rule.id = i }

      # Handle selector list divergence: remove rules from selector lists if declarations no longer match
      # This makes selector_list_id authoritative - if set, declarations MUST be identical
      # Only process if selector_lists is enabled in the stylesheet's parser options
      selector_lists = {}
      parser_options = stylesheet.instance_variable_get(:@parser_options) || {}
      if parser_options[:selector_lists]
        update_selector_lists_for_divergence!(merged_rules, selector_lists)
      end

      # Add passthrough AtRules to output
      merged_rules.concat(at_rules)

      # Rebuild media_index from rules' media_query_id
      # This ensures media_index is consistent with the MediaQuery objects
      media_queries = stylesheet.instance_variable_get(:@media_queries)
      media_query_lists = stylesheet.instance_variable_get(:@_media_query_lists)
      new_media_index = {}

      # Build reverse map: media_query_id => list_id (one-time cost)
      mq_id_to_list_id = {}
      media_query_lists.each do |list_id, mq_ids|
        mq_ids.each { |mq_id| mq_id_to_list_id[mq_id] = list_id }
      end

      merged_rules.each do |rule|
        next unless rule.is_a?(Rule) && rule.media_query_id

        # Check if this rule's media_query_id is part of a list
        list_id = mq_id_to_list_id[rule.media_query_id]

        if list_id
          # This rule is in a compound media query (e.g., "@media screen, print")
          # Index it under ALL media types in the list
          mq_ids = media_query_lists[list_id]
          mq_ids.each do |mq_id|
            mq = media_queries[mq_id]
            next unless mq

            media_type = mq.type
            new_media_index[media_type] ||= []
            new_media_index[media_type] << rule.id
          end
        else
          # Single media query - just index under its type
          mq = media_queries[rule.media_query_id]
          next unless mq

          media_type = mq.type
          new_media_index[media_type] ||= []
          new_media_index[media_type] << rule.id
        end
      end

      # Deduplicate arrays once at the end
      new_media_index.each_value(&:uniq!)

      # Create result stylesheet
      if mutate
        stylesheet.instance_variable_set(:@rules, merged_rules)
        stylesheet.instance_variable_set(:@media_index, new_media_index)
        # @media_queries and @_media_query_lists stay the same - preserved from input
        # Update selector lists with divergence tracking
        stylesheet.instance_variable_set(:@_selector_lists, selector_lists)
        stylesheet
      else
        # Create new Stylesheet with merged rules
        result = Stylesheet.new
        result.instance_variable_set(:@rules, merged_rules)
        result.instance_variable_set(:@media_index, new_media_index)
        result.instance_variable_set(:@media_queries, media_queries)
        result.instance_variable_set(:@_media_query_lists, media_query_lists)
        result.instance_variable_set(:@charset, stylesheet.charset)
        result.instance_variable_set(:@_selector_lists, selector_lists)
        result
      end
    end

    # Merge multiple rules with same selector
    #
    # @param selector [String] The selector
    # @param rules [Array<Rule>] Rules with this selector
    # @return [Rule] Merged rule with cascaded declarations
    def self.flatten_rules_for_selector(selector, rules)
      # Build declaration map: property => [source_order, specificity, important, value]
      decl_map = {}

      rules.each do |rule|
        spec = rule.specificity || calculate_specificity(rule.selector)

        rule.declarations.each_with_index do |decl, idx|
          # Property is already US-ASCII and lowercase from parser
          prop = decl.property

          # Calculate source order (higher = later)
          source_order = rule.id * 1000 + idx

          existing = decl_map[prop]

          # Apply cascade rules:
          # 1. !important always wins over non-important
          # 2. Higher specificity wins
          # 3. Later source order wins (if specificity and importance are equal)

          if existing.nil?
            decl_map[prop] = [source_order, spec, decl.important, decl.value]
          else
            existing_order, existing_spec, existing_important, _existing_val = existing

            # Determine winner
            should_replace = false

            if decl.important && !existing_important
              # New is important, existing is not -> new wins
              should_replace = true
            elsif !decl.important && existing_important
              # Existing is important, new is not -> existing wins
              should_replace = false
            elsif spec > existing_spec
              # Higher specificity wins
              should_replace = true
            elsif spec < existing_spec
              # Lower specificity loses
              should_replace = false
            else
              # Same specificity and importance -> later source order wins
              should_replace = source_order > existing_order
            end

            if should_replace
              decl_map[prop] = [source_order, spec, decl.important, decl.value]
            end
          end
        end
      end

      # Build final declarations array
      # NOTE: Using each with << instead of map for performance (1.05-1.11x faster)
      # The << pattern is faster than map's implicit array return (even without YJIT)
      #
      # NOTE: We don't sort by source_order here because:
      # 1. Hash iteration order in Ruby is insertion order (since Ruby 1.9)
      # 2. Declaration order doesn't affect CSS behavior (cascade is already resolved)
      # 3. Sorting would add overhead for purely aesthetic output
      # The output order is roughly source order but may vary when properties are
      # overridden by later rules with higher specificity or importance.
      declarations = []
      decl_map.each do |prop, (_order, _spec, important, value)|
        declarations << Declaration.new(prop, value, important)
      end

      return nil if declarations.empty?

      # Preserve selector_list_id if all rules in group share the same one
      selector_list_ids = rules.filter_map(&:selector_list_id)
      selector_list_ids.uniq!
      selector_list_id = selector_list_ids.size == 1 ? selector_list_ids.first : nil

      # All rules being merged have the same media_query_id (they were grouped by it)
      media_query_id = rules.first.media_query_id

      # Create merged rule
      Rule.new(
        0, # ID will be updated later
        selector,
        declarations,
        rules.first.specificity, # Use first rule's specificity
        nil,  # No parent after flattening
        nil,  # No nesting style after flattening
        selector_list_id, # Preserve if all rules share same ID
        media_query_id # Preserve media context
      )
    end

    # Calculate specificity for a selector
    #
    # @param selector [String] CSS selector
    # @return [Integer] Specificity value
    def self.calculate_specificity(selector)
      Cataract.calculate_specificity(selector)
    end

    # Expand a single shorthand declaration into longhand declarations.
    # Returns an array of longhand declarations. If the declaration is not a shorthand,
    # returns an array with just that declaration.
    #
    # @param decl [Declaration] Declaration to expand
    # @return [Array<Declaration>] Array of expanded longhand declarations
    # @api private
    def self.expand_shorthand(decl)
      case decl.property
      when 'margin'
        expand_margin(decl)
      when 'padding'
        expand_padding(decl)
      when 'border'
        expand_border(decl)
      when 'border-top', 'border-right', 'border-bottom', 'border-left'
        expand_border_side(decl)
      when 'border-width'
        expand_border_width(decl)
      when 'border-style'
        expand_border_style(decl)
      when 'border-color'
        expand_border_color(decl)
      when 'font'
        expand_font(decl)
      when 'background'
        expand_background(decl)
      when 'list-style'
        expand_list_style(decl)
      else
        # Not a shorthand, return as-is in an array
        [decl]
      end
    end

    # Expand margin shorthand
    def self.expand_margin(decl)
      sides = parse_four_sides(decl.value)
      [
        Declaration.new(PROP_MARGIN_TOP, sides[0], decl.important),
        Declaration.new(PROP_MARGIN_RIGHT, sides[1], decl.important),
        Declaration.new(PROP_MARGIN_BOTTOM, sides[2], decl.important),
        Declaration.new(PROP_MARGIN_LEFT, sides[3], decl.important)
      ]
    end

    # Expand padding shorthand
    def self.expand_padding(decl)
      sides = parse_four_sides(decl.value)
      [
        Declaration.new(PROP_PADDING_TOP, sides[0], decl.important),
        Declaration.new(PROP_PADDING_RIGHT, sides[1], decl.important),
        Declaration.new(PROP_PADDING_BOTTOM, sides[2], decl.important),
        Declaration.new(PROP_PADDING_LEFT, sides[3], decl.important)
      ]
    end

    # Parse four-sided value (margin/padding)
    # "10px" -> ["10px", "10px", "10px", "10px"]
    # "10px 20px" -> ["10px", "20px", "10px", "20px"]
    # "10px 20px 30px" -> ["10px", "20px", "30px", "20px"]
    # "10px 20px 30px 40px" -> ["10px", "20px", "30px", "40px"]
    def self.parse_four_sides(value)
      parts = split_on_whitespace(value)

      case parts.length
      when 1
        [parts[0], parts[0], parts[0], parts[0]]
      when 2
        [parts[0], parts[1], parts[0], parts[1]]
      when 3
        [parts[0], parts[1], parts[2], parts[1]]
      else
        [parts[0], parts[1], parts[2], parts[3]]
      end
    end

    # Split value on whitespace (handling calc() and other functions)
    def self.split_on_whitespace(value)
      parts = []
      current = String.new
      paren_depth = 0

      i = 0
      len = value.bytesize
      while i < len
        byte = value.getbyte(i)

        if byte == BYTE_LPAREN
          paren_depth += 1
          current << byte
        elsif byte == BYTE_RPAREN
          paren_depth -= 1
          current << byte
        elsif byte == BYTE_SPACE && paren_depth == 0
          parts << current unless current.empty?
          current = String.new
        else
          current << byte
        end

        i += 1
      end

      parts << current unless current.empty?
      parts
    end

    # Expand border shorthand (e.g., "1px solid red")
    def self.expand_border(decl)
      # Parse border value
      width, style, color = parse_border_value(decl.value)

      result = []

      # Expand to all sides using property constants
      if width
        result << Declaration.new(PROP_BORDER_TOP_WIDTH, width, decl.important)
        result << Declaration.new(PROP_BORDER_RIGHT_WIDTH, width, decl.important)
        result << Declaration.new(PROP_BORDER_BOTTOM_WIDTH, width, decl.important)
        result << Declaration.new(PROP_BORDER_LEFT_WIDTH, width, decl.important)
      end

      if style
        result << Declaration.new(PROP_BORDER_TOP_STYLE, style, decl.important)
        result << Declaration.new(PROP_BORDER_RIGHT_STYLE, style, decl.important)
        result << Declaration.new(PROP_BORDER_BOTTOM_STYLE, style, decl.important)
        result << Declaration.new(PROP_BORDER_LEFT_STYLE, style, decl.important)
      end

      if color
        result << Declaration.new(PROP_BORDER_TOP_COLOR, color, decl.important)
        result << Declaration.new(PROP_BORDER_RIGHT_COLOR, color, decl.important)
        result << Declaration.new(PROP_BORDER_BOTTOM_COLOR, color, decl.important)
        result << Declaration.new(PROP_BORDER_LEFT_COLOR, color, decl.important)
      end

      result
    end

    # Expand border-side shorthand (e.g., "border-top: 1px solid red")
    def self.expand_border_side(decl)
      # Extract side from property name (e.g., "border-top" -> "top")
      side = decl.property.byteslice(7..-1) # Skip "border-" prefix
      width, style, color = parse_border_value(decl.value)

      result = []

      # Map side to property constants
      if width
        width_prop = case side
                     when SIDE_TOP then PROP_BORDER_TOP_WIDTH
                     when SIDE_RIGHT then PROP_BORDER_RIGHT_WIDTH
                     when SIDE_BOTTOM then PROP_BORDER_BOTTOM_WIDTH
                     when SIDE_LEFT then PROP_BORDER_LEFT_WIDTH
                     end
        result << Declaration.new(width_prop, width, decl.important)
      end

      if style
        style_prop = case side
                     when SIDE_TOP then PROP_BORDER_TOP_STYLE
                     when SIDE_RIGHT then PROP_BORDER_RIGHT_STYLE
                     when SIDE_BOTTOM then PROP_BORDER_BOTTOM_STYLE
                     when SIDE_LEFT then PROP_BORDER_LEFT_STYLE
                     end
        result << Declaration.new(style_prop, style, decl.important)
      end

      if color
        color_prop = case side
                     when SIDE_TOP then PROP_BORDER_TOP_COLOR
                     when SIDE_RIGHT then PROP_BORDER_RIGHT_COLOR
                     when SIDE_BOTTOM then PROP_BORDER_BOTTOM_COLOR
                     when SIDE_LEFT then PROP_BORDER_LEFT_COLOR
                     end
        result << Declaration.new(color_prop, color, decl.important)
      end

      result
    end

    # Expand border-width shorthand
    def self.expand_border_width(decl)
      sides = parse_four_sides(decl.value)
      [
        Declaration.new(PROP_BORDER_TOP_WIDTH, sides[0], decl.important),
        Declaration.new(PROP_BORDER_RIGHT_WIDTH, sides[1], decl.important),
        Declaration.new(PROP_BORDER_BOTTOM_WIDTH, sides[2], decl.important),
        Declaration.new(PROP_BORDER_LEFT_WIDTH, sides[3], decl.important)
      ]
    end

    # Expand border-style shorthand
    def self.expand_border_style(decl)
      sides = parse_four_sides(decl.value)
      [
        Declaration.new(PROP_BORDER_TOP_STYLE, sides[0], decl.important),
        Declaration.new(PROP_BORDER_RIGHT_STYLE, sides[1], decl.important),
        Declaration.new(PROP_BORDER_BOTTOM_STYLE, sides[2], decl.important),
        Declaration.new(PROP_BORDER_LEFT_STYLE, sides[3], decl.important)
      ]
    end

    # Expand border-color shorthand
    def self.expand_border_color(decl)
      sides = parse_four_sides(decl.value)
      [
        Declaration.new(PROP_BORDER_TOP_COLOR, sides[0], decl.important),
        Declaration.new(PROP_BORDER_RIGHT_COLOR, sides[1], decl.important),
        Declaration.new(PROP_BORDER_BOTTOM_COLOR, sides[2], decl.important),
        Declaration.new(PROP_BORDER_LEFT_COLOR, sides[3], decl.important)
      ]
    end

    # Parse border value (e.g., "1px solid red" -> ["1px", "solid", "red"])
    def self.parse_border_value(value)
      parts = split_on_whitespace(value)
      width = nil
      style = nil
      color = nil

      # Identify each part by type
      parts.each do |part|
        if is_border_width?(part)
          width = part
        elsif is_border_style?(part)
          style = part
        else
          color = part # Assume color if not width or style
        end
      end

      [width, style, color]
    end

    # Check if value looks like a border width
    def self.is_border_width?(value)
      # Check for numeric values or width keywords
      return true if BORDER_WIDTH_KEYWORDS.include?(value)

      # Check if value contains a digit (byte-by-byte)
      i = 0
      len = value.bytesize
      while i < len
        byte = value.getbyte(i)
        return true if byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9

        i += 1
      end

      false
    end

    # Check if value is a border style
    def self.is_border_style?(value)
      BORDER_STYLE_KEYWORDS.include?(value)
    end

    # Expand font shorthand
    # Format: [style] [variant] [weight] size[/line-height] family
    def self.expand_font(decl)
      value = decl.value
      parts = split_on_whitespace(value)

      # Need at least 2 parts (size and family)
      return [decl] if parts.length < 2

      # Parse from left to right
      # Optional: style, variant, weight (can appear in any order)
      # Required: size (with optional /line-height), family

      i = 0
      style = nil
      variant = nil
      weight = nil
      size = nil
      line_height = nil
      family_parts = []

      # Process optional style/variant/weight
      while i < parts.length - 1 # Leave at least 1 for family
        part = parts[i]

        # Check if this could be size (has digit or is a size keyword)
        if is_font_size?(part)
          # This is the size, rest is family
          size_part = part

          # Check for line-height (find '/' byte)
          slash_idx = nil
          j = 0
          len = size_part.bytesize
          while j < len
            if size_part.getbyte(j) == BYTE_SLASH_FWD
              slash_idx = j
              break
            end
            j += 1
          end

          if slash_idx
            size = size_part.byteslice(0, slash_idx)
            line_height = size_part.byteslice((slash_idx + 1)..-1)
          else
            size = size_part
          end

          # Rest is family
          family_parts = parts[(i + 1)..-1]
          break
        elsif is_font_style?(part)
          style = part
        elsif is_font_variant?(part)
          variant = part
        elsif is_font_weight?(part)
          weight = part
        else
          # Unknown, might be start of family - treat everything from here as family
          family_parts = parts[i..-1]
          break
        end

        i += 1
      end

      family = family_parts.join(' ')

      # Font shorthand sets ALL longhand properties
      # Unspecified values get CSS initial values
      # Size and family are required; if missing, return unexpanded
      return [decl] if !size || family.empty?

      result = []
      result << Declaration.new(PROP_FONT_STYLE, style || 'normal', decl.important)
      result << Declaration.new(PROP_FONT_VARIANT, variant || 'normal', decl.important)
      result << Declaration.new(PROP_FONT_WEIGHT, weight || 'normal', decl.important)
      result << Declaration.new(PROP_FONT_SIZE, size, decl.important)
      result << Declaration.new(PROP_LINE_HEIGHT, line_height || 'normal', decl.important)
      result << Declaration.new(PROP_FONT_FAMILY, family, decl.important)

      result
    end

    # Check if value is a font size
    def self.is_font_size?(value)
      # Has digit or is a keyword
      i = 0
      len = value.bytesize
      while i < len
        byte = value.getbyte(i)
        return true if byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9

        i += 1
      end
      FONT_SIZE_KEYWORDS.include?(value)
    end

    # Check if value is a font style
    def self.is_font_style?(value)
      FONT_STYLE_KEYWORDS.include?(value)
    end

    # Check if value is a font variant
    def self.is_font_variant?(value)
      FONT_VARIANT_KEYWORDS.include?(value)
    end

    # Check if value is a font weight
    def self.is_font_weight?(value)
      # Check for numeric weights like 400, 700
      i = 0
      len = value.bytesize
      while i < len
        byte = value.getbyte(i)
        return true if byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9

        i += 1
      end
      FONT_WEIGHT_KEYWORDS.include?(value)
    end

    # Expand background shorthand
    # Format: [color] [image] [repeat] [attachment] [position]
    def self.expand_background(decl)
      value = decl.value
      parts = split_on_whitespace(value)

      return [decl] if parts.empty?

      # Parse background components (simple heuristic)
      # According to CSS spec, background shorthand sets ALL properties
      # Any unspecified values get their initial values
      color = nil
      image = nil
      repeat = nil
      attachment = nil
      position = nil

      parts.each do |part|
        if starts_with_url?(part) || part == 'none'
          image = part
        elsif BACKGROUND_REPEAT_KEYWORDS.include?(part)
          repeat = part
        elsif BACKGROUND_ATTACHMENT_KEYWORDS.include?(part)
          attachment = part
        elsif is_position_value?(part)
          position ||= String.new
          position << ' ' unless position.empty?
          position << part
        else
          # Assume it's a color
          color = part
        end
      end

      # Background shorthand sets ALL longhand properties
      # Unspecified values get CSS initial values
      result = []
      result << Declaration.new(PROP_BACKGROUND_COLOR, color || 'transparent', decl.important)
      result << Declaration.new(PROP_BACKGROUND_IMAGE, image || 'none', decl.important)
      result << Declaration.new(PROP_BACKGROUND_REPEAT, repeat || 'repeat', decl.important)
      result << Declaration.new(PROP_BACKGROUND_ATTACHMENT, attachment || 'scroll', decl.important)
      result << Declaration.new(PROP_BACKGROUND_POSITION, position || '0% 0%', decl.important)

      result
    end

    # Check if value starts with 'url('
    def self.starts_with_url?(value)
      return false if value.bytesize < 4

      value.getbyte(0) == BYTE_LOWER_U &&
        value.getbyte(1) == BYTE_LOWER_R &&
        value.getbyte(2) == BYTE_LOWER_L &&
        value.getbyte(3) == BYTE_LPAREN
    end

    # Check if value is a position value (for background-position)
    def self.is_position_value?(value)
      return true if BACKGROUND_POSITION_KEYWORDS.include?(value)

      # Check for '%' or digits
      i = 0
      len = value.bytesize
      while i < len
        byte = value.getbyte(i)
        return true if byte == BYTE_PERCENT
        return true if byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9

        i += 1
      end
      false
    end

    # Expand list-style shorthand
    # Format: [type] [position] [image]
    def self.expand_list_style(decl)
      value = decl.value
      parts = split_on_whitespace(value)

      return [decl] if parts.empty?

      result = []
      type = nil
      position = nil
      image = nil

      parts.each do |part|
        if starts_with_url?(part) || part == 'none'
          image = part
        elsif LIST_STYLE_POSITION_KEYWORDS.include?(part)
          position = part
        else
          # Assume it's a type (disc, circle, square, etc.)
          type = part
        end
      end

      result << Declaration.new(PROP_LIST_STYLE_TYPE, type, decl.important) if type
      result << Declaration.new(PROP_LIST_STYLE_POSITION, position, decl.important) if position
      result << Declaration.new(PROP_LIST_STYLE_IMAGE, image, decl.important) if image

      result.empty? ? [decl] : result
    end

    # Recreate shorthand properties where possible (mutates declarations)
    #
    # @param rule [Rule] Rule to recreate shorthands in
    def self.recreate_shorthands!(rule)
      # Build property map
      prop_map = {}
      rule.declarations.each { |d| prop_map[d.property] = d }

      # Try to recreate margin
      recreate_margin!(rule, prop_map)

      # Try to recreate padding
      recreate_padding!(rule, prop_map)

      # Try to recreate border
      recreate_border!(rule, prop_map)

      # Try to recreate list-style
      recreate_list_style!(rule, prop_map)

      # Try to recreate font
      recreate_font!(rule, prop_map)

      # Try to recreate background
      recreate_background!(rule, prop_map)
    end

    # Try to recreate margin shorthand
    def self.recreate_margin!(rule, prop_map)
      # Use each + << instead of map (1.05-1.20x faster, called once per rule during merge)
      sides = []
      MARGIN_SIDES.each { |s| sides << prop_map[s] }
      return unless sides.all? # Need all four sides

      # Check if all have same importance
      # Use each + << instead of map
      importances = []
      sides.each { |s| importances << s.important }
      importances.uniq!
      return if importances.length > 1 # Mixed importance, can't create shorthand

      # Use each + << instead of map
      values = []
      sides.each { |s| values << s.value }
      important = sides.first.important

      # Create optimized shorthand
      shorthand_value = optimize_four_sides(values)

      # Remove individual sides and append shorthand
      # Note: We append rather than insert at original position to match C implementation behavior
      rule.declarations.reject! { |d| MARGIN_SIDES.include?(d.property) }
      rule.declarations << Declaration.new(PROP_MARGIN, shorthand_value, important)
    end

    # Try to recreate padding shorthand
    def self.recreate_padding!(rule, prop_map)
      # Use each + << instead of map (1.05-1.20x faster, called once per rule during merge)
      sides = []
      PADDING_SIDES.each { |s| sides << prop_map[s] }
      return unless sides.all?

      # Use each + << instead of map
      importances = []
      sides.each { |s| importances << s.important }
      importances.uniq!
      return if importances.length > 1

      # Use each + << instead of map
      values = []
      sides.each { |s| values << s.value }
      important = sides.first.important

      shorthand_value = optimize_four_sides(values)

      # Remove individual sides and append shorthand
      # Note: We append rather than insert at original position to match C implementation behavior
      rule.declarations.reject! { |d| PADDING_SIDES.include?(d.property) }
      rule.declarations << Declaration.new(PROP_PADDING, shorthand_value, important)
    end

    # Helper: Check if all declarations have same value and importance
    # Does single pass instead of multiple .map calls
    def self.check_all_same?(decls)
      return false if decls.empty?

      first_val = decls[0].value
      first_imp = decls[0].important

      i = 1
      while i < decls.length
        return false if decls[i].value != first_val
        return false if decls[i].important != first_imp

        i += 1
      end

      true
    end

    # Try to recreate border shorthand
    def self.recreate_border!(rule, prop_map)
      # Check if we have all width/style/color properties with same values for all sides
      # Use each + << instead of map (1.05-1.20x faster, called once per rule during merge)
      widths = []
      BORDER_WIDTHS.each { |p| widths << prop_map[p] }
      styles = []
      BORDER_STYLES.each { |p| styles << prop_map[p] }
      colors = []
      BORDER_COLORS.each { |p| colors << prop_map[p] }

      # Check if all sides have same values and can create full border shorthand
      # Check cheapest condition first (.all?), then do single pass for values/importance
      widths_all_same = widths.all? && check_all_same?(widths)
      styles_all_same = styles.all? && check_all_same?(styles)
      colors_all_same = colors.all? && check_all_same?(colors)

      # Can create FULL border shorthand ONLY if style is present (style is required for border shorthand)
      # AND all properties that are present have same values and importance
      if styles_all_same
        # Check if we have width and/or color with same importance as style
        can_create_border = true
        important = styles.first.important

        # If width is present, must be all-same and same importance
        if widths.all?
          can_create_border = false unless widths_all_same && widths.first.important == important
        end

        # If color is present, must be all-same and same importance
        if colors.all?
          can_create_border = false unless colors_all_same && colors.first.important == important
        end

        if can_create_border
          # Create full border shorthand
          parts = []
          parts << widths.first.value if widths_all_same
          parts << styles.first.value
          parts << colors.first.value if colors_all_same

          border_value = parts.join(' ')

          # Remove individual properties and append shorthand
          # Note: We append rather than insert at original position to match C implementation behavior
          rule.declarations.reject! { |d| BORDER_ALL.include?(d.property) }
          rule.declarations << Declaration.new(PROP_BORDER, border_value, important)
          return
        end
      end

      # Try to create border-width/style/color shorthands
      recreate_border_width!(rule, widths) if widths.all?
      recreate_border_style!(rule, styles) if styles.all?
      recreate_border_color!(rule, colors) if colors.all?
    end

    # Recreate border-width shorthand
    def self.recreate_border_width!(rule, widths)
      importances = widths.map(&:important).uniq
      return if importances.length > 1

      values = widths.map(&:value)
      important = widths.first.important

      shorthand_value = optimize_four_sides(values)

      rule.declarations.reject! { |d| BORDER_WIDTHS.include?(d.property) }
      rule.declarations << Declaration.new(PROP_BORDER_WIDTH, shorthand_value, important)
    end

    # Recreate border-style shorthand
    def self.recreate_border_style!(rule, styles)
      importances = styles.map(&:important).uniq
      return if importances.length > 1

      values = styles.map(&:value)
      important = styles.first.important

      shorthand_value = optimize_four_sides(values)

      rule.declarations.reject! { |d| BORDER_STYLES.include?(d.property) }
      rule.declarations << Declaration.new(PROP_BORDER_STYLE, shorthand_value, important)
    end

    # Recreate border-color shorthand
    def self.recreate_border_color!(rule, colors)
      importances = colors.map(&:important).uniq
      return if importances.length > 1

      values = colors.map(&:value)
      important = colors.first.important

      shorthand_value = optimize_four_sides(values)

      rule.declarations.reject! { |d| BORDER_COLORS.include?(d.property) }
      rule.declarations << Declaration.new(PROP_BORDER_COLOR, shorthand_value, important)
    end

    # Optimize four-sided value representation
    # ["10px", "10px", "10px", "10px"] -> "10px"
    # ["10px", "20px", "10px", "20px"] -> "10px 20px"
    # ["10px", "20px", "30px", "20px"] -> "10px 20px 30px"
    # ["10px", "20px", "30px", "40px"] -> "10px 20px 30px 40px"
    def self.optimize_four_sides(values)
      top, right, bottom, left = values

      if top == right && right == bottom && bottom == left
        top
      elsif top == bottom && right == left
        "#{top} #{right}"
      elsif right == left
        "#{top} #{right} #{bottom}"
      else
        "#{top} #{right} #{bottom} #{left}"
      end
    end

    # Try to recreate font shorthand
    # Requires: font-size and font-family (minimum)
    # Optional: font-style, font-variant, font-weight, line-height
    def self.recreate_font!(rule, prop_map)
      size = prop_map[PROP_FONT_SIZE]
      family = prop_map[PROP_FONT_FAMILY]

      # Need at least size and family
      return unless size && family

      # Check if all font properties have same importance
      font_decls = FONT_PROPERTIES.filter_map { |p| prop_map[p] }
      return if font_decls.empty?

      importances = font_decls.map(&:important).uniq
      return if importances.length > 1

      important = font_decls.first.important

      # Build font shorthand value
      # Strategy: Only omit defaults if we have ALL 6 properties (from shorthand expansion)
      # If we have a partial set, include all non-nil values
      style = prop_map[PROP_FONT_STYLE]&.value
      variant = prop_map[PROP_FONT_VARIANT]&.value
      weight = prop_map[PROP_FONT_WEIGHT]&.value
      line_height = prop_map[PROP_LINE_HEIGHT]&.value

      all_present = style && variant && weight && line_height
      parts = []

      if all_present
        # All properties present (likely from shorthand expansion) - omit defaults
        parts << style if style != 'normal'
        parts << variant if variant != 'normal'
        parts << weight if weight != 'normal'
      else
        # Partial set - include all non-nil values
        parts << style if style
        parts << variant if variant
        parts << weight if weight
      end

      # Required: size[/line-height]
      if all_present
        # Omit line-height if default
        if line_height != 'normal'
          parts << "#{size.value}/#{line_height}"
        else
          parts << size.value
        end
      else
        # Include line-height if present
        if line_height
          parts << "#{size.value}/#{line_height}"
        else
          parts << size.value
        end
      end

      # Required: family
      parts << family.value

      shorthand_value = parts.join(' ')

      # Remove individual properties and append shorthand
      # Note: We append rather than insert at original position to match C implementation behavior
      rule.declarations.reject! { |d| FONT_PROPERTIES.include?(d.property) }
      rule.declarations << Declaration.new(PROP_FONT, shorthand_value, important)
    end

    # Try to recreate background shorthand
    # Can combine: background-color, background-image, background-repeat, etc.
    def self.recreate_background!(rule, prop_map)
      bg_props = BACKGROUND_PROPERTIES
      bg_decls = bg_props.filter_map { |p| prop_map[p] }

      # Need at least 2 properties to create shorthand
      # Single properties should stay as longhands (e.g., background-color: blue)
      # because shorthand resets all other properties to initial values
      return if bg_decls.length < 2

      # Check if all have same importance
      importances = bg_decls.map(&:important).uniq
      return if importances.length > 1

      important = bg_decls.first.important

      # Build background shorthand value
      # Strategy: Only omit defaults if we have ALL 5 properties (from shorthand expansion)
      # If we have a partial set (explicit longhands), include all values
      color = prop_map[PROP_BACKGROUND_COLOR]&.value
      image = prop_map[PROP_BACKGROUND_IMAGE]&.value
      repeat = prop_map[PROP_BACKGROUND_REPEAT]&.value
      position = prop_map[PROP_BACKGROUND_POSITION]&.value
      attachment = prop_map[PROP_BACKGROUND_ATTACHMENT]&.value

      all_present = color && image && repeat && position && attachment
      parts = []

      if all_present
        # All 5 properties present (likely from shorthand expansion) - omit defaults
        parts << color if color != 'transparent'
        parts << image if image != 'none'
        parts << repeat if repeat != 'repeat'
        parts << position if position != '0% 0%'
        parts << attachment if attachment != 'scroll'
      else
        # Partial set (explicit longhands) - include all non-nil values
        parts << color if color
        parts << image if image
        parts << repeat if repeat
        parts << position if position
        parts << attachment if attachment
      end

      shorthand_value = parts.join(' ')

      # Remove individual properties and append shorthand
      # Note: We append rather than insert at original position to match C implementation behavior
      rule.declarations.reject! { |d| BACKGROUND_PROPERTIES.include?(d.property) }
      rule.declarations << Declaration.new(PROP_BACKGROUND, shorthand_value, important)
    end

    # Try to recreate list-style shorthand
    # Can combine: list-style-type, list-style-position, list-style-image
    def self.recreate_list_style!(rule, prop_map)
      ls_props = LIST_STYLE_PROPERTIES
      ls_decls = ls_props.filter_map { |p| prop_map[p] }

      # Need at least 2 properties to create shorthand
      return if ls_decls.length < 2

      # Check if all have same importance
      importances = ls_decls.map(&:important).uniq
      return if importances.length > 1

      important = ls_decls.first.important

      # Build list-style shorthand value
      parts = []
      parts << prop_map[PROP_LIST_STYLE_TYPE].value if prop_map[PROP_LIST_STYLE_TYPE]
      parts << prop_map[PROP_LIST_STYLE_POSITION].value if prop_map[PROP_LIST_STYLE_POSITION]
      parts << prop_map[PROP_LIST_STYLE_IMAGE].value if prop_map[PROP_LIST_STYLE_IMAGE]

      shorthand_value = parts.join(' ')

      # Remove individual properties and append shorthand
      # Note: We append rather than insert at original position to match C implementation behavior
      rule.declarations.reject! { |d| LIST_STYLE_PROPERTIES.include?(d.property) }
      rule.declarations << Declaration.new(PROP_LIST_STYLE, shorthand_value, important)
    end

    # Update selector lists to remove diverged rules
    #
    # After flattening/cascade, rules that were in the same selector list may have
    # different declarations. This method builds the selector_lists hash with only
    # rules that still match, and clears selector_list_id for diverged rules.
    #
    # @param merged_rules [Array<Rule>] Flattened rules (with new IDs assigned)
    # @param selector_lists [Hash] Empty hash to populate with list_id => Array of rule IDs
    def self.update_selector_lists_for_divergence!(merged_rules, selector_lists)
      # Group merged rules by selector_list_id (skip rules with no list)
      # Note: Using manual each loop instead of .select{}.group_by for performance.
      # The more concise form (.select + .group_by) is ~50-60% slower due to intermediate array allocation.
      rules_by_list = {}
      merged_rules.each do |r|
        next unless r.selector_list_id

        (rules_by_list[r.selector_list_id] ||= []) << r
      end

      # For each selector list, check if declarations still match
      rules_by_list.each do |list_id, rules_in_list|
        # Skip if only one rule in list (nothing to compare)
        next if rules_in_list.size <= 1

        # Get first rule as reference
        reference_rule = rules_in_list.first
        reference_decls = reference_rule.declarations

        # Find rules that still match (have identical declarations)
        matching_rules = [reference_rule]

        rules_in_list[1..].each do |rule|
          if declarations_equal?(reference_decls, rule.declarations)
            matching_rules << rule
          else
            # Clear selector_list_id for diverged rule
            rule.selector_list_id = nil
          end
        end

        # Only keep the selector list if at least 2 rules still match
        if matching_rules.size >= 2
          # Build selector_lists hash with NEW rule IDs
          selector_lists[list_id] = matching_rules.map(&:id)
        else
          # Clear selector_list_id for the last remaining rule too
          matching_rules.each { |r| r.selector_list_id = nil }
        end
      end
    end

    # Check if two declaration arrays are identical
    #
    # @param decls1 [Array<Declaration>]
    # @param decls2 [Array<Declaration>]
    # @return [Boolean]
    def self.declarations_equal?(decls1, decls2)
      return false if decls1.size != decls2.size

      # Compare each declaration (property, value, important must all match)
      decls1.zip(decls2).all? do |d1, d2|
        d1.property == d2.property &&
          d1.value == d2.value &&
          d1.important == d2.important
      end
    end

    # Mark all methods except flatten and expand_shorthand as private
    private_class_method :flatten_rules_for_selector, :calculate_specificity,
                         :expand_margin, :expand_padding, :parse_four_sides, :split_on_whitespace,
                         :expand_border, :expand_border_side, :expand_border_width, :expand_border_style,
                         :expand_border_color, :parse_border_value, :is_border_width?, :is_border_style?,
                         :expand_font, :is_font_size?, :is_font_style?, :is_font_variant?, :is_font_weight?,
                         :expand_background, :starts_with_url?, :is_position_value?, :expand_list_style,
                         :recreate_shorthands!, :recreate_margin!, :recreate_padding!, :check_all_same?,
                         :recreate_border!, :recreate_border_width!, :recreate_border_style!, :recreate_border_color!,
                         :optimize_four_sides, :recreate_font!, :recreate_background!, :recreate_list_style!,
                         :update_selector_lists_for_divergence!, :declarations_equal?
  end
end
