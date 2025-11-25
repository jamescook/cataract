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

    # Extract substring and force specified encoding
    # Per CSS spec, charset detection happens at byte-stream level before parsing.
    # All parsing operations treat content as UTF-8 (spec requires fallback to UTF-8).
    # This prevents ArgumentError on broken/invalid encodings when calling string methods.
    # Optional encoding parameter (default: 'UTF-8', use 'US-ASCII' for property names)
    def byteslice_encoded(start, length, encoding: 'UTF-8')
      @_css.byteslice(start, length).force_encoding(encoding)
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

    def initialize(css_string, parser_options: {}, parent_media_sym: nil, parent_media_query_id: nil, depth: 0)
      # Type validation
      raise TypeError, "css_string must be a String, got #{css_string.class}" unless css_string.is_a?(String)

      # Private: Internal parsing state
      @_css = css_string.dup.freeze
      @_pos = 0
      @_len = @_css.bytesize
      @_parent_media_sym = parent_media_sym
      @_parent_media_query_id = parent_media_query_id
      @_depth = depth # Current recursion depth (passed from parent parser)

      # Private: Parser options with defaults
      @_parser_options = {
        selector_lists: true,
        base_uri: nil,
        absolute_paths: false,
        uri_resolver: nil,
        raise_parse_errors: false
      }.merge(parser_options)

      # Private: Extract options to ivars to avoid repeated hash lookups in hot path
      @_selector_lists_enabled = @_parser_options[:selector_lists]
      @_base_uri = @_parser_options[:base_uri]
      @_absolute_paths = @_parser_options[:absolute_paths]
      @_uri_resolver = @_parser_options[:uri_resolver] || Cataract::DEFAULT_URI_RESOLVER

      # Parse error handling options - extract to ivars for hot path performance
      @_raise_parse_errors = @_parser_options[:raise_parse_errors]
      if @_raise_parse_errors.is_a?(Hash)
        # Granular control - default all to false (opt-in)
        @_check_empty_values = @_raise_parse_errors[:empty_values] || false
        @_check_malformed_declarations = @_raise_parse_errors[:malformed_declarations] || false
        @_check_invalid_selectors = @_raise_parse_errors[:invalid_selectors] || false
        @_check_invalid_selector_syntax = @_raise_parse_errors[:invalid_selector_syntax] || false
        @_check_malformed_at_rules = @_raise_parse_errors[:malformed_at_rules] || false
        @_check_unclosed_blocks = @_raise_parse_errors[:unclosed_blocks] || false
      elsif @_raise_parse_errors == true
        # Enable all error checks
        @_check_empty_values = true
        @_check_malformed_declarations = true
        @_check_invalid_selectors = true
        @_check_invalid_selector_syntax = true
        @_check_malformed_at_rules = true
        @_check_unclosed_blocks = true
      else
        # Disabled
        @_check_empty_values = false
        @_check_malformed_declarations = false
        @_check_invalid_selectors = false
        @_check_invalid_selector_syntax = false
        @_check_malformed_at_rules = false
        @_check_unclosed_blocks = false
      end

      # Private: Internal counters
      @_media_query_id_counter = 0   # Next MediaQuery ID (0-indexed)
      @_next_selector_list_id = 0    # Counter for selector list IDs
      @_next_media_query_list_id = 0 # Counter for media query list IDs
      @_rule_id_counter = 0          # Next rule ID (0-indexed)
      @_media_query_count = 0        # Safety limit

      # Public: Parser results (returned in parse result hash)
      @rules = []                    # Flat array of Rule structs
      @media_queries = []            # Array of MediaQuery objects
      @media_index = {}              # Symbol => Array of rule IDs (for backwards compat/caching)
      @imports = []                  # Array of ImportStatement structs
      @charset = nil                 # @charset declaration

      # Semi-private: Internal state exposed with _ prefix in result
      @_selector_lists = {}          # Hash: list_id => Array of rule IDs
      @_media_query_lists = {}       # Hash: list_id => Array of MediaQuery IDs (for "screen, print")
      @_has_nesting = false          # Set to true if any nested rules found
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
        decl_start = @_pos # Should be right after the {
        decl_end = find_matching_brace(decl_start)

        # Check if block has nested selectors
        if has_nested_selectors?(decl_start, decl_end)
          # NESTED PATH: Parse mixed declarations + nested rules
          # Split comma-separated selectors and parse each one
          selectors = selector.split(',')

          selectors.each do |individual_selector|
            individual_selector.strip!

            # Check for empty selector in comma-separated list
            if @_check_invalid_selector_syntax && individual_selector.empty? && selectors.size > 1
              raise ParseError.new('Invalid selector syntax: empty selector in comma-separated list',
                                   css: @_css, pos: decl_start, type: :invalid_selector_syntax)
            end

            next if individual_selector.empty?

            # Get rule ID for this selector
            current_rule_id = @_rule_id_counter
            @_rule_id_counter += 1

            # Reserve parent's position in rules array (ensures parent comes before nested)
            parent_position = @rules.length
            @rules << nil # Placeholder

            # Parse mixed block (declarations + nested selectors)
            @_depth += 1
            parent_declarations = parse_mixed_block(decl_start, decl_end,
                                                    individual_selector, current_rule_id, @_parent_media_sym, @_parent_media_query_id)
            @_depth -= 1

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
          end

          # Move position past the closing brace
          @_pos = decl_end
          @_pos += 1 if @_pos < @_len && @_css.getbyte(@_pos) == BYTE_RBRACE
        else
          # NON-NESTED PATH: Parse declarations only
          @_pos = decl_start # Reset to start of block
          declarations = parse_declarations

          # Split comma-separated selectors into individual rules
          selectors = selector.split(',')

          # Determine if we should track this as a selector list
          # Check boolean first to potentially avoid size() call via short-circuit evaluation
          list_id = nil
          if @_selector_lists_enabled && selectors.size > 1
            list_id = @_next_selector_list_id
            @_next_selector_list_id += 1
            @_selector_lists[list_id] = []
          end

          selectors.each do |individual_selector|
            individual_selector.strip!

            # Check for empty selector in comma-separated list
            if @_check_invalid_selector_syntax && individual_selector.empty? && selectors.size > 1
              raise ParseError.new('Invalid selector syntax: empty selector in comma-separated list',
                                   css: @_css, pos: decl_start, type: :invalid_selector_syntax)
            end

            next if individual_selector.empty?

            rule_id = @_rule_id_counter

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
            @_rule_id_counter += 1

            # Track in selector list if applicable
            @_selector_lists[list_id] << rule_id if list_id
          end
        end
      end

      {
        rules: @rules,
        _media_index: @media_index,
        media_queries: @media_queries,
        _selector_lists: @_selector_lists,
        _media_query_lists: @_media_query_lists,
        imports: @imports,
        charset: @charset,
        _has_nesting: @_has_nesting
      }
    end

    private

    # Check if we're at end of input
    def eof?
      @_pos >= @_len
    end

    # Peek current byte without advancing
    # @return [Integer, nil] Byte value or nil if EOF
    def peek_byte
      return nil if eof?

      @_css.getbyte(@_pos)
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
      @_pos += 1 while !eof? && whitespace?(peek_byte)
    end

    def skip_comment # rubocop:disable Naming/PredicateMethod
      return false unless peek_byte == BYTE_SLASH && @_css.getbyte(@_pos + 1) == BYTE_STAR

      @_pos += 2 # Skip /*
      while @_pos + 1 < @_len
        if @_css.getbyte(@_pos) == BYTE_STAR && @_css.getbyte(@_pos + 1) == BYTE_SLASH
          @_pos += 2 # Skip */
          return true
        end
        @_pos += 1
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
        old_pos = @_pos
        skip_whitespace
        skip_comment
      end until @_pos == old_pos # No progress made # rubocop:disable Lint/Loop
    end

    # Check if a selector contains only valid CSS selector characters and sequences
    # Returns true if valid, false if invalid
    # Valid characters: a-z A-Z 0-9 - _ . # [ ] : * > + ~ ( ) ' " = ^ $ | \ & % / whitespace
    def valid_selector_syntax?(selector_text)
      i = 0
      len = selector_text.bytesize

      while i < len
        byte = selector_text.getbyte(i)

        # Check for invalid character sequences
        if i + 1 < len
          next_byte = selector_text.getbyte(i + 1)
          # Double dot (..) is invalid
          return false if byte == BYTE_DOT && next_byte == BYTE_DOT
          # Double hash (##) is invalid
          return false if byte == BYTE_HASH && next_byte == BYTE_HASH
        end

        # Alphanumeric
        if (byte >= BYTE_LOWER_A && byte <= BYTE_LOWER_Z) || (byte >= BYTE_UPPER_A && byte <= BYTE_UPPER_Z) || (byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9)
          i += 1
          next
        end

        # Whitespace
        if byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR
          i += 1
          next
        end

        # Valid CSS selector special characters
        case byte
        when BYTE_HYPHEN, BYTE_UNDERSCORE, BYTE_DOT, BYTE_HASH, BYTE_LBRACKET, BYTE_RBRACKET,
             BYTE_COLON, BYTE_ASTERISK, BYTE_GT, BYTE_PLUS, BYTE_TILDE, BYTE_LPAREN, BYTE_RPAREN,
             BYTE_SQUOTE, BYTE_DQUOTE, BYTE_EQUALS, BYTE_CARET, BYTE_DOLLAR,
             BYTE_PIPE, BYTE_BACKSLASH, BYTE_AMPERSAND, BYTE_PERCENT, BYTE_SLASH, BYTE_BANG,
             BYTE_COMMA
          i += 1
        else
          # Invalid character found
          return false
        end
      end

      true
    end

    # Parse a single CSS declaration (property: value)
    #
    # Performance-critical helper that parses one declaration.
    # Shared by parse_mixed_block, parse_declarations, and parse_declarations_block.
    #
    # @param pos [Integer] Current position in CSS string
    # @param end_pos [Integer] End position (boundary for parsing)
    # @param parse_important [Boolean] Whether to parse !important flag (false for at-rules)
    # @return [Array(Declaration|nil, Integer)] Tuple of [declaration, new_position]
    def parse_single_declaration(pos, end_pos, parse_important)
      # Parse property name (scan until ':')
      prop_start = pos
      while pos < end_pos && @_css.getbyte(pos) != BYTE_COLON &&
            @_css.getbyte(pos) != BYTE_SEMICOLON && @_css.getbyte(pos) != BYTE_RBRACE
        pos += 1
      end

      # Skip if malformed (no colon found)
      if pos >= end_pos || @_css.getbyte(pos) != BYTE_COLON
        # Error recovery: skip to next semicolon
        while pos < end_pos && @_css.getbyte(pos) != BYTE_SEMICOLON
          pos += 1
        end
        pos += 1 if pos < end_pos && @_css.getbyte(pos) == BYTE_SEMICOLON
        return [nil, pos]
      end

      # Trim trailing whitespace from property
      prop_end = pos
      while prop_end > prop_start && whitespace?(@_css.getbyte(prop_end - 1))
        prop_end -= 1
      end

      # Extract and normalize property name
      property = byteslice_encoded(prop_start, prop_end - prop_start)
      # Custom properties (--foo) are case-sensitive and can contain Unicode
      # Regular properties are ASCII-only and case-insensitive
      unless property.bytesize >= 2 && property.getbyte(0) == BYTE_HYPHEN && property.getbyte(1) == BYTE_HYPHEN
        property.force_encoding('US-ASCII')
        property.downcase!
      end

      pos += 1 # Skip ':'

      # Skip leading whitespace in value
      while pos < end_pos && whitespace?(@_css.getbyte(pos))
        pos += 1
      end

      # Parse value (scan until ';' or '}')
      val_start = pos
      while pos < end_pos && @_css.getbyte(pos) != BYTE_SEMICOLON && @_css.getbyte(pos) != BYTE_RBRACE
        pos += 1
      end
      val_end = pos

      # Trim trailing whitespace from value
      while val_end > val_start && whitespace?(@_css.getbyte(val_end - 1))
        val_end -= 1
      end

      value = byteslice_encoded(val_start, val_end - val_start)

      # Parse !important flag if requested
      important = false
      if parse_important && value.end_with?('!important')
        important = true
        # Remove '!important' and trailing whitespace
        value = value[0, value.length - 10].rstrip
      end

      # Skip semicolon if present
      pos += 1 if pos < end_pos && @_css.getbyte(pos) == BYTE_SEMICOLON

      # Return nil if empty declaration
      return [nil, pos] if prop_end <= prop_start || val_end <= val_start

      # Convert relative URLs to absolute if enabled
      value = convert_urls_in_value(value)

      [Declaration.new(property, value, important), pos]
    end

    # Find matching closing brace
    #
    # Performance notes (benchmarked on bootstrap.css with 2,400 braces):
    # - Using `return` instead of `break` avoids catch table overhead (~2% faster)
    # - Checking RBRACE before LBRACE is faster because closing braces are
    #   encountered more frequently when searching forward from an opening brace
    # - Combined optimizations: baseline 666ms → optimized 652ms (2% improvement)
    #
    # Translated from C: see ext/cataract/css_parser.c find_matching_brace
    def find_matching_brace(start_pos)
      depth = 1
      pos = start_pos

      while pos < @_len
        byte = @_css.getbyte(pos)
        if byte == BYTE_RBRACE
          depth -= 1
          return pos if depth == 0
        elsif byte == BYTE_LBRACE
          depth += 1
        end
        pos += 1
      end

      # Reached EOF without finding matching closing brace
      if @_check_unclosed_blocks && depth > 0
        raise ParseError.new('Unclosed block: missing closing brace',
                             css: @_css, pos: start_pos - 1, type: :unclosed_block)
      end

      pos
    end

    # Parse selector (read until '{')
    def parse_selector
      start_pos = @_pos

      # Read until we find '{'
      until eof? || peek_byte == BYTE_LBRACE # Flip to save a 'opt_not' instruction: while !eof? && peek_byte != BYTE_LBRACE
        @_pos += 1
      end

      # If we hit EOF without finding '{', return nil
      return nil if eof?

      # Extract selector text
      selector_text = byteslice_encoded(start_pos, @_pos - start_pos)

      # Skip the '{'
      @_pos += 1 if peek_byte == BYTE_LBRACE

      # Trim whitespace from selector (in-place to avoid allocation)
      selector_text.strip!

      # Validate selector (strict mode) - only if enabled to avoid overhead
      if @_check_invalid_selectors
        # Check for empty selector
        if selector_text.empty?
          raise ParseError.new('Invalid selector: empty selector',
                               css: @_css, pos: start_pos, type: :invalid_selector)
        end

        # Check if selector starts with a combinator (>, +, ~)
        first_char = selector_text.getbyte(0)
        if first_char == BYTE_GT || first_char == BYTE_PLUS || first_char == BYTE_TILDE
          raise ParseError.new("Invalid selector: selector cannot start with combinator '#{selector_text[0]}'",
                               css: @_css, pos: start_pos, type: :invalid_selector)
        end
      end

      # Check selector syntax (whitelist validation for invalid characters/sequences)
      if @_check_invalid_selector_syntax && !valid_selector_syntax?(selector_text)
        raise ParseError.new('Invalid selector syntax: selector contains invalid characters',
                             css: @_css, pos: start_pos, type: :invalid_selector_syntax)
      end

      selector_text
    end

    # Parse mixed block containing declarations AND nested selectors/at-rules
    # Translated from C: see ext/cataract/css_parser.c parse_mixed_block
    # Returns: Array of declarations (only the declarations, not nested rules)
    def parse_mixed_block(start_pos, end_pos, parent_selector, parent_rule_id, parent_media_sym, parent_media_query_id = nil)
      # Check recursion depth to prevent stack overflow
      if @_depth > MAX_PARSE_DEPTH
        raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
      end

      declarations = []
      pos = start_pos

      while pos < end_pos
        # Skip whitespace and comments
        while pos < end_pos && whitespace?(@_css.getbyte(pos))
          pos += 1
        end
        break if pos >= end_pos

        # Skip comments
        if pos + 1 < end_pos && @_css.getbyte(pos) == BYTE_SLASH && @_css.getbyte(pos + 1) == BYTE_STAR
          pos += 2
          while pos + 1 < end_pos
            if @_css.getbyte(pos) == BYTE_STAR && @_css.getbyte(pos + 1) == BYTE_SLASH
              pos += 2
              break
            end
            pos += 1
          end
          next
        end

        # Check if this is a nested @media query
        if @_css.getbyte(pos) == BYTE_AT && pos + 6 < end_pos &&
           byteslice_encoded(pos, 6) == '@media' &&
           (pos + 6 >= end_pos || whitespace?(@_css.getbyte(pos + 6)))
          # Nested @media - parse with parent selector as context
          media_start = pos + 6
          while media_start < end_pos && whitespace?(@_css.getbyte(media_start))
            media_start += 1
          end

          # Find opening brace
          media_query_end = media_start
          while media_query_end < end_pos && @_css.getbyte(media_query_end) != BYTE_LBRACE
            media_query_end += 1
          end
          break if media_query_end >= end_pos

          # Extract media query (trim trailing whitespace)
          media_query_end_trimmed = media_query_end
          while media_query_end_trimmed > media_start && whitespace?(@_css.getbyte(media_query_end_trimmed - 1))
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

          # Create MediaQuery object for this nested @media
          # If we're already in a media query context, combine with parent
          nested_media_query_id = if parent_media_query_id
                                    # Combine with parent MediaQuery
                                    parent_mq = @media_queries[parent_media_query_id]

                                    # This should never happen - parent_media_query_id should always be valid
                                    if parent_mq.nil?
                                      raise ParseError, "Invalid parent_media_query_id: #{parent_media_query_id} (not found in @media_queries)"
                                    end

                                    # Combine parent media query with child
                                    _child_type, child_conditions = parse_media_query_parts(media_query_str)
                                    combined_type, combined_conditions = combine_media_query_parts(parent_mq, child_conditions)
                                    combined_mq = Cataract::MediaQuery.new(@_media_query_id_counter, combined_type, combined_conditions)
                                    @media_queries << combined_mq
                                    combined_id = @_media_query_id_counter
                                    @_media_query_id_counter += 1
                                    combined_id
                                  else
                                    # No parent context, just use the child media query
                                    media_type, media_conditions = parse_media_query_parts(media_query_str)
                                    nested_media_query = Cataract::MediaQuery.new(@_media_query_id_counter, media_type, media_conditions)
                                    @media_queries << nested_media_query
                                    mq_id = @_media_query_id_counter
                                    @_media_query_id_counter += 1
                                    mq_id
                                  end

          # Create rule ID for this media rule
          media_rule_id = @_rule_id_counter
          @_rule_id_counter += 1

          # Reserve position in rules array (ensures sequential IDs match array indices)
          rule_position = @rules.length
          @rules << nil # Placeholder

          # Parse mixed block recursively with the nested media query ID as context
          @_depth += 1
          media_declarations = parse_mixed_block(media_block_start, media_block_end,
                                                 parent_selector, media_rule_id, combined_media_sym, nested_media_query_id)
          @_depth -= 1

          # Create rule with parent selector and declarations, associated with combined media query
          rule = Rule.new(
            media_rule_id,
            parent_selector,
            media_declarations,
            nil,  # specificity
            parent_rule_id,
            nil,  # nesting_style (nil for @media nesting)
            nil,  # selector_list_id
            nested_media_query_id # media_query_id
          )

          # Mark that we have nesting
          @_has_nesting = true unless parent_rule_id.nil?

          # Replace placeholder with actual rule
          @rules[rule_position] = rule
          next
        end

        # Check if this is a nested selector
        byte = @_css.getbyte(pos)
        if byte == BYTE_AMPERSAND || byte == BYTE_DOT || byte == BYTE_HASH ||
           byte == BYTE_LBRACKET || byte == BYTE_COLON || byte == BYTE_ASTERISK ||
           byte == BYTE_GT || byte == BYTE_PLUS || byte == BYTE_TILDE || byte == BYTE_AT
          # Find the opening brace
          nested_sel_start = pos
          while pos < end_pos && @_css.getbyte(pos) != BYTE_LBRACE
            pos += 1
          end
          break if pos >= end_pos

          nested_sel_end = pos
          # Trim trailing whitespace
          while nested_sel_end > nested_sel_start && whitespace?(@_css.getbyte(nested_sel_end - 1))
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
            rule_id = @_rule_id_counter
            @_rule_id_counter += 1

            # Reserve position in rules array (ensures sequential IDs match array indices)
            rule_position = @rules.length
            @rules << nil # Placeholder

            # Recursively parse nested block
            @_depth += 1
            nested_declarations = parse_mixed_block(nested_block_start, nested_block_end,
                                                    resolved_selector, rule_id, parent_media_sym, parent_media_query_id)
            @_depth -= 1

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

            # Replace placeholder with actual rule
            @rules[rule_position] = rule
          end

          next
        end

        # This is a declaration - parse it using shared helper
        decl, pos = parse_single_declaration(pos, end_pos, true)
        declarations << decl if decl
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
          @_pos += 1 # consume '}'
          break
        end

        # Parse property name (read until ':')
        property_start = @_pos
        until eof?
          byte = peek_byte
          break if byte == BYTE_COLON || byte == BYTE_SEMICOLON || byte == BYTE_RBRACE

          @_pos += 1
        end

        # Skip if no colon found (malformed)
        if eof? || peek_byte != BYTE_COLON
          # Check for malformed declaration (strict mode)
          if @_check_malformed_declarations
            property_text = byteslice_encoded(property_start, @_pos - property_start).strip
            if property_text.empty?
              raise ParseError.new('Malformed declaration: missing property name',
                                   css: @_css, pos: property_start, type: :malformed_declaration)
            else
              raise ParseError.new("Malformed declaration: missing colon after property '#{property_text}'",
                                   css: @_css, pos: property_start, type: :malformed_declaration)
            end
          end

          # Try to recover by finding next ; or }
          skip_to_semicolon_or_brace
          next
        end

        # Extract property name - use UTF-8 encoding to support custom properties with Unicode
        property = byteslice_encoded(property_start, @_pos - property_start)
        property.strip!
        # Custom properties (--foo) are case-sensitive and can contain Unicode
        # Regular properties are ASCII-only and case-insensitive
        unless property.bytesize >= 2 && property.getbyte(0) == BYTE_HYPHEN && property.getbyte(1) == BYTE_HYPHEN
          # Regular property: force ASCII encoding and downcase
          property.force_encoding('US-ASCII')
          property.downcase!
        end
        @_pos += 1 # skip ':'

        skip_ws_and_comments

        # Parse value (read until ';' or '}', but respect quoted strings)
        value_start = @_pos
        important = false
        in_quote = nil # nil, BYTE_SQUOTE, or BYTE_DQUOTE

        until eof?
          byte = peek_byte

          if in_quote
            # Inside quoted string - only exit on matching quote
            if byte == in_quote
              in_quote = nil
            elsif byte == BYTE_BACKSLASH && @_pos + 1 < @_len
              # Skip escaped character
              @_pos += 1
            end
          else
            # Not in quote - check for terminators or quote start
            break if byte == BYTE_SEMICOLON || byte == BYTE_RBRACE

            if byte == BYTE_SQUOTE || byte == BYTE_DQUOTE
              in_quote = byte
            end
          end

          @_pos += 1
        end

        value = byteslice_encoded(value_start, @_pos - value_start)
        value.strip!

        # Check for !important (byte-by-byte, no regexp)
        if value.bytesize >= 10
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

        # Check for empty value (strict mode) - only if enabled to avoid overhead
        if @_check_empty_values && value.empty?
          raise ParseError.new("Empty value for property '#{property}'",
                               css: @_css, pos: property_start, type: :empty_value)
        end

        # Skip semicolon if present
        @_pos += 1 if peek_byte == BYTE_SEMICOLON

        # Convert relative URLs to absolute if enabled
        value = convert_urls_in_value(value)

        # Create Declaration struct
        declarations << Declaration.new(property, value, important)
      end

      declarations
    end

    # Parse at-rule (@media, @supports, @charset, @keyframes, @font-face, etc)
    # Translated from C: see ext/cataract/css_parser.c lines 962-1128
    def parse_at_rule
      at_rule_start = @_pos # Points to '@'
      @_pos += 1 # skip '@'

      # Find end of at-rule name (stop at whitespace or opening brace)
      name_start = @_pos
      until eof?
        byte = peek_byte
        break if whitespace?(byte) || byte == BYTE_LBRACE

        @_pos += 1
      end

      at_rule_name = byteslice_encoded(name_start, @_pos - name_start)

      # Handle @charset specially - it's just @charset "value";
      if at_rule_name == 'charset'
        skip_ws_and_comments
        # Read until semicolon
        value_start = @_pos
        while !eof? && peek_byte != BYTE_SEMICOLON
          @_pos += 1
        end

        charset_value = byteslice_encoded(value_start, @_pos - value_start)
        charset_value.strip!
        # Remove quotes
        @charset = charset_value.delete('"\'')

        @_pos += 1 if peek_byte == BYTE_SEMICOLON # consume semicolon
        return
      end

      # Handle @import - must come before rules (except @charset)
      if at_rule_name == 'import'
        # If we've already seen a rule, this @import is invalid
        if @rules.size > 0
          warn 'CSS @import ignored: @import must appear before all rules (found import after rules)'
          # Skip to semicolon
          while !eof? && peek_byte != BYTE_SEMICOLON
            @_pos += 1
          end
          @_pos += 1 if peek_byte == BYTE_SEMICOLON
          return
        end

        parse_import_statement
        return
      end

      # Handle conditional group at-rules: @supports, @layer, @container, @scope
      # These behave like @media but don't affect media context
      if AT_RULE_TYPES.include?(at_rule_name)
        skip_ws_and_comments

        # Remember start of condition for error reporting
        condition_start = @_pos

        # Skip to opening brace
        condition_end = @_pos
        while !eof? && peek_byte != BYTE_LBRACE
          condition_end = @_pos
          @_pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        # Validate condition (strict mode) - @supports, @container, @scope require conditions
        if @_check_malformed_at_rules && (at_rule_name == 'supports' || at_rule_name == 'container' || at_rule_name == 'scope')
          condition_str = byteslice_encoded(condition_start, condition_end - condition_start).strip
          if condition_str.empty?
            raise ParseError.new("Malformed @#{at_rule_name}: missing condition",
                                 css: @_css, pos: condition_start, type: :malformed_at_rule)
          end
        end

        @_pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @_pos
        block_end = find_matching_brace(@_pos)

        # Check depth before recursing
        if @_depth + 1 > MAX_PARSE_DEPTH
          raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
        end

        # Recursively parse block content (preserve parent media context)
        nested_parser = Parser.new(
          byteslice_encoded(block_start, block_end - block_start),
          parser_options: @_parser_options,
          parent_media_sym: @_parent_media_sym,
          depth: @_depth + 1
        )

        nested_result = nested_parser.parse

        # Merge nested selector_lists with offsetted IDs
        list_id_offset = @_next_selector_list_id
        if nested_result[:_selector_lists] && !nested_result[:_selector_lists].empty?
          nested_result[:_selector_lists].each do |list_id, rule_ids|
            new_list_id = list_id + list_id_offset
            offsetted_rule_ids = rule_ids.map { |rid| rid + @_rule_id_counter }
            @_selector_lists[new_list_id] = offsetted_rule_ids
          end
          @_next_selector_list_id = list_id_offset + nested_result[:_selector_lists].size
        end

        # NOTE: We no longer build media_index during parse
        # It will be built from MediaQuery objects after import resolution

        # Add nested rules to main rules array
        nested_result[:rules].each do |rule|
          rule.id = @_rule_id_counter
          # Update selector_list_id if applicable
          if rule.is_a?(Rule) && rule.selector_list_id
            rule.selector_list_id += list_id_offset
          end
          @_rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @_pos = block_end
        @_pos += 1 if @_pos < @_len && @_css.getbyte(@_pos) == BYTE_RBRACE

        return
      end

      # Handle @media specially - parse content and track in media_index
      if at_rule_name == 'media'
        skip_ws_and_comments

        # Find media query (up to opening brace)
        mq_start = @_pos
        while !eof? && peek_byte != BYTE_LBRACE
          @_pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        mq_end = @_pos
        # Trim trailing whitespace
        while mq_end > mq_start && whitespace?(@_css.getbyte(mq_end - 1))
          mq_end -= 1
        end

        child_media_string = byteslice_encoded(mq_start, mq_end - mq_start)
        # Keep media query exactly as written - parentheses are required per CSS spec
        child_media_string.strip!

        # Validate @media has a query (strict mode)
        if @_check_malformed_at_rules && child_media_string.empty?
          raise ParseError.new('Malformed @media: missing media query or condition',
                               css: @_css, pos: mq_start, type: :malformed_at_rule)
        end

        child_media_sym = child_media_string.to_sym

        # Split comma-separated media queries (e.g., "screen, print" -> ["screen", "print"])
        # Per W3C spec, comma acts as logical OR - each query is independent
        media_query_strings = child_media_string.split(',').map(&:strip)

        # Create MediaQuery objects for each query in the list
        media_query_ids = []
        media_query_strings.each do |query_string|
          media_type, media_conditions = parse_media_query_parts(query_string)
          media_query = Cataract::MediaQuery.new(@_media_query_id_counter, media_type, media_conditions)
          @media_queries << media_query
          media_query_ids << @_media_query_id_counter
          @_media_query_id_counter += 1
        end

        # If multiple queries, track them as a list for serialization
        if media_query_ids.size > 1
          @_media_query_lists[@_next_media_query_list_id] = media_query_ids
          @_next_media_query_list_id += 1
        end

        # Use first query ID as the primary one for rules in this block
        current_media_query_id = media_query_ids.first

        # Combine with parent media context
        combined_media_sym = combine_media_queries(@_parent_media_sym, child_media_sym)

        # NOTE: @_parent_media_query_id is always nil here because top-level @media blocks
        # create separate parsers without passing parent_media_query_id (see nested_parser creation below).
        # MediaQuery combining for nested @media happens in parse_mixed_block instead.
        # So this is just an alias to current_media_query_id.
        combined_media_query_id = current_media_query_id

        # Check media query limit
        unless @media_index.key?(combined_media_sym)
          @_media_query_count += 1
          if @_media_query_count > MAX_MEDIA_QUERIES
            raise SizeError, "Too many media queries: exceeded maximum of #{MAX_MEDIA_QUERIES}"
          end
        end

        @_pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @_pos
        block_end = find_matching_brace(@_pos)

        # Check depth before recursing
        if @_depth + 1 > MAX_PARSE_DEPTH
          raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
        end

        # Parse the content with the combined media context
        # Note: We don't pass parent_media_query_id because MediaQuery IDs are local to each parser
        # The nested parser will create its own MediaQueries, which we'll merge with offsetted IDs
        nested_parser = Parser.new(
          byteslice_encoded(block_start, block_end - block_start),
          parser_options: @_parser_options,
          parent_media_sym: combined_media_sym,
          depth: @_depth + 1
        )

        nested_result = nested_parser.parse

        # Merge nested selector_lists with offsetted IDs
        list_id_offset = @_next_selector_list_id
        if nested_result[:_selector_lists] && !nested_result[:_selector_lists].empty?
          nested_result[:_selector_lists].each do |list_id, rule_ids|
            new_list_id = list_id + list_id_offset
            offsetted_rule_ids = rule_ids.map { |rid| rid + @_rule_id_counter }
            @_selector_lists[new_list_id] = offsetted_rule_ids
          end
          @_next_selector_list_id = list_id_offset + nested_result[:_selector_lists].size
        end

        # Merge nested MediaQuery objects with offsetted IDs
        mq_id_offset = @_media_query_id_counter
        if nested_result[:media_queries] && !nested_result[:media_queries].empty?
          nested_result[:media_queries].each do |mq|
            # Create new MediaQuery with offsetted ID
            new_mq = Cataract::MediaQuery.new(mq.id + mq_id_offset, mq.type, mq.conditions)
            @media_queries << new_mq
          end
          @_media_query_id_counter += nested_result[:media_queries].size
        end

        # Merge nested media_query_lists with offsetted IDs
        if nested_result[:_media_query_lists] && !nested_result[:_media_query_lists].empty?
          nested_result[:_media_query_lists].each do |list_id, mq_ids|
            # Offset the list_id and media_query_ids
            new_list_id = list_id + @_next_media_query_list_id
            offsetted_mq_ids = mq_ids.map { |mq_id| mq_id + mq_id_offset }
            @_media_query_lists[new_list_id] = offsetted_mq_ids
          end
          @_next_media_query_list_id += nested_result[:_media_query_lists].size
        end

        # Merge nested media_index into ours (for nested @media)
        # Note: We no longer build media_index during parse
        # It will be built from MediaQuery objects after import resolution

        # Add nested rules to main rules array
        nested_result[:rules].each do |rule|
          rule.id = @_rule_id_counter
          # Update selector_list_id if applicable
          if rule.is_a?(Rule) && rule.selector_list_id
            rule.selector_list_id += list_id_offset
          end

          # Update media_query_id if applicable (both Rule and AtRule can have media_query_id)
          if rule.media_query_id
            # Nested parser assigned a media_query_id - need to combine with our context
            nested_mq_id = rule.media_query_id + mq_id_offset
            nested_mq = @media_queries[nested_mq_id]

            # Combine nested media query with our media context
            if nested_mq && combined_media_query_id
              outer_mq = @media_queries[combined_media_query_id]
              if outer_mq
                # Combine media queries directly without string building
                combined_type, combined_conditions = combine_media_query_parts(outer_mq, nested_mq.conditions)
                combined_mq = Cataract::MediaQuery.new(@_media_query_id_counter, combined_type, combined_conditions)
                @media_queries << combined_mq
                rule.media_query_id = @_media_query_id_counter
                @_media_query_id_counter += 1
              else
                rule.media_query_id = nested_mq_id
              end
            else
              rule.media_query_id = nested_mq_id
            end
          elsif rule.respond_to?(:media_query_id=)
            # Assign the combined media_query_id if no media_query_id set
            # (applies to both Rule and AtRule)
            rule.media_query_id = combined_media_query_id
          end

          # NOTE: We no longer build media_index during parse
          # It will be built from MediaQuery objects after import resolution

          @_rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @_pos = block_end
        @_pos += 1 if @_pos < @_len && @_css.getbyte(@_pos) == BYTE_RBRACE

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
          @_pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        selector_end = @_pos
        # Trim trailing whitespace
        while selector_end > selector_start && whitespace?(@_css.getbyte(selector_end - 1))
          selector_end -= 1
        end
        selector = byteslice_encoded(selector_start, selector_end - selector_start)

        @_pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @_pos
        block_end = find_matching_brace(@_pos)

        # Check depth before recursing
        if @_depth + 1 > MAX_PARSE_DEPTH
          raise DepthError, "CSS nesting too deep: exceeded maximum depth of #{MAX_PARSE_DEPTH}"
        end

        # Parse keyframe blocks as rules (0%/from/to etc)
        # Create a nested parser context
        nested_parser = Parser.new(
          byteslice_encoded(block_start, block_end - block_start),
          parser_options: @_parser_options,
          depth: @_depth + 1
        )
        nested_result = nested_parser.parse
        content = nested_result[:rules]

        # Move position past the closing brace
        @_pos = block_end
        # The closing brace should be at block_end
        @_pos += 1 if @_pos < @_len && @_css.getbyte(@_pos) == BYTE_RBRACE

        # Get rule ID and increment
        rule_id = @_rule_id_counter
        @_rule_id_counter += 1

        # Create AtRule with nested rules
        at_rule = AtRule.new(rule_id, selector, content, nil, @_parent_media_query_id)
        @rules << at_rule

        return
      end

      # Check for @font-face (contains <declaration-list>)
      if at_rule_name == 'font-face'
        # Build selector string: "@font-face"
        selector_start = at_rule_start # Points to '@'

        # Skip to opening brace
        while !eof? && peek_byte != BYTE_LBRACE
          @_pos += 1
        end

        return if eof? || peek_byte != BYTE_LBRACE

        selector_end = @_pos
        # Trim trailing whitespace
        while selector_end > selector_start && whitespace?(@_css.getbyte(selector_end - 1))
          selector_end -= 1
        end
        selector = byteslice_encoded(selector_start, selector_end - selector_start)

        @_pos += 1 # skip '{'

        # Find matching closing brace
        decl_start = @_pos
        decl_end = find_matching_brace(@_pos)

        # Parse declarations
        content = parse_declarations_block(decl_start, decl_end)

        # Move position past the closing brace
        @_pos = decl_end
        # The closing brace should be at decl_end
        @_pos += 1 if @_pos < @_len && @_css.getbyte(@_pos) == BYTE_RBRACE

        # Get rule ID and increment
        rule_id = @_rule_id_counter
        @_rule_id_counter += 1

        # Create AtRule with declarations
        at_rule = AtRule.new(rule_id, selector, content, nil, @_parent_media_query_id)
        @rules << at_rule

        return
      end

      # Unknown at-rule (@property, @page, @counter-style, etc.)
      # Treat as a regular selector-based rule with declarations
      selector_start = at_rule_start # Points to '@'

      # Skip to opening brace
      until eof? || peek_byte == BYTE_LBRACE # Save a not_opt instruction: while !eof? && peek_byte != BYTE_LBRACE
        @_pos += 1
      end

      return if eof? || peek_byte != BYTE_LBRACE

      selector_end = @_pos
      # Trim trailing whitespace
      while selector_end > selector_start && whitespace?(@_css.getbyte(selector_end - 1))
        selector_end -= 1
      end
      selector = byteslice_encoded(selector_start, selector_end - selector_start)

      @_pos += 1 # skip '{'

      # Parse declarations
      declarations = parse_declarations

      # Create Rule with declarations
      rule = Rule.new(
        @_rule_id_counter, # id
        selector,            # selector (e.g., "@property --main-color")
        declarations,        # declarations
        nil,                 # specificity
        nil,                 # parent_rule_id
        nil                  # nesting_style
      )

      @rules << rule
      @_rule_id_counter += 1
    end

    # Check if block contains nested selectors vs just declarations
    # Translated from C: see ext/cataract/css_parser.c has_nested_selectors
    def has_nested_selectors?(start_pos, end_pos)
      pos = start_pos

      while pos < end_pos
        # Skip whitespace
        while pos < end_pos && whitespace?(@_css.getbyte(pos))
          pos += 1
        end
        break if pos >= end_pos

        # Skip comments
        if pos + 1 < end_pos && @_css.getbyte(pos) == BYTE_SLASH && @_css.getbyte(pos + 1) == BYTE_STAR
          pos += 2
          while pos + 1 < end_pos
            if @_css.getbyte(pos) == BYTE_STAR && @_css.getbyte(pos + 1) == BYTE_SLASH
              pos += 2
              break
            end
            pos += 1
          end
          next
        end

        # Check for nested selector indicators
        byte = @_css.getbyte(pos)
        if byte == BYTE_AMPERSAND || byte == BYTE_DOT || byte == BYTE_HASH ||
           byte == BYTE_LBRACKET || byte == BYTE_COLON || byte == BYTE_ASTERISK ||
           byte == BYTE_GT || byte == BYTE_PLUS || byte == BYTE_TILDE
          # Look ahead - if followed by {, it's likely a nested selector
          lookahead = pos + 1
          while lookahead < end_pos && @_css.getbyte(lookahead) != BYTE_LBRACE &&
                @_css.getbyte(lookahead) != BYTE_SEMICOLON && @_css.getbyte(lookahead) != BYTE_NEWLINE
            lookahead += 1
          end
          return true if lookahead < end_pos && @_css.getbyte(lookahead) == BYTE_LBRACE
        end

        # Check for @media, @supports, etc nested inside
        return true if byte == BYTE_AT

        # Skip to next line or semicolon
        while pos < end_pos && @_css.getbyte(pos) != BYTE_SEMICOLON && @_css.getbyte(pos) != BYTE_NEWLINE
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
        @_pos += 1
      end

      @_pos += 1 if peek_byte == BYTE_SEMICOLON # consume semicolon
    end

    # Parse an @import statement
    # @import "url" [media-query];
    # @import url("url") [media-query];
    def parse_import_statement
      skip_ws_and_comments

      # Check for optional url(
      has_url_function = false
      if @_pos + 4 <= @_len && match_ascii_ci?(@_css, @_pos, 'url(')
        has_url_function = true
        @_pos += 4
        skip_ws_and_comments
      end

      # Find opening quote
      byte = peek_byte
      if eof? || (byte != BYTE_DQUOTE && byte != BYTE_SQUOTE)
        # Invalid @import, skip to semicolon
        while !eof? && peek_byte != BYTE_SEMICOLON
          @_pos += 1
        end
        @_pos += 1 unless eof?
        return
      end

      quote_char = byte
      @_pos += 1 # Skip opening quote

      url_start = @_pos

      # Find closing quote (handle escaped quotes)
      while !eof? && peek_byte != quote_char
        @_pos += if peek_byte == BYTE_BACKSLASH && @_pos + 1 < @_len
                   2 # Skip escaped character
                 else
                   1
                 end
      end

      if eof?
        # Unterminated string
        return
      end

      url = byteslice_encoded(url_start, @_pos - url_start)
      @_pos += 1 # Skip closing quote

      # Skip closing paren if we had url(
      if has_url_function
        skip_ws_and_comments
        @_pos += 1 if peek_byte == BYTE_RPAREN
      end

      skip_ws_and_comments

      # Check for optional media query (everything until semicolon)
      media_string = nil
      media_query_id = nil
      if !eof? && peek_byte != BYTE_SEMICOLON
        media_start = @_pos

        # Find semicolon
        while !eof? && peek_byte != BYTE_SEMICOLON
          @_pos += 1
        end

        media_end = @_pos

        # Trim trailing whitespace from media query
        while media_end > media_start && whitespace?(@_css.getbyte(media_end - 1))
          media_end -= 1
        end

        if media_end > media_start
          media_string = byteslice_encoded(media_start, media_end - media_start)

          # Split comma-separated media queries (e.g., "screen, handheld" -> ["screen", "handheld"])
          media_query_strings = media_string.split(',').map(&:strip)

          # Create MediaQuery objects for each query in the list
          media_query_ids = []
          media_query_strings.each do |query_string|
            media_type, media_conditions = parse_media_query_parts(query_string)

            # If we have a parent import's media context, combine them
            parent_import_type = @_parser_options[:parent_import_media_type]
            parent_import_conditions = @_parser_options[:parent_import_media_conditions]

            if parent_import_type
              # Combine: parent's type is the effective type
              # Conditions are combined with "and"
              combined_type = parent_import_type
              combined_conditions = if parent_import_conditions && media_conditions
                                      "#{parent_import_conditions} and #{media_conditions}"
                                    elsif parent_import_conditions
                                      "#{parent_import_conditions} and #{media_type}#{" and #{media_conditions}" if media_conditions}"
                                    elsif media_conditions
                                      media_type == :all ? media_conditions : "#{media_type} and #{media_conditions}"
                                    else
                                      media_type == parent_import_type ? nil : media_type.to_s
                                    end

              media_type = combined_type
              media_conditions = combined_conditions
            end

            # Create MediaQuery object
            media_query = Cataract::MediaQuery.new(@_media_query_id_counter, media_type, media_conditions)
            @media_queries << media_query
            media_query_ids << @_media_query_id_counter
            @_media_query_id_counter += 1
          end

          # Use the first media query ID for the import statement
          # (The list is tracked separately for serialization)
          media_query_id = media_query_ids.first

          # If multiple queries, track them as a list for serialization
          if media_query_ids.size > 1
            media_query_list_id = @_next_media_query_list_id
            @_media_query_lists[media_query_list_id] = media_query_ids
            @_next_media_query_list_id += 1
          end
        end
      end

      # Skip semicolon
      @_pos += 1 if peek_byte == BYTE_SEMICOLON

      # Create ImportStatement (resolved: false by default)
      import_stmt = ImportStatement.new(@_rule_id_counter, url, media_string, media_query_id, false)
      @imports << import_stmt
      @_rule_id_counter += 1
    end

    # Convert relative URLs in a value string to absolute URLs
    # Called when @_absolute_paths is enabled and @_base_uri is set
    #
    # @param value [String] The declaration value to process
    # @return [String] Value with relative URLs converted to absolute
    def convert_urls_in_value(value)
      return value unless @_absolute_paths && @_base_uri

      result = +''
      pos = 0
      len = value.bytesize

      while pos < len
        # Look for 'url(' - case insensitive
        byte = value.getbyte(pos)
        if pos + 3 < len &&
           (byte == BYTE_LOWER_U || byte == BYTE_UPPER_U) &&
           (value.getbyte(pos + 1) == BYTE_LOWER_R || value.getbyte(pos + 1) == BYTE_UPPER_R) &&
           (value.getbyte(pos + 2) == BYTE_LOWER_L || value.getbyte(pos + 2) == BYTE_UPPER_L) &&
           value.getbyte(pos + 3) == BYTE_LPAREN

          result << value.byteslice(pos, 4) # append 'url('
          pos += 4

          # Skip whitespace
          while pos < len && (value.getbyte(pos) == BYTE_SPACE || value.getbyte(pos) == BYTE_TAB)
            result << value.getbyte(pos).chr
            pos += 1
          end

          # Check for quote
          quote_char = nil
          if pos < len && (value.getbyte(pos) == BYTE_SQUOTE || value.getbyte(pos) == BYTE_DQUOTE)
            quote_char = value.getbyte(pos)
            pos += 1
          end

          # Extract URL
          url_start = pos
          if quote_char
            # Scan until matching quote
            while pos < len && value.getbyte(pos) != quote_char
              # Handle escape
              pos += if value.getbyte(pos) == BYTE_BACKSLASH && pos + 1 < len
                       2
                     else
                       1
                     end
            end
          else
            # Scan until ) or whitespace
            while pos < len
              b = value.getbyte(pos)
              break if b == BYTE_RPAREN || b == BYTE_SPACE || b == BYTE_TAB

              pos += 1
            end
          end

          url_str = value.byteslice(url_start, pos - url_start)

          # Check if URL needs resolution (is relative)
          # Skip if: contains "://" OR starts with "data:"
          needs_resolution = true
          if url_str.empty?
            needs_resolution = false
          else
            # Check for "://"
            i = 0
            url_len = url_str.bytesize
            while i + 2 < url_len
              if url_str.getbyte(i) == BYTE_COLON &&
                 url_str.getbyte(i + 1) == BYTE_SLASH &&
                 url_str.getbyte(i + 2) == BYTE_SLASH
                needs_resolution = false
                break
              end
              i += 1
            end

            # Check for "data:" prefix (case insensitive)
            if needs_resolution && url_len >= 5
              if (url_str.getbyte(0) == BYTE_LOWER_D || url_str.getbyte(0) == BYTE_UPPER_D) &&
                 (url_str.getbyte(1) == BYTE_LOWER_A || url_str.getbyte(1) == BYTE_UPPER_A) &&
                 (url_str.getbyte(2) == BYTE_LOWER_T || url_str.getbyte(2) == BYTE_UPPER_T) &&
                 (url_str.getbyte(3) == BYTE_LOWER_A || url_str.getbyte(3) == BYTE_UPPER_A) &&
                 url_str.getbyte(4) == BYTE_COLON
                needs_resolution = false
              end
            end
          end

          if needs_resolution
            # Resolve relative URL using the resolver proc
            begin
              resolved = @_uri_resolver.call(@_base_uri, url_str)
              result << "'" << resolved << "'"
            rescue StandardError
              # If resolution fails, preserve original
              if quote_char
                result << quote_char.chr << url_str << quote_char.chr
              else
                result << url_str
              end
            end
          elsif url_str.empty?
            # Preserve original URL
            result << "''"
          elsif quote_char
            result << quote_char.chr << url_str << quote_char.chr
          else
            result << url_str
          end

          # Skip past closing quote if present
          pos += 1 if quote_char && pos < len && value.getbyte(pos) == quote_char

          # Skip whitespace before )
          while pos < len && (value.getbyte(pos) == BYTE_SPACE || value.getbyte(pos) == BYTE_TAB)
            pos += 1
          end

          # The ) will be copied in the next iteration or at the end
        else
          result << byte.chr
          pos += 1
        end
      end

      result
    end

    # Parse a block of declarations given start/end positions
    # Used for @font-face and other at-rules
    # Translated from C: see ext/cataract/css_parser.c parse_declarations
    def parse_declarations_block(start_pos, end_pos)
      declarations = []
      pos = start_pos

      while pos < end_pos
        # Skip whitespace
        while pos < end_pos && whitespace?(@_css.getbyte(pos))
          pos += 1
        end
        break if pos >= end_pos

        # Parse declaration using shared helper (at-rules don't use !important)
        decl, pos = parse_single_declaration(pos, end_pos, false)
        declarations << decl if decl
      end

      declarations
    end

    # Combine parent and child media query parts directly without string building
    #
    # The parent's type takes precedence (child type is ignored per CSS spec).
    #
    # @param parent_mq [MediaQuery] Parent media query object
    # @param child_conditions [String|nil] Child conditions (e.g., "(min-width: 500px)")
    # @return [Array<Symbol, String|nil>] [combined_type, combined_conditions]
    #
    # @example
    #   combine_media_query_parts(screen_mq, "(min-width: 500px)") #=> [:screen, "... and (min-width: 500px)"]
    def combine_media_query_parts(parent_mq, child_conditions)
      # Type: parent's type wins (outermost type)
      combined_type = parent_mq.type

      # Conditions: combine parent and child conditions
      combined_conditions = if parent_mq.conditions && child_conditions
                              "#{parent_mq.conditions} and #{child_conditions}"
                            elsif parent_mq.conditions
                              parent_mq.conditions
                            elsif child_conditions
                              child_conditions
                            end

      [combined_type, combined_conditions]
    end

    # Parse media query string into type and conditions
    #
    # @param query [String] Media query string (e.g., "screen", "screen and (min-width: 768px)")
    # @return [Array<Symbol, String|nil>] [type, conditions] where type is Symbol, conditions is String or nil
    #
    # @example
    #   parse_media_query_parts("screen") #=> [:screen, nil]
    #   parse_media_query_parts("screen and (min-width: 768px)") #=> [:screen, "(min-width: 768px)"]
    #   parse_media_query_parts("(min-width: 500px)") #=> [:all, "(min-width: 500px)"]
    def parse_media_query_parts(query)
      i = 0
      len = query.bytesize

      # Skip leading whitespace
      while i < len && whitespace?(query.getbyte(i))
        i += 1
      end

      return [:all, nil] if i >= len

      # Check if starts with '(' - media feature without type (defaults to :all)
      if query.getbyte(i) == BYTE_LPAREN
        return [:all, query.byteslice(i, len - i)]
      end

      # Find first media type word
      word_start = i
      while i < len
        byte = query.getbyte(i)
        break if whitespace?(byte) || byte == BYTE_LPAREN

        i += 1
      end

      type = query.byteslice(word_start, i - word_start).to_sym

      # Skip whitespace after type
      while i < len && whitespace?(query.getbyte(i))
        i += 1
      end

      # Check if there's more (conditions)
      if i >= len
        return [type, nil]
      end

      # Look for " and " keyword (case-insensitive)
      # We need to find "and" as a separate word
      and_pos = nil
      check_i = i
      while check_i < len - 2
        # Check for 'and' (a=97/65, n=110/78, d=100/68)
        byte0 = query.getbyte(check_i)
        byte1 = query.getbyte(check_i + 1)
        byte2 = query.getbyte(check_i + 2)

        if (byte0 == BYTE_LOWER_A || byte0 == BYTE_UPPER_A) &&
           (byte1 == BYTE_LOWER_N || byte1 == BYTE_UPPER_N) &&
           (byte2 == BYTE_LOWER_D || byte2 == BYTE_UPPER_D)
          # Make sure it's a word boundary (whitespace before and after)
          before_ok = check_i == 0 || whitespace?(query.getbyte(check_i - 1))
          after_ok = check_i + 3 >= len || whitespace?(query.getbyte(check_i + 3))
          if before_ok && after_ok
            and_pos = check_i
            break
          end
        end
        check_i += 1
      end

      if and_pos
        # Skip past "and " to get conditions
        conditions_start = and_pos + 3 # skip "and"
        while conditions_start < len && whitespace?(query.getbyte(conditions_start))
          conditions_start += 1
        end
        conditions = query.byteslice(conditions_start, len - conditions_start)
        [type, conditions]
      else
        # No "and" found - rest is conditions (unusual but possible)
        [type, query.byteslice(i, len - i)]
      end
    end
  end
end
