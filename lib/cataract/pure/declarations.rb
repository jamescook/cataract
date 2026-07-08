# frozen_string_literal: true

# Pure Ruby CSS parser - standalone declaration-list string parsing
# NO REGEXP ALLOWED - char-by-char parsing only
#
# Backs Declarations.new(some_string), NOT the main parser's declaration
# handling - the two intentionally disagree in a few ways:
#   - Custom properties (--foo) are downcased here too (the main parser
#     preserves their case, since they're case-sensitive per spec)
#   - No relative-URL conversion (there's no base_uri to convert against)
#   - A missing colon stops parsing entirely, rather than recovering at the
#     next semicolon like the main parser does
# Mirrors ext/cataract/cataract.c's new_parse_declarations_string exactly,
# byte for byte, since both backends must agree here.

module Cataract
  module Backends
    class PureImpl
      # Parse a standalone CSS declaration-list string ("color: red; margin: 10px")
      # into an array of Declaration structs.
      #
      # @param str [String] CSS declarations, optionally wrapped in { ... }
      # @return [Array<Declaration>] Parsed declarations
      def parse_declarations(str)
        fin = str.bytesize
        pos = 0

        # Strip outer braces and whitespace (css_parser compatibility)
        pos += 1 while pos < fin && (decl_whitespace?(str.getbyte(pos)) || str.getbyte(pos) == BYTE_LBRACE)
        fin -= 1 while fin > pos && (decl_whitespace?(str.getbyte(fin - 1)) || str.getbyte(fin - 1) == BYTE_RBRACE)

        declarations = []

        while pos < fin
          pos += 1 while pos < fin && (decl_whitespace?(str.getbyte(pos)) || str.getbyte(pos) == BYTE_SEMICOLON)
          break if pos >= fin

          span = scan_one_declaration(str, pos, fin)
          break unless span # No colon found - stop parsing entirely

          pos = span[:next_pos]
          next unless span[:val_end] > span[:val_start] # Skip if value is empty

          property = str.byteslice(span[:prop_start], span[:prop_end] - span[:prop_start])
                        .force_encoding(Encoding::US_ASCII).downcase
          value = str.byteslice(span[:val_start], span[:val_end] - span[:val_start]).force_encoding(Encoding::UTF_8)

          declarations << Declaration.new(property, value, span[:important])
        end

        declarations
      end

      # Scans one "prop: value" declaration starting at pos, stopping at fin
      # (never reads past it). On success, returns a span hash and next_pos is
      # the position just past the terminating ';' (or fin/'}' if there wasn't
      # one). On failure - no ':' found - returns nil, leaving the caller to
      # decide how to recover (this parser stops entirely).
      #
      # The value scan tracks paren depth, so a ';' inside url(...) or rgba(...)
      # doesn't end the value early, and always stops at an unguarded '}'.
      def scan_one_declaration(str, pos, fin)
        prop_start = pos
        pos += 1 while pos < fin && str.getbyte(pos) != BYTE_COLON
        return nil if pos >= fin

        prop_end = pos
        prop_end -= 1 while prop_end > prop_start && decl_whitespace?(str.getbyte(prop_end - 1))
        prop_start += 1 while prop_start < prop_end && decl_whitespace?(str.getbyte(prop_start))

        pos += 1 # Skip ':'
        pos += 1 while pos < fin && decl_whitespace?(str.getbyte(pos))

        val_start = pos
        paren_depth = 0
        while pos < fin && str.getbyte(pos) != BYTE_RBRACE
          byte = str.getbyte(pos)
          if byte == BYTE_LPAREN
            paren_depth += 1
          elsif byte == BYTE_RPAREN
            paren_depth -= 1
          elsif byte == BYTE_SEMICOLON && paren_depth == 0
            break
          end
          pos += 1
        end
        val_end = pos
        val_end -= 1 while val_end > val_start && decl_whitespace?(str.getbyte(val_end - 1))

        important, val_end = extract_important(str, val_start, val_end)
        val_end -= 1 while val_end > val_start && decl_whitespace?(str.getbyte(val_end - 1))

        pos += 1 if pos < fin && str.getbyte(pos) == BYTE_SEMICOLON

        { prop_start: prop_start, prop_end: prop_end, val_start: val_start, val_end: val_end,
          important: important, next_pos: pos }
      end
      private :scan_one_declaration

      # Detects and strips a trailing '!important' marker from [val_start, val_end).
      # Assumes trailing whitespace has already been trimmed once. Zero or more
      # whitespace tokens are allowed between '!' and 'important' per the CSS2.1
      # grammar. Returns [important?, new_val_end].
      def extract_important(str, val_start, val_end)
        check = val_end
        return [false, val_end] if check - val_start < 10 # strlen("!important") == 10

        check -= 1 while check > val_start && decl_whitespace?(str.getbyte(check - 1))
        return [false, val_end] if check - val_start < 9 || str.byteslice(check - 9, 9) != 'important'

        check -= 9
        check -= 1 while check > val_start && decl_whitespace?(str.getbyte(check - 1))
        return [false, val_end] if check <= val_start || str.getbyte(check - 1) != BYTE_BANG

        [true, check - 1]
      end
      private :extract_important

      def decl_whitespace?(byte)
        byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR
      end
      private :decl_whitespace?
    end
  end
end
