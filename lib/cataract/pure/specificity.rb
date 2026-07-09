# frozen_string_literal: true

# Pure Ruby CSS parser - Specificity calculation
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  module Backends
    class PureImpl
      # Legacy CSS2 pseudo-elements written with a single colon (e.g. :before)
      # that must still be counted as pseudo-elements, not pseudo-classes.
      PSEUDO_ELEMENT_KEYWORDS = %w[before after first-line first-letter selection].freeze

      # Check if byte is a letter (a-z, A-Z)
      # @param byte [Integer] Byte value from String#getbyte
      # @return [Boolean] true if letter
      def letter?(byte)
        (byte >= BYTE_LOWER_A && byte <= BYTE_LOWER_Z) ||
          (byte >= BYTE_UPPER_A && byte <= BYTE_UPPER_Z)
      end
      private :letter?

      # Check if byte is alphanumeric, hyphen, or underscore (CSS identifier char)
      # @param byte [Integer] Byte value from String#getbyte
      # @return [Boolean] true if valid identifier character
      def ident_char?(byte)
        letter?(byte) || (byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9) || byte == BYTE_HYPHEN || byte == BYTE_UNDERSCORE
      end
      private :ident_char?

      # Calculate CSS specificity for a selector
      #
      # @param selector [String] CSS selector
      # @return [Integer] Specificity value
      #
      # Specificity calculation (per CSS spec):
      # - Count IDs (#id) - each worth 100
      # - Count classes/attributes/pseudo-classes (.class, [attr], :pseudo) - each worth 10
      # - Count elements/pseudo-elements (div, ::before) - each worth 1
      def calculate_specificity(selector)
        return 0 if selector.nil? || selector.empty?

        # Counters for specificity components
        id_count = 0
        class_count = 0
        attr_count = 0
        pseudo_class_count = 0
        pseudo_element_count = 0
        element_count = 0

        i = 0
        len = selector.length

        while i < len
          byte = selector.getbyte(i)

          if byte == BYTE_HASH
            id_count += 1
            i = skip_identifier(selector, i + 1, len)
          elsif byte == BYTE_DOT
            class_count += 1
            i = skip_identifier(selector, i + 1, len)
          elsif byte == BYTE_LBRACKET
            attr_count += 1
            i = skip_attribute_selector(selector, i, len)
          elsif byte == BYTE_COLON
            i, is_not, not_content, counts_as_element = parse_pseudo(selector, i, len)
            if not_content
              # :not() doesn't count itself, but its content does
              not_specificity = calculate_specificity(not_content)
              id_count += not_specificity / 100
              class_count += (not_specificity % 100) / 10
              element_count += not_specificity % 10
            elsif !is_not
              if counts_as_element
                pseudo_element_count += 1
              else
                pseudo_class_count += 1
              end
            end
          elsif letter?(byte)
            ident_end = skip_identifier(selector, i + 1, len)
            if ident_end < len && selector.getbyte(ident_end) == BYTE_PIPE
              # Namespace prefix (ns|E, css-namespaces-3 qname grammar) -
              # contributes nothing itself; the local name after '|' is the
              # real type selector and gets counted on the next iteration.
              i = ident_end + 1
            else
              element_count += 1
              i = ident_end
            end
          else
            # Whitespace, combinators, and the universal selector (*) all have
            # zero specificity - just skip a single byte.
            i += 1
          end
        end

        # Calculate specificity using W3C formula
        (id_count * 100) +
          ((class_count + attr_count + pseudo_class_count) * 10) +
          ((element_count + pseudo_element_count) * 1)
      end

      # Advances past an identifier (used after #id, .class, element names, and
      # pseudo names), returning the index of the first non-identifier byte.
      def skip_identifier(selector, pos, len)
        pos += 1 while pos < len && ident_char?(selector.getbyte(pos))
        pos
      end
      private :skip_identifier

      # Advances past a bracketed [attr] selector, honoring nested brackets,
      # returning the index just after the matching closing bracket.
      def skip_attribute_selector(selector, pos, len)
        skip_balanced(selector, pos + 1, len, BYTE_LBRACKET, BYTE_RBRACKET)
      end
      private :skip_attribute_selector

      # Advances past a balanced open/close byte pair (already past the opening
      # byte, with depth 1), returning the index just after the matching close.
      def skip_balanced(selector, pos, len, open_byte, close_byte)
        depth = 1
        while pos < len && depth > 0
          b = selector.getbyte(pos)
          depth += 1 if b == open_byte
          depth -= 1 if b == close_byte
          pos += 1
        end
        pos
      end
      private :skip_balanced

      # Advances past a balanced open/close byte pair (already past the opening
      # byte, with depth 1), returning the index OF the matching close byte
      # (rather than past it), so the caller can capture the content in between.
      def find_balanced_close(selector, pos, len, open_byte, close_byte)
        depth = 1
        while pos < len && depth > 0
          b = selector.getbyte(pos)
          depth += 1 if b == open_byte
          depth -= 1 if b == close_byte
          pos += 1 if depth > 0
        end
        pos
      end
      private :find_balanced_close

      # Parses a :pseudo-class, ::pseudo-element, or :not(...) token starting at
      # the colon byte. Returns [new_pos, is_not, not_content, counts_as_element]:
      # - new_pos: index just after the fully-consumed token (incl. any (...) args)
      # - is_not: whether this token is :not (which never counts itself)
      # - not_content: the non-empty content of :not(...), or nil otherwise
      # - counts_as_element: whether this token counts toward pseudo-elements
      #   (::foo, or a legacy single-colon pseudo-element like :before) rather
      #   than pseudo-classes
      def parse_pseudo(selector, pos, len)
        pos += 1
        is_pseudo_element = false
        if pos < len && selector.getbyte(pos) == BYTE_COLON
          is_pseudo_element = true
          pos += 1
        end

        pseudo_start = pos
        pos = skip_identifier(selector, pos, len)
        pseudo_name = selector[pseudo_start...pos]

        is_legacy_pseudo_element = !is_pseudo_element && !pseudo_name.empty? &&
                                   PSEUDO_ELEMENT_KEYWORDS.include?(pseudo_name)
        is_not = (pseudo_name == 'not')
        not_content = nil

        if pos < len && selector.getbyte(pos) == BYTE_LPAREN
          pos += 1
          if is_not
            content_start = pos
            pos = find_balanced_close(selector, pos, len, BYTE_LPAREN, BYTE_RPAREN)
            content = selector[content_start...pos]
            not_content = content unless content.empty?
            pos += 1 # Skip closing paren
          else
            pos = skip_balanced(selector, pos, len, BYTE_LPAREN, BYTE_RPAREN)
          end
        end

        [pos, is_not, not_content, is_pseudo_element || is_legacy_pseudo_element]
      end
      private :parse_pseudo
    end
  end
end
