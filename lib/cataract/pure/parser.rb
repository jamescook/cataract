# frozen_string_literal: true

# Pure Ruby CSS parser - Parser class
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  # Pure Ruby CSS parser - char-by-char, NO REGEXP
  class Parser
    # Maximum parse depth (prevent infinite recursion)
    MAX_PARSE_DEPTH = 10

    # Maximum media queries (prevent symbol table exhaustion)
    MAX_MEDIA_QUERIES = 1000

    # Maximum property name/value lengths
    MAX_PROPERTY_NAME_LENGTH = 256
    MAX_PROPERTY_VALUE_LENGTH = 32768

    attr_reader :css, :pos, :len

    def initialize(css_string, parent_media_sym: nil)
      @css = css_string.dup.freeze
      @pos = 0
      @len = @css.bytesize
      @parent_media_sym = parent_media_sym

      # Parser state
      @rules = []                    # Flat array of Rule structs
      @media_index = {}              # Symbol => Array of rule IDs
      @rule_id_counter = 0           # Next rule ID (0-indexed)
      @media_query_count = 0         # Safety limit
      @media_cache = {}              # Parse-time cache: string => parsed media types
      @has_nesting = false           # Set to true if any nested rules found
      @depth = 0                     # Current recursion depth
      @charset = nil                 # @charset declaration
    end

    def parse
      # Skip @import statements at the beginning (they're handled by ImportResolver)
      # Per CSS spec, @import must come before all rules (except @charset)
      skip_imports

      # Main parsing loop - char-by-char, NO REGEXP
      while !eof?
        skip_ws_and_comments
        break if eof?

        if ENV['DEBUG_PARSER']
          puts "DEBUG: Main loop, pos=#{@pos}, next 50 chars: #{@css[@pos, 50].inspect}"
        end

        # Peek at next byte to determine what to parse
        byte = peek_byte

        # Check for at-rules (@media, @charset, etc)
        if byte == BYTE_AT
          parse_at_rule
          next
        end

        # Must be a selector-based rule
        selector = parse_selector

        if ENV['DEBUG_PARSER']
          puts "DEBUG: Parsed selector: #{selector.inspect}, pos now=#{@pos}"
        end

        next if selector.nil? || selector.empty?

        declarations = parse_declarations

        # Split comma-separated selectors into individual rules
        # "html, body, p" => ["html", "body", "p"]
        selectors = selector.split(',').map(&:strip)

        selectors.each do |individual_selector|
          next if individual_selector.empty?

          # Create Rule struct
          rule = Rule.new(
            @rule_id_counter,    # id
            individual_selector, # selector
            declarations,        # declarations
            nil,                 # specificity (calculated lazily)
            nil,                 # parent_rule_id
            nil                  # nesting_style
          )

          @rules << rule
          @rule_id_counter += 1
        end
      end

      {
        rules: @rules,
        _media_index: @media_index,
        charset: @charset,
        _has_nesting: @has_nesting
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

    # Read current byte and advance position
    # @return [Integer, nil] Byte value or nil if EOF
    def read_byte
      return nil if eof?
      byte = @css.getbyte(@pos)
      @pos += 1
      byte
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

    # Skip whitespace
    def skip_whitespace
      @pos += 1 while !eof? && whitespace?(peek_byte)
    end

    # Skip CSS comments /* ... */
    def skip_comment
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

    # Skip whitespace and comments
    def skip_ws_and_comments
      loop do
        old_pos = @pos
        skip_whitespace
        skip_comment
        break if @pos == old_pos # No progress made
      end
    end

    # Find matching closing brace
    # Translated from C: see ext/cataract/css_parser.c find_matching_brace
    def find_matching_brace(start_pos)
      depth = 1
      pos = start_pos

      if ENV['DEBUG_PARSER']
        puts "DEBUG: find_matching_brace start_pos=#{start_pos}, char at pos: #{@css[start_pos].inspect}"
      end

      while pos < @len && depth > 0
        byte = @css.getbyte(pos)
        if byte == BYTE_LBRACE
          depth += 1
        elsif byte == BYTE_RBRACE
          depth -= 1
        end
        pos += 1 if depth > 0
      end

      if ENV['DEBUG_PARSER']
        puts "DEBUG: find_matching_brace end pos=#{pos}, depth=#{depth}, char at pos: #{@css[pos].inspect if pos < @len}"
      end

      pos
    end

    # Find matching closing paren
    def find_matching_paren(start_pos)
      # TODO: Track depth, handle nested parens
      # Return position of matching ')' or len if not found
      start_pos
    end

    # Parse selector (read until '{')
    def parse_selector
      start_pos = @pos

      if ENV['DEBUG_PARSER']
        puts "DEBUG: parse_selector start_pos=#{start_pos}, next 50: #{@css[start_pos, 50].inspect}"
      end

      # Read until we find '{'
      while !eof? && peek_byte != BYTE_LBRACE
        @pos += 1
      end

      # If we hit EOF without finding '{', return nil
      return nil if eof?

      if ENV['DEBUG_PARSER']
        puts "DEBUG: parse_selector found '{' at pos=#{@pos}, char: #{@css[@pos].inspect}"
      end

      # Extract selector text
      selector_text = @css.byteslice(start_pos...@pos)

      if ENV['DEBUG_PARSER']
        puts "DEBUG: parse_selector extracted: #{selector_text.inspect}"
      end

      # Skip the '{'
      @pos += 1 if peek_byte == BYTE_LBRACE

      if ENV['DEBUG_PARSER']
        puts "DEBUG: parse_selector after skip, pos=#{@pos}"
      end

      # Trim whitespace from selector
      selector_text.strip
    end

    # Parse declaration block (inside { ... })
    # Assumes we're already past the opening '{'
    def parse_declarations
      declarations = []

      # Read until we find the closing '}'
      while !eof?
        skip_ws_and_comments
        break if eof?

        # Check for closing brace
        if peek_byte == BYTE_RBRACE
          @pos += 1 # consume '}'
          break
        end

        # Parse property name (read until ':')
        property_start = @pos
        while !eof?
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

        property = @css.byteslice(property_start...@pos).strip.downcase
        @pos += 1 # skip ':'

        skip_ws_and_comments

        # Parse value (read until ';' or '}')
        value_start = @pos
        important = false

        while !eof?
          byte = peek_byte
          break if byte == BYTE_SEMICOLON || byte == BYTE_RBRACE
          @pos += 1
        end

        value = @css.byteslice(value_start...@pos).strip

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
          if i >= 8 && value[i-8..i] == 'important'
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
              # Remove everything from '!' onwards
              value = value[0...i].strip
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
      at_rule_start = @pos  # Points to '@'
      @pos += 1 # skip '@'

      # Find end of at-rule name (stop at whitespace or opening brace)
      name_start = @pos
      while !eof?
        byte = peek_byte
        break if whitespace?(byte) || byte == BYTE_LBRACE
        @pos += 1
      end

      at_rule_name = @css.byteslice(name_start...@pos)

      # Handle @charset specially - it's just @charset "value";
      if at_rule_name == 'charset'
        skip_ws_and_comments
        # Read until semicolon
        value_start = @pos
        while !eof? && peek_byte != BYTE_SEMICOLON
          @pos += 1
        end

        charset_value = @css.byteslice(value_start...@pos).strip
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

      # Handle conditional group at-rules: @supports, @layer, @container, @scope
      # These behave like @media but don't affect media context
      if %w[supports layer container scope].include?(at_rule_name)
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

        # Recursively parse block content (preserve parent media context)
        nested_parser = Parser.new(@css.byteslice(block_start...block_end), parent_media_sym: @parent_media_sym)
        nested_result = nested_parser.parse

        # Merge nested media_index into ours
        nested_result[:_media_index].each do |media, rule_ids|
          @media_index[media] ||= []
          @media_index[media].concat(rule_ids.map { |rid| @rule_id_counter + rid })
        end

        # Add nested rules to main rules array
        nested_result[:rules].each do |rule|
          rule.id = @rule_id_counter
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

        child_media_string = @css.byteslice(mq_start...mq_end)
        child_media_sym = child_media_string.to_sym

        # Combine with parent media context
        combined_media_sym = combine_media_queries(@parent_media_sym, child_media_sym)

        # Check media query limit
        if !@media_index.key?(combined_media_sym)
          @media_query_count += 1
          if @media_query_count > MAX_MEDIA_QUERIES
            raise SizeError, "Too many media queries: exceeded maximum of #{MAX_MEDIA_QUERIES}"
          end
        end

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Parse the content with the combined media context
        nested_parser = Parser.new(@css.byteslice(block_start...block_end), parent_media_sym: combined_media_sym)
        nested_result = nested_parser.parse

        # Merge nested media_index into ours (for nested @media)
        nested_result[:_media_index].each do |media, rule_ids|
          @media_index[media] ||= []
          @media_index[media].concat(rule_ids.map { |rid| @rule_id_counter + rid })
        end

        # Add nested rules to main rules array and update media_index
        nested_result[:rules].each do |rule|
          rule.id = @rule_id_counter

          # Add to full query symbol
          @media_index[combined_media_sym] ||= []
          @media_index[combined_media_sym] << @rule_id_counter

          # Extract media types and add to each (if different from full query)
          media_types = Cataract.parse_media_types(combined_media_sym)
          media_types.each do |media_type|
            # Only add if different from combined_media_sym to avoid duplication
            if media_type != combined_media_sym
              @media_index[media_type] ||= []
              @media_index[media_type] << @rule_id_counter
            end
          end

          @rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @pos = block_end
        @pos += 1 if @pos < @len && @css.getbyte(@pos) == BYTE_RBRACE

        if ENV['DEBUG_PARSER']
          puts "DEBUG: After @media, pos=#{@pos}, next 50 chars: #{@css[@pos, 50].inspect}"
        end

        return
      end

      # Check for @keyframes (contains <rule-list>)
      is_keyframes = at_rule_name == 'keyframes' ||
                     at_rule_name == '-webkit-keyframes' ||
                     at_rule_name == '-moz-keyframes'

      if is_keyframes
        # Build full selector string: "@keyframes fade"
        selector_start = at_rule_start  # Points to '@'

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
        selector = @css.byteslice(selector_start...selector_end)

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Parse keyframe blocks as rules (0%/from/to etc)
        # Create a nested parser context
        nested_parser = Parser.new(@css.byteslice(block_start...block_end))
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
        selector_start = at_rule_start  # Points to '@'

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
        selector = @css.byteslice(selector_start...selector_end)

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
      selector_start = at_rule_start  # Points to '@'

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
      selector = @css.byteslice(selector_start...selector_end)

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
    def has_nested_selectors?(start_pos, end_pos)
      # TODO: Look for &, ., #, [, :, *, >, +, ~, @ followed by {
      # Return true if nested selectors found
      false
    end

    # Resolve nested selector against parent
    def resolve_nested_selector(parent_selector, nested_selector)
      # TODO: Handle & replacement (explicit nesting)
      # Handle implicit nesting (prepend parent)
      # Return [resolved_selector, nesting_style]
      [nested_selector, 0]
    end

    # Lowercase property name (CSS properties are ASCII)
    def lowercase_property(str)
      # Simple ASCII lowercase (no encoding issues)
      str.downcase
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

      combined = parent_str + " and "

      # If child is a condition (contains ':'), wrap it in parentheses
      if child_str.include?(':')
        # Add parens if not already present
        if child_str.start_with?('(') && child_str.end_with?(')')
          combined += child_str
        else
          combined += '(' + child_str + ')'
        end
      else
        combined += child_str
      end

      combined.to_sym
    end

    # Skip to next semicolon or closing brace (error recovery)
    def skip_to_semicolon_or_brace
      while !eof? && peek_byte != BYTE_SEMICOLON && peek_byte != BYTE_RBRACE
        @pos += 1
      end
      @pos += 1 if peek_byte == BYTE_SEMICOLON # consume semicolon
    end

    # Skip to next rule (error recovery for at-rules we don't handle yet)
    def skip_to_next_rule
      depth = 0
      while !eof?
        char = peek_byte
        if char == BYTE_LBRACE
          depth += 1
        elsif char == BYTE_RBRACE
          depth -= 1
          if depth <= 0
            @pos += 1 # consume final '}'
            break
          end
        end
        @pos += 1
      end
    end

    # Skip @import statements at the beginning of CSS
    # Per CSS spec, @import must come before all rules (except @charset)
    def skip_imports
      while !eof?
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

        # Check for @import
        if @pos + 7 <= @len && @css.getbyte(@pos) == BYTE_AT && @css.byteslice(@pos+1...@pos+7).downcase == 'import'
          # Check that it's followed by whitespace or quote
          if @pos + 7 >= @len || whitespace?(@css.getbyte(@pos + 7)) || @css.getbyte(@pos + 7) == BYTE_SQUOTE || @css.getbyte(@pos + 7) == BYTE_DQUOTE
            # Skip to semicolon
            while !eof? && peek_byte != BYTE_SEMICOLON
              @pos += 1
            end
            @pos += 1 if !eof?  # Skip semicolon
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

        property = @css.byteslice(prop_start...prop_end).downcase

        pos += 1  # Skip ':'

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

        value = @css.byteslice(val_start...val_end)

        pos += 1 if pos < end_pos && @css.getbyte(pos) == BYTE_SEMICOLON

        # Create Declaration struct (at-rules don't use !important)
        declarations << Declaration.new(property, value, false)
      end

      declarations
    end
  end
end
