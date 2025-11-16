# frozen_string_literal: true

# Pure Ruby CSS parser - Parser class
#
# IMPORTANT: This code is intentionally written in a non-idiomatic style.
# - Performance comes first - mirrors the C implementation
# - Character-by-character parsing (NO REGEXP)
# - Minimal abstraction, lots of state mutation
# - Optimized for speed, not readability
#
# Do NOT refactor to "clean Ruby" without benchmarking - you will make it slower.
#
# Example: RuboCop suggests using `.positive?` instead of `> 0`, but benchmarking
# shows `> 0` is 1.26x faster. These micro-optimizations
# matter in a hot parsing loop.

module Cataract
  # Pure Ruby CSS parser - char-by-char, NO REGEXP
  class Parser
    # Maximum parse depth (prevent infinite recursion)
    MAX_PARSE_DEPTH = 10

    # Maximum media queries (prevent symbol table exhaustion)
    MAX_MEDIA_QUERIES = 1000

    # Maximum property name/value lengths
    MAX_PROPERTY_NAME_LENGTH = 256
    MAX_PROPERTY_VALUE_LENGTH = 32_768

    AT_RULE_TYPES = %w[supports layer container scope].freeze

    attr_reader :css, :pos, :len

    # Extract substring and force specified encoding
    # Per CSS spec, charset detection happens at byte-stream level before parsing.
    # All parsing operations treat content as UTF-8 (spec requires fallback to UTF-8).
    # This prevents ArgumentError on broken/invalid encodings when calling string methods.
    # Optional encoding parameter (default: 'UTF-8', use 'US-ASCII' for property names)
    def byteslice_encoded(start, length, encoding: 'UTF-8')
      @css.byteslice(start, length).force_encoding(encoding)
    end

    # Helper: Case-insensitive ASCII byte comparison
    # Compares bytes at given position with ASCII pattern (case-insensitive)
    # Safe to use even if position is in middle of multi-byte UTF-8 characters
    # Returns true if match, false otherwise
    def match_ascii_ci?(str, pos, pattern)
      pattern_len = pattern.bytesize
      return false if pos + pattern_len > str.bytesize

      i = 0
      while i < pattern_len
        str_byte = str.getbyte(pos + i)
        pat_byte = pattern.getbyte(i)

        # Convert both to lowercase for comparison (ASCII only: A-Z -> a-z)
        str_byte += BYTE_CASE_DIFF if str_byte >= BYTE_UPPER_A && str_byte <= BYTE_UPPER_Z
        pat_byte += BYTE_CASE_DIFF if pat_byte >= BYTE_UPPER_A && pat_byte <= BYTE_UPPER_Z

        return false if str_byte != pat_byte

        i += 1
      end

      true
    end

    def initialize(css_string, parser_options: {}, parent_media_sym: nil, depth: 0)
      @css = css_string.dup.freeze
      @pos = 0
      @len = @css.bytesize
      @parent_media_sym = parent_media_sym

      # Parser options with defaults
      @parser_options = {
        selector_lists: true
      }.merge(parser_options)

      # Extract selector_lists option to ivar to avoid repeated hash lookups in hot path
      @selector_lists_enabled = @parser_options[:selector_lists]

      # Parser state
      @rules = []                    # Flat array of Rule structs
      @_media_index = {}             # Symbol => Array of rule IDs
      @_selector_lists = {}          # Hash: list_id => Array of rule IDs
      @_next_selector_list_id = 0    # Counter for selector list IDs
      @imports = []                  # Array of ImportStatement structs
      @rule_id_counter = 0           # Next rule ID (0-indexed)
      @media_query_count = 0         # Safety limit
      @_has_nesting = false          # Set to true if any nested rules found
      @depth = depth                 # Current recursion depth (passed from parent parser)
      @charset = nil                 # @charset declaration
    end

    def parse
      # @import statements are now handled in parse_at_rule
      # They must come before all rules (except @charset) per CSS spec

      # Main parsing loop - char-by-char, NO REGEXP
      until eof?
        skip_ws_and_comments
        break if eof?

        # Peek at next byte to determine what to parse
        byte = peek_byte

        # Check for at-rules (@media, @charset, etc)
        if byte == BYTE_AT
          parse_at_rule
          next
        end

        # Must be a selector-based rule
        selector = parse_selector

        if selector.nil? || selector.empty?
          next
        end

        # Find the block boundaries
        decl_start = @pos # Should be right after the {
        decl_end = find_matching_brace(decl_start)

        # Check if block has nested selectors
        if has_nested_selectors?(decl_start, decl_end)
          # NESTED PATH: Parse mixed declarations + nested rules
          # Split comma-separated selectors and parse each one
          selectors = selector.split(',')

          selectors.each do |individual_selector|
            individual_selector.strip!
            next if individual_selector.empty?

            # Get rule ID for this selector
            current_rule_id = @rule_id_counter
            @rule_id_counter += 1

            # Reserve parent's position in rules array (ensures parent comes before nested)
            parent_position = @rules.length
            @rules << nil # Placeholder

            # Parse mixed block (declarations + nested selectors)
            @depth += 1
            parent_declarations = parse_mixed_block(decl_start, decl_end,
                                                    individual_selector, current_rule_id, @parent_media_sym)
            @depth -= 1

            # Create parent rule and replace placeholder
            rule = Rule.new(
              current_rule_id,
              individual_selector,
              parent_declarations,
              nil,  # specificity
              nil,  # parent_rule_id (top-level)
              nil   # nesting_style
            )

            @rules[parent_position] = rule
            @_media_index[@parent_media_sym] ||= [] if @parent_media_sym
            @_media_index[@parent_media_sym] << current_rule_id if @parent_media_sym
          end

          # Move position past the closing brace
          @pos = decl_end
          @pos += 1 if @pos < @len && @css.getbyte(@pos) == BYTE_RBRACE
        else
          # NON-NESTED PATH: Parse declarations only
          @pos = decl_start # Reset to start of block
          declarations = parse_declarations

          # Split comma-separated selectors into individual rules
          selectors = selector.split(',')

          # Determine if we should track this as a selector list
          # Check boolean first to potentially avoid size() call via short-circuit evaluation
          list_id = nil
          if @selector_lists_enabled && selectors.size > 1
            list_id = @_next_selector_list_id
            @_next_selector_list_id += 1
            @_selector_lists[list_id] = []
          end

          selectors.each do |individual_selector|
            individual_selector.strip!
            next if individual_selector.empty?

            rule_id = @rule_id_counter

            # Dup declarations for each rule in a selector list to avoid shared state
            # (principle of least surprise - modifying one rule shouldn't affect others)
            # Must deep dup: both the array and the Declaration objects inside
            rule_declarations = if list_id
                                  declarations.map { |d| Declaration.new(d.property, d.value, d.important) }
                                else
                                  declarations
                                end

            # Create Rule struct (with selector_list_id as 7th parameter)
            rule = Rule.new(
              rule_id,             # id
              individual_selector, # selector
              rule_declarations,   # declarations
              nil,                 # specificity (calculated lazily)
              nil,                 # parent_rule_id
              nil,                 # nesting_style
              list_id              # selector_list_id
            )

            @rules << rule
            @rule_id_counter += 1

            # Track in selector list if applicable
            @_selector_lists[list_id] << rule_id if list_id
          end
        end
      end

      {
        rules: @rules,
        _media_index: @_media_index,
        _selector_lists: @_selector_lists,
        imports: @imports,
        charset: @charset,
        _has_nesting: @_has_nesting
      }
    end

    private

    # Check if we're at end of input
    def eof?
      @pos >= @len
    end

    # Peek current byte without advancing
    # @return [Integer, nil] Byte value or nil if EOF
    def peek_byte
      return nil if eof?

      @css.getbyte(@pos)
    end

    # Delegate to module-level helper methods (now work with bytes)
    def whitespace?(byte)
      Cataract.is_whitespace?(byte)
    end

    def letter?(byte)
      Cataract.letter?(byte)
    end

    def digit?(byte)
      Cataract.digit?(byte)
    end

    def ident_char?(byte)
      Cataract.ident_char?(byte)
    end

    def skip_whitespace
      @pos += 1 while !eof? && whitespace?(peek_byte)
    end

    def skip_comment # rubocop:disable Naming/PredicateMethod
      return false unless peek_byte == BYTE_SLASH && @css.getbyte(@pos + 1) == BYTE_STAR

      @pos += 2 # Skip /*
      while @pos + 1 < @len
        if @css.getbyte(@pos) == BYTE_STAR && @css.getbyte(@pos + 1) == BYTE_SLASH
          @pos += 2 # Skip */
          return true
        end
        @pos += 1
      end
      true
    end

    # Skip whitespace and comments until no more progress can be made
    #
    # Optimization: Using `begin...end until` instead of `loop + break` reduces VM overhead:
    # - loop + break: 29 instructions with catch table for break/redo/next, uses throw/send
    # - begin...end until: 24 instructions, simple jump-based loop, no catch table
    # Benchmark shows 15-51% speedup depending on YJIT
    def skip_ws_and_comments
      begin
        old_pos = @pos
        skip_whitespace
        skip_comment
      end until @pos == old_pos # No progress made # rubocop:disable Lint/Loop
    end

    # Find matching closing brace
    # Translated from C: see ext/cataract/css_parser.c find_matching_brace
    def find_matching_brace(start_pos)
      depth = 1
      pos = start_pos

      while pos < @len
        byte = @css.getbyte(pos)
        if byte == BYTE_LBRACE
          depth += 1
        elsif byte == BYTE_RBRACE
          depth -= 1
          break if depth == 0 # Found matching brace, exit immediately
        end
        pos += 1
      end

      pos
    end

    # Parse selector (read until '{')
    def parse_selector
      start_pos = @pos

      # Read until we find '{'
      until eof? || peek_byte == BYTE_LBRACE # Flip to save a 'opt_not' instruction: while !eof? && peek_byte != BYTE_LBRACE
        @pos += 1
      end

      # If we hit EOF without finding '{', return nil
      return nil if eof?

      # Extract selector text
      selector_text = byteslice_encoded(start_pos, @pos - start_pos)

      # Skip the '{'
      @pos += 1 if peek_byte == BYTE_LBRACE

      # Trim whitespace from selector (in-place to avoid allocation)
      selector_text.strip!
      selector_text
    end

    # Parse mixed block containing declarations AND nested selectors/at-rules
    # Translated from C: see ext/cataract/css_parser.c parse_mixed_block
    # Returns: Array of declarations (only the declarations, not nested rules)
    def parse_mixed_block(start_pos, end_pos, parent_selector, parent_rule_id, parent_media_sym)
      # Check recursion depth to prevent stack overflow
      if @depth > MAX_PARSE_DEPTH
        raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
      end

      declarations = []
      pos = start_pos

      while pos < end_pos
        # Skip whitespace and comments
        while pos < end_pos && whitespace?(@css.getbyte(pos))
          pos += 1
        end
        break if pos >= end_pos

        # Skip comments
        if pos + 1 < end_pos && @css.getbyte(pos) == BYTE_SLASH && @css.getbyte(pos + 1) == BYTE_STAR
          pos += 2
          while pos + 1 < end_pos
            if @css.getbyte(pos) == BYTE_STAR && @css.getbyte(pos + 1) == BYTE_SLASH
              pos += 2
              break
            end
            pos += 1
          end
          next
        end

        # Check if this is a nested @media query
        if @css.getbyte(pos) == BYTE_AT && pos + 6 < end_pos &&
           byteslice_encoded(pos, 6) == '@media' &&
           (pos + 6 >= end_pos || whitespace?(@css.getbyte(pos + 6)))
          # Nested @media - parse with parent selector as context
          media_start = pos + 6
          while media_start < end_pos && whitespace?(@css.getbyte(media_start))
            media_start += 1
          end

          # Find opening brace
          media_query_end = media_start
          while media_query_end < end_pos && @css.getbyte(media_query_end) != BYTE_LBRACE
            media_query_end += 1
          end
          break if media_query_end >= end_pos

          # Extract media query (trim trailing whitespace)
          media_query_end_trimmed = media_query_end
          while media_query_end_trimmed > media_start && whitespace?(@css.getbyte(media_query_end_trimmed - 1))
            media_query_end_trimmed -= 1
          end
          media_query_str = byteslice_encoded(media_start, media_query_end_trimmed - media_start)
          # Keep media query exactly as written - parentheses are required per CSS spec
          media_query_str.strip!
          media_sym = media_query_str.to_sym

          pos = media_query_end + 1 # Skip {

          # Find matching closing brace
          media_block_start = pos
          media_block_end = find_matching_brace(pos)
          pos = media_block_end
          pos += 1 if pos < end_pos # Skip }

          # Combine media queries: parent + child
          combined_media_sym = combine_media_queries(parent_media_sym, media_sym)

          # Create rule ID for this media rule
          media_rule_id = @rule_id_counter
          @rule_id_counter += 1

          # Parse mixed block recursively
          @depth += 1
          media_declarations = parse_mixed_block(media_block_start, media_block_end,
                                                 parent_selector, media_rule_id, combined_media_sym)
          @depth -= 1

          # Create rule with parent selector and declarations, associated with combined media query
          rule = Rule.new(
            media_rule_id,
            parent_selector,
            media_declarations,
            nil,  # specificity
            parent_rule_id,
            nil   # nesting_style (nil for @media nesting)
          )

          # Mark that we have nesting
          @_has_nesting = true unless parent_rule_id.nil?

          @rules << rule
          @_media_index[combined_media_sym] ||= []
          @_media_index[combined_media_sym] << media_rule_id

          next
        end

        # Check if this is a nested selector
        byte = @css.getbyte(pos)
        if byte == BYTE_AMPERSAND || byte == BYTE_DOT || byte == BYTE_HASH ||
           byte == BYTE_LBRACKET || byte == BYTE_COLON || byte == BYTE_ASTERISK ||
           byte == BYTE_GT || byte == BYTE_PLUS || byte == BYTE_TILDE || byte == BYTE_AT
          # Find the opening brace
          nested_sel_start = pos
          while pos < end_pos && @css.getbyte(pos) != BYTE_LBRACE
            pos += 1
          end
          break if pos >= end_pos

          nested_sel_end = pos
          # Trim trailing whitespace
          while nested_sel_end > nested_sel_start && whitespace?(@css.getbyte(nested_sel_end - 1))
            nested_sel_end -= 1
          end

          pos += 1 # Skip {

          # Find matching closing brace
          nested_block_start = pos
          nested_block_end = find_matching_brace(pos)
          pos = nested_block_end
          pos += 1 if pos < end_pos # Skip }

          # Extract nested selector and split on commas
          nested_selector_text = byteslice_encoded(nested_sel_start, nested_sel_end - nested_sel_start)
          nested_selectors = nested_selector_text.split(',')

          nested_selectors.each do |seg|
            seg.strip!
            next if seg.empty?

            # Resolve nested selector
            resolved_selector, nesting_style = resolve_nested_selector(parent_selector, seg)

            # Get rule ID
            rule_id = @rule_id_counter
            @rule_id_counter += 1

            # Recursively parse nested block
            @depth += 1
            nested_declarations = parse_mixed_block(nested_block_start, nested_block_end,
                                                    resolved_selector, rule_id, parent_media_sym)
            @depth -= 1

            # Create rule for nested selector
            rule = Rule.new(
              rule_id,
              resolved_selector,
              nested_declarations,
              nil, # specificity
              parent_rule_id,
              nesting_style
            )

            # Mark that we have nesting
            @_has_nesting = true unless parent_rule_id.nil?

            @rules << rule
            @_media_index[parent_media_sym] ||= [] if parent_media_sym
            @_media_index[parent_media_sym] << rule_id if parent_media_sym
          end

          next
        end

        # This is a declaration - parse it
        prop_start = pos
        while pos < end_pos && @css.getbyte(pos) != BYTE_COLON &&
              @css.getbyte(pos) != BYTE_SEMICOLON && @css.getbyte(pos) != BYTE_LBRACE
          pos += 1
        end

        if pos >= end_pos || @css.getbyte(pos) != BYTE_COLON
          # Malformed - skip to semicolon
          while pos < end_pos && @css.getbyte(pos) != BYTE_SEMICOLON
            pos += 1
          end
          pos += 1 if pos < end_pos
          next
        end

        prop_end = pos
        # Trim trailing whitespace
        while prop_end > prop_start && whitespace?(@css.getbyte(prop_end - 1))
          prop_end -= 1
        end

        property = byteslice_encoded(prop_start, prop_end - prop_start, encoding: 'US-ASCII')
        property.downcase!

        pos += 1 # Skip :

        # Skip leading whitespace in value
        while pos < end_pos && whitespace?(@css.getbyte(pos))
          pos += 1
        end

        # Parse value (read until ';' or '}')
        val_start = pos
        while pos < end_pos && @css.getbyte(pos) != BYTE_SEMICOLON && @css.getbyte(pos) != BYTE_RBRACE
          pos += 1
        end
        val_end = pos

        # Trim trailing whitespace from value
        while val_end > val_start && whitespace?(@css.getbyte(val_end - 1))
          val_end -= 1
        end

        value = byteslice_encoded(val_start, val_end - val_start)

        # Check for !important flag
        important = false
        if value.end_with?('!important')
          important = true
          # NOTE: Using rstrip here instead of manual byte loop since !important is rare (not hot path)
          value = value[0, value.length - 10].rstrip # Remove '!important' and trailing whitespace
        end

        pos += 1 if pos < end_pos && @css.getbyte(pos) == BYTE_SEMICOLON

        # Create declaration
        declarations << Declaration.new(property, value, important) if prop_end > prop_start && val_end > val_start
      end

      declarations
    end

    # Parse declaration block (inside { ... })
    # Assumes we're already past the opening '{'
    def parse_declarations
      declarations = []

      # Read until we find the closing '}'
      until eof?
        skip_ws_and_comments
        break if eof?

        # Check for closing brace
        if peek_byte == BYTE_RBRACE
          @pos += 1 # consume '}'
          break
        end

        # Parse property name (read until ':')
        property_start = @pos
        until eof?
          byte = peek_byte
          break if byte == BYTE_COLON || byte == BYTE_SEMICOLON || byte == BYTE_RBRACE

          @pos += 1
        end

        # Skip if no colon found (malformed)
        if eof? || peek_byte != BYTE_COLON
          # Try to recover by finding next ; or }
          skip_to_semicolon_or_brace
          next
        end

        property = byteslice_encoded(property_start, @pos - property_start, encoding: 'US-ASCII')
        property.strip!
        property.downcase!
        @pos += 1 # skip ':'

        skip_ws_and_comments

        # Parse value (read until ';' or '}')
        value_start = @pos
        important = false

        until eof?
          byte = peek_byte
          break if byte == BYTE_SEMICOLON || byte == BYTE_RBRACE

          @pos += 1
        end

        value = byteslice_encoded(value_start, @pos - value_start)
        value.strip!

        # Check for !important (byte-by-byte, no regexp)
        if value.bytesize > 10
          # Scan backwards to find !important
          i = value.bytesize - 1
          # Skip trailing whitespace
          while i >= 0
            b = value.getbyte(i)
            break unless b == BYTE_SPACE || b == BYTE_TAB

            i -= 1
          end

          # Check for 'important' (9 chars)
          if i >= 8 && value[(i - 8), 9] == 'important'
            i -= 9
            # Skip whitespace before 'important'
            while i >= 0
              b = value.getbyte(i)
              break unless b == BYTE_SPACE || b == BYTE_TAB

              i -= 1
            end
            # Check for '!'
            if i >= 0 && value.getbyte(i) == BYTE_BANG
              important = true
              # Remove everything from '!' onwards (use byteslice and strip in-place)
              value = value.byteslice(0, i)
              value.strip!
            end
          end
        end

        # Skip semicolon if present
        @pos += 1 if peek_byte == BYTE_SEMICOLON

        # Create Declaration struct
        declarations << Declaration.new(property, value, important)
      end

      declarations
    end

    # Parse at-rule (@media, @supports, @charset, @keyframes, @font-face, etc)
    # Translated from C: see ext/cataract/css_parser.c lines 962-1128
    def parse_at_rule
      at_rule_start = @pos # Points to '@'
      @pos += 1 # skip '@'

      # Find end of at-rule name (stop at whitespace or opening brace)
      name_start = @pos
      until eof?
        byte = peek_byte
        break if whitespace?(byte) || byte == BYTE_LBRACE

        @pos += 1
      end

      at_rule_name = byteslice_encoded(name_start, @pos - name_start)

      # Handle @charset specially - it's just @charset "value";
      if at_rule_name == 'charset'
        skip_ws_and_comments
        # Read until semicolon
        value_start = @pos
        while !eof? && peek_byte != BYTE_SEMICOLON
          @pos += 1
        end

        charset_value = byteslice_encoded(value_start, @pos - value_start)
        charset_value.strip!
        # Remove quotes (byte-by-byte)
        result = String.new
        i = 0
        len = charset_value.bytesize
        while i < len
          byte = charset_value.getbyte(i)
          result << charset_value[i] unless byte == BYTE_DQUOTE || byte == BYTE_SQUOTE
          i += 1
        end
        @charset = result

        @pos += 1 if peek_byte == BYTE_SEMICOLON # consume semicolon
        return
      end

      # Handle @import - must come before rules (except @charset)
      if at_rule_name == 'import'
        # If we've already seen a rule, this @import is invalid
        if @rules.size > 0
          warn 'CSS @import ignored: @import must appear before all rules (found import after rules)'
          # Skip to semicolon
          while !eof? && peek_byte != BYTE_SEMICOLON
            @pos += 1
          end
          @pos += 1 if peek_byte == BYTE_SEMICOLON
          return
        end

        parse_import_statement
        return
      end

      # Handle conditional group at-rules: @supports, @layer, @container, @scope
      # These behave like @media but don't affect media context
      if AT_RULE_TYPES.include?(at_rule_name)
        skip_ws_and_comments

        # Skip to opening brace
        while !eof? && peek_byte != BYTE_LBRACE
          @pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Check depth before recursing
        if @depth + 1 > MAX_PARSE_DEPTH
          raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
        end

        # Recursively parse block content (preserve parent media context)
        nested_parser = Parser.new(
          byteslice_encoded(block_start, block_end - block_start),
          parser_options: @parser_options,
          parent_media_sym: @parent_media_sym,
          depth: @depth + 1
        )

        nested_result = nested_parser.parse

        # Merge nested selector_lists with offsetted IDs
        list_id_offset = @_next_selector_list_id
        if nested_result[:_selector_lists] && !nested_result[:_selector_lists].empty?
          nested_result[:_selector_lists].each do |list_id, rule_ids|
            new_list_id = list_id + list_id_offset
            offsetted_rule_ids = rule_ids.map { |rid| rid + @rule_id_counter }
            @_selector_lists[new_list_id] = offsetted_rule_ids
          end
          @_next_selector_list_id = list_id_offset + nested_result[:_selector_lists].size
        end

        # Merge nested media_index into ours
        nested_result[:_media_index].each do |media, rule_ids|
          @_media_index[media] ||= []
          # Use each + << instead of concat + map (1.20x faster for small arrays)
          rule_ids.each { |rid| @_media_index[media] << (@rule_id_counter + rid) }
        end

        # Add nested rules to main rules array
        nested_result[:rules].each do |rule|
          rule.id = @rule_id_counter
          # Update selector_list_id if applicable
          if rule.is_a?(Rule) && rule.selector_list_id
            rule.selector_list_id += list_id_offset
          end
          @rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @pos = block_end
        @pos += 1 if @pos < @len && @css.getbyte(@pos) == BYTE_RBRACE

        return
      end

      # Handle @media specially - parse content and track in media_index
      if at_rule_name == 'media'
        skip_ws_and_comments

        # Find media query (up to opening brace)
        mq_start = @pos
        while !eof? && peek_byte != BYTE_LBRACE
          @pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        mq_end = @pos
        # Trim trailing whitespace
        while mq_end > mq_start && whitespace?(@css.getbyte(mq_end - 1))
          mq_end -= 1
        end

        child_media_string = byteslice_encoded(mq_start, mq_end - mq_start)
        # Keep media query exactly as written - parentheses are required per CSS spec
        child_media_string.strip!
        child_media_sym = child_media_string.to_sym

        # Combine with parent media context
        combined_media_sym = combine_media_queries(@parent_media_sym, child_media_sym)

        # Check media query limit
        unless @_media_index.key?(combined_media_sym)
          @media_query_count += 1
          if @media_query_count > MAX_MEDIA_QUERIES
            raise SizeError, "Too many media queries: exceeded maximum of #{MAX_MEDIA_QUERIES}"
          end
        end

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Check depth before recursing
        if @depth + 1 > MAX_PARSE_DEPTH
          raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
        end

        # Parse the content with the combined media context
        nested_parser = Parser.new(
          byteslice_encoded(block_start, block_end - block_start),
          parser_options: @parser_options,
          parent_media_sym: combined_media_sym,
          depth: @depth + 1
        )

        nested_result = nested_parser.parse

        # Merge nested selector_lists with offsetted IDs
        list_id_offset = @_next_selector_list_id
        if nested_result[:_selector_lists] && !nested_result[:_selector_lists].empty?
          nested_result[:_selector_lists].each do |list_id, rule_ids|
            new_list_id = list_id + list_id_offset
            offsetted_rule_ids = rule_ids.map { |rid| rid + @rule_id_counter }
            @_selector_lists[new_list_id] = offsetted_rule_ids
          end
          @_next_selector_list_id = list_id_offset + nested_result[:_selector_lists].size
        end

        # Merge nested media_index into ours (for nested @media)
        nested_result[:_media_index].each do |media, rule_ids|
          @_media_index[media] ||= []
          # Use each + << instead of concat + map (1.20x faster for small arrays)
          rule_ids.each { |rid| @_media_index[media] << (@rule_id_counter + rid) }
        end

        # Add nested rules to main rules array and update media_index
        nested_result[:rules].each do |rule|
          rule.id = @rule_id_counter
          # Update selector_list_id if applicable
          if rule.is_a?(Rule) && rule.selector_list_id
            rule.selector_list_id += list_id_offset
          end

          # Extract media types and add to each first (if different from full query)
          # We add these BEFORE the full query so that when iterating the media_index hash,
          # the full query comes last and takes precedence during serialization
          media_types = Cataract.parse_media_types(combined_media_sym)
          media_types.each do |media_type|
            # Only add if different from combined_media_sym to avoid duplication
            if media_type != combined_media_sym
              @_media_index[media_type] ||= []
              @_media_index[media_type] << @rule_id_counter
            end
          end

          # Add to full query symbol (after media types for insertion order)
          @_media_index[combined_media_sym] ||= []
          @_media_index[combined_media_sym] << @rule_id_counter

          @rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @pos = block_end
        @pos += 1 if @pos < @len && @css.getbyte(@pos) == BYTE_RBRACE

        return
      end

      # Check for @keyframes (contains <rule-list>)
      is_keyframes = at_rule_name == 'keyframes' ||
                     at_rule_name == '-webkit-keyframes' ||
                     at_rule_name == '-moz-keyframes'

      if is_keyframes
        # Build full selector string: "@keyframes fade"
        selector_start = at_rule_start # Points to '@'

        # Skip to opening brace
        while !eof? && peek_byte != BYTE_LBRACE
          @pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        selector_end = @pos
        # Trim trailing whitespace
        while selector_end > selector_start && whitespace?(@css.getbyte(selector_end - 1))
          selector_end -= 1
        end
        selector = byteslice_encoded(selector_start, selector_end - selector_start)

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Check depth before recursing
        if @depth + 1 > MAX_PARSE_DEPTH
          raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
        end

        # Parse keyframe blocks as rules (0%/from/to etc)
        # Create a nested parser context
        nested_parser = Parser.new(
          byteslice_encoded(block_start, block_end - block_start),
          parser_options: @parser_options,
          depth: @depth + 1
        )
        nested_result = nested_parser.parse
        content = nested_result[:rules]

        # Move position past the closing brace
        @pos = block_end
        # The closing brace should be at block_end
        @pos += 1 if @pos < @len && @css.getbyte(@pos) == BYTE_RBRACE

        # Get rule ID and increment
        rule_id = @rule_id_counter
        @rule_id_counter += 1

        # Create AtRule with nested rules
        at_rule = AtRule.new(rule_id, selector, content, nil)
        @rules << at_rule

        return
      end

      # Check for @font-face (contains <declaration-list>)
      if at_rule_name == 'font-face'
        # Build selector string: "@font-face"
        selector_start = at_rule_start # Points to '@'

        # Skip to opening brace
        while !eof? && peek_byte != BYTE_LBRACE
          @pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        selector_end = @pos
        # Trim trailing whitespace
        while selector_end > selector_start && whitespace?(@css.getbyte(selector_end - 1))
          selector_end -= 1
        end
        selector = byteslice_encoded(selector_start, selector_end - selector_start)

        @pos += 1 # skip '{'

        # Find matching closing brace
        decl_start = @pos
        decl_end = find_matching_brace(@pos)

        # Parse declarations
        content = parse_declarations_block(decl_start, decl_end)

        # Move position past the closing brace
        @pos = decl_end
        # The closing brace should be at decl_end
        @pos += 1 if @pos < @len && @css.getbyte(@pos) == BYTE_RBRACE

        # Get rule ID and increment
        rule_id = @rule_id_counter
        @rule_id_counter += 1

        # Create AtRule with declarations
        at_rule = AtRule.new(rule_id, selector, content, nil)
        @rules << at_rule

        return
      end

      # Unknown at-rule (@property, @page, @counter-style, etc.)
      # Treat as a regular selector-based rule with declarations
      selector_start = at_rule_start # Points to '@'

      # Skip to opening brace
      until eof? || peek_byte == BYTE_LBRACE # Save a not_opt instruction: while !eof? && peek_byte != BYTE_LBRACE
        @pos += 1
      end

      return if eof? || peek_byte != BYTE_LBRACE

      selector_end = @pos
      # Trim trailing whitespace
      while selector_end > selector_start && whitespace?(@css.getbyte(selector_end - 1))
        selector_end -= 1
      end
      selector = byteslice_encoded(selector_start, selector_end - selector_start)

      @pos += 1 # skip '{'

      # Parse declarations
      declarations = parse_declarations

      # Create Rule with declarations
      rule = Rule.new(
        @rule_id_counter,    # id
        selector,            # selector (e.g., "@property --main-color")
        declarations,        # declarations
        nil,                 # specificity
        nil,                 # parent_rule_id
        nil                  # nesting_style
      )

      @rules << rule
      @rule_id_counter += 1
    end

    # Check if block contains nested selectors vs just declarations
    # Translated from C: see ext/cataract/css_parser.c has_nested_selectors
    def has_nested_selectors?(start_pos, end_pos)
      pos = start_pos

      while pos < end_pos
        # Skip whitespace
        while pos < end_pos && whitespace?(@css.getbyte(pos))
          pos += 1
        end
        break if pos >= end_pos

        # Skip comments
        if pos + 1 < end_pos && @css.getbyte(pos) == BYTE_SLASH && @css.getbyte(pos + 1) == BYTE_STAR
          pos += 2
          while pos + 1 < end_pos
            if @css.getbyte(pos) == BYTE_STAR && @css.getbyte(pos + 1) == BYTE_SLASH
              pos += 2
              break
            end
            pos += 1
          end
          next
        end

        # Check for nested selector indicators
        byte = @css.getbyte(pos)
        if byte == BYTE_AMPERSAND || byte == BYTE_DOT || byte == BYTE_HASH ||
           byte == BYTE_LBRACKET || byte == BYTE_COLON || byte == BYTE_ASTERISK ||
           byte == BYTE_GT || byte == BYTE_PLUS || byte == BYTE_TILDE
          # Look ahead - if followed by {, it's likely a nested selector
          lookahead = pos + 1
          while lookahead < end_pos && @css.getbyte(lookahead) != BYTE_LBRACE &&
                @css.getbyte(lookahead) != BYTE_SEMICOLON && @css.getbyte(lookahead) != BYTE_NEWLINE
            lookahead += 1
          end
          return true if lookahead < end_pos && @css.getbyte(lookahead) == BYTE_LBRACE
        end

        # Check for @media, @supports, etc nested inside
        return true if byte == BYTE_AT

        # Skip to next line or semicolon
        while pos < end_pos && @css.getbyte(pos) != BYTE_SEMICOLON && @css.getbyte(pos) != BYTE_NEWLINE
          pos += 1
        end
        pos += 1 if pos < end_pos
      end

      false
    end

    # Resolve nested selector against parent
    # Translated from C: see ext/cataract/css_parser.c resolve_nested_selector
    # Examples:
    #   resolve_nested_selector(".parent", "& .child")  => [".parent .child", 1]  (explicit)
    #   resolve_nested_selector(".parent", "&:hover")   => [".parent:hover", 1]   (explicit)
    #   resolve_nested_selector(".parent", "&.active")  => [".parent.active", 1]  (explicit)
    #   resolve_nested_selector(".parent", ".child")    => [".parent .child", 0]  (implicit)
    #   resolve_nested_selector(".parent", "> .child")  => [".parent > .child", 0] (implicit combinator)
    #
    # Returns: [resolved_selector, nesting_style]
    #   nesting_style: 0 = NESTING_STYLE_IMPLICIT, 1 = NESTING_STYLE_EXPLICIT
    def resolve_nested_selector(parent_selector, nested_selector)
      # Check if nested selector contains & (byte-level search)
      len = nested_selector.bytesize
      has_ampersand = false
      i = 0
      while i < len
        if nested_selector.getbyte(i) == BYTE_AMPERSAND
          has_ampersand = true
          break
        end
        i += 1
      end

      if has_ampersand
        # Explicit nesting - replace & with parent
        nesting_style = NESTING_STYLE_EXPLICIT

        # Trim leading whitespace to check for combinator
        # NOTE: We use a manual byte-level loop instead of lstrip for performance.
        # Ruby's lstrip handles all Unicode whitespace and encoding checks, but CSS
        # selectors only use ASCII whitespace (space, tab, newline, CR). Our loop
        # checks only these 4 bytes, which benchmarks 1.89x faster than lstrip.
        start_pos = 0
        while start_pos < len
          byte = nested_selector.getbyte(start_pos)
          break unless byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR

          start_pos += 1
        end

        # Check if selector starts with a combinator (relative selector)
        starts_with_combinator = false
        if start_pos < len
          first_byte = nested_selector.getbyte(start_pos)
          starts_with_combinator = (first_byte == BYTE_PLUS || first_byte == BYTE_GT || first_byte == BYTE_TILDE)
        end

        # Build result by replacing & with parent
        result = String.new
        if starts_with_combinator
          # Prepend parent first with space for relative selectors
          # Example: "+ .bar + &" => ".foo + .bar + .foo"
          result << parent_selector
          result << ' '
        end

        # Replace all & with parent selector (byte-level iteration)
        i = 0
        while i < len
          byte = nested_selector.getbyte(i)
          result << if byte == BYTE_AMPERSAND
                      parent_selector
                    else
                      byte.chr
                    end
          i += 1
        end

        [result, nesting_style]
      else
        # Implicit nesting - prepend parent with appropriate spacing
        nesting_style = NESTING_STYLE_IMPLICIT

        # Trim leading whitespace from nested selector (byte-level)
        # See comment above for why we don't use lstrip
        start_pos = 0
        while start_pos < len
          byte = nested_selector.getbyte(start_pos)
          break unless byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR

          start_pos += 1
        end

        result = String.new
        result << parent_selector
        result << ' '
        result << nested_selector.byteslice(start_pos, nested_selector.bytesize - start_pos)

        [result, nesting_style]
      end
    end

    # Combine parent and child media queries
    # Translated from C: see ext/cataract/css_parser.c combine_media_queries
    # Examples:
    #   parent="screen", child="min-width: 500px" => "screen and (min-width: 500px)"
    #   parent=nil, child="print" => "print"
    def combine_media_queries(parent, child)
      return child if parent.nil?
      return parent if child.nil?

      # Combine: "parent and child"
      parent_str = parent.to_s
      child_str = child.to_s

      combined = "#{parent_str} and "

      # If child is a condition (contains ':'), wrap it in parentheses
      combined += if child_str.include?(':')
                    # Add parens if not already present
                    len = child_str.bytesize
                    if len > 1 && child_str.getbyte(0) == BYTE_LPAREN && child_str.getbyte(len - 1) == BYTE_RPAREN
                      child_str
                    else
                      "(#{child_str})"
                    end
                  else
                    child_str
                  end

      combined.to_sym
    end

    # Skip to next semicolon or closing brace (error recovery)
    def skip_to_semicolon_or_brace
      until eof? || peek_byte == BYTE_SEMICOLON || peek_byte == BYTE_RBRACE # Flip to save a not_opt instruction: while !eof? && peek_byte != BYTE_SEMICOLON && peek_byte != BYTE_RBRACE
        @pos += 1
      end

      @pos += 1 if peek_byte == BYTE_SEMICOLON # consume semicolon
    end

    # Parse an @import statement
    # @import "url" [media-query];
    # @import url("url") [media-query];
    def parse_import_statement
      skip_ws_and_comments

      # Check for optional url(
      has_url_function = false
      if @pos + 4 <= @len && match_ascii_ci?(@css, @pos, 'url(')
        has_url_function = true
        @pos += 4
        skip_ws_and_comments
      end

      # Find opening quote
      byte = peek_byte
      if eof? || (byte != BYTE_DQUOTE && byte != BYTE_SQUOTE)
        # Invalid @import, skip to semicolon
        while !eof? && peek_byte != BYTE_SEMICOLON
          @pos += 1
        end
        @pos += 1 unless eof?
        return
      end

      quote_char = byte
      @pos += 1 # Skip opening quote

      url_start = @pos

      # Find closing quote (handle escaped quotes)
      while !eof? && peek_byte != quote_char
        @pos += if peek_byte == BYTE_BACKSLASH && @pos + 1 < @len
                  2 # Skip escaped character
                else
                  1
                end
      end

      if eof?
        # Unterminated string
        return
      end

      url = byteslice_encoded(url_start, @pos - url_start)
      @pos += 1 # Skip closing quote

      # Skip closing paren if we had url(
      if has_url_function
        skip_ws_and_comments
        @pos += 1 if peek_byte == BYTE_RPAREN
      end

      skip_ws_and_comments

      # Check for optional media query (everything until semicolon)
      media = nil
      if !eof? && peek_byte != BYTE_SEMICOLON
        media_start = @pos

        # Find semicolon
        while !eof? && peek_byte != BYTE_SEMICOLON
          @pos += 1
        end

        media_end = @pos

        # Trim trailing whitespace from media query
        while media_end > media_start && whitespace?(@css.getbyte(media_end - 1))
          media_end -= 1
        end

        if media_end > media_start
          media = byteslice_encoded(media_start, media_end - media_start).to_sym
        end
      end

      # Skip semicolon
      @pos += 1 if peek_byte == BYTE_SEMICOLON

      # Create ImportStatement (resolved: false by default)
      import_stmt = ImportStatement.new(@rule_id_counter, url, media, false)
      @imports << import_stmt
      @rule_id_counter += 1
    end

    # Skip @import statements at the beginning of CSS (DEPRECATED - now parsed)
    # Per CSS spec, @import must come before all rules (except @charset)
    def skip_imports
      until eof?
        # Skip whitespace
        while !eof? && whitespace?(peek_byte)
          @pos += 1
        end
        break if eof?

        # Skip comments
        if @pos + 1 < @len && @css.getbyte(@pos) == BYTE_SLASH && @css.getbyte(@pos + 1) == BYTE_STAR
          @pos += 2
          while @pos + 1 < @len
            if @css.getbyte(@pos) == BYTE_STAR && @css.getbyte(@pos + 1) == BYTE_SLASH
              @pos += 2
              break
            end
            @pos += 1
          end
          next
        end

        # Check for @import (case-insensitive byte comparison)
        if @pos + 7 <= @len && @css.getbyte(@pos) == BYTE_AT && match_ascii_ci?(@css, @pos + 1, 'import')
          # Check that it's followed by whitespace or quote
          if @pos + 7 >= @len || whitespace?(@css.getbyte(@pos + 7)) || @css.getbyte(@pos + 7) == BYTE_SQUOTE || @css.getbyte(@pos + 7) == BYTE_DQUOTE
            # Skip to semicolon
            while !eof? && peek_byte != BYTE_SEMICOLON
              @pos += 1
            end
            @pos += 1 unless eof? # Skip semicolon
            next
          end
        end

        # Hit non-@import content, stop skipping
        break
      end
    end

    # Parse a block of declarations given start/end positions
    # Used for @font-face and other at-rules
    # Translated from C: see ext/cataract/css_parser.c parse_declarations
    def parse_declarations_block(start_pos, end_pos)
      declarations = []
      pos = start_pos

      while pos < end_pos
        # Skip whitespace
        while pos < end_pos && whitespace?(@css.getbyte(pos))
          pos += 1
        end
        break if pos >= end_pos

        # Parse property name (read until ':')
        prop_start = pos
        while pos < end_pos && @css.getbyte(pos) != BYTE_COLON && @css.getbyte(pos) != BYTE_SEMICOLON && @css.getbyte(pos) != BYTE_RBRACE
          pos += 1
        end

        # Skip if no colon found (malformed)
        if pos >= end_pos || @css.getbyte(pos) != BYTE_COLON
          # Try to recover by finding next semicolon
          while pos < end_pos && @css.getbyte(pos) != BYTE_SEMICOLON
            pos += 1
          end
          pos += 1 if pos < end_pos && @css.getbyte(pos) == BYTE_SEMICOLON
          next
        end

        prop_end = pos
        # Trim trailing whitespace from property
        while prop_end > prop_start && whitespace?(@css.getbyte(prop_end - 1))
          prop_end -= 1
        end

        property = byteslice_encoded(prop_start, prop_end - prop_start, encoding: 'US-ASCII')
        property.downcase!

        pos += 1 # Skip ':'

        # Skip leading whitespace in value
        while pos < end_pos && whitespace?(@css.getbyte(pos))
          pos += 1
        end

        # Parse value (read until ';' or '}')
        val_start = pos
        while pos < end_pos && @css.getbyte(pos) != BYTE_SEMICOLON && @css.getbyte(pos) != BYTE_RBRACE
          pos += 1
        end
        val_end = pos

        # Trim trailing whitespace from value
        while val_end > val_start && whitespace?(@css.getbyte(val_end - 1))
          val_end -= 1
        end

        value = byteslice_encoded(val_start, val_end - val_start)

        pos += 1 if pos < end_pos && @css.getbyte(pos) == BYTE_SEMICOLON

        # Create Declaration struct (at-rules don't use !important)
        declarations << Declaration.new(property, value, false)
      end

      declarations
    end
  end
end
