# frozen_string_literal: true

# Pure Ruby CSS parser - Specificity calculation
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  # Calculate CSS specificity for a selector
  #
  # @param selector [String] CSS selector
  # @return [Integer] Specificity value
  #
  # Specificity calculation (per CSS spec):
  # - Count IDs (#id) - each worth 100
  # - Count classes/attributes/pseudo-classes (.class, [attr], :pseudo) - each worth 10
  # - Count elements/pseudo-elements (div, ::before) - each worth 1
  def self.calculate_specificity(selector)
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

    pseudo_element_kwords = %w[before after first-line first-letter selection]

    while i < len
      byte = selector.getbyte(i)

      # Skip whitespace and combinators
      if byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR ||
         byte == BYTE_GT || byte == BYTE_PLUS || byte == BYTE_TILDE || byte == BYTE_COMMA
        i += 1
        next
      end

      # ID selector: #id
      if byte == BYTE_HASH
        id_count += 1
        i += 1
        # Skip the identifier
        while i < len && ident_char?(selector.getbyte(i))
          i += 1
        end
        next
      end

      # Class selector: .class
      if byte == BYTE_DOT
        class_count += 1
        i += 1
        # Skip the identifier
        while i < len && ident_char?(selector.getbyte(i))
          i += 1
        end
        next
      end

      # Attribute selector: [attr]
      if byte == BYTE_LBRACKET
        attr_count += 1
        i += 1
        # Skip to closing bracket
        bracket_depth = 1
        while i < len && bracket_depth > 0
          b = selector.getbyte(i)
          if b == BYTE_LBRACKET
            bracket_depth += 1
          elsif b == BYTE_RBRACKET
            bracket_depth -= 1
          end
          i += 1
        end
        next
      end

      # Pseudo-element (::) or pseudo-class (:)
      if byte == BYTE_COLON
        i += 1
        is_pseudo_element = false

        # Check for double colon (::)
        if i < len && selector.getbyte(i) == BYTE_COLON
          is_pseudo_element = true
          i += 1
        end

        # Extract pseudo name
        pseudo_start = i
        while i < len && ident_char?(selector.getbyte(i))
          i += 1
        end
        pseudo_name = selector[pseudo_start...i]

        # Check for legacy pseudo-elements (single colon but should be double)
        is_legacy_pseudo_element = false
        if !is_pseudo_element && !pseudo_name.empty?
          is_legacy_pseudo_element = pseudo_element_kwords.include?(pseudo_name)
        end

        # Check for :not() - it doesn't count itself, but its content does
        is_not = (pseudo_name == 'not')

        # Skip function arguments if present
        if i < len && selector.getbyte(i) == BYTE_LPAREN
          i += 1
          paren_depth = 1

          # If it's :not(), calculate specificity of the content
          if is_not
            not_content_start = i

            # Find closing paren
            while i < len && paren_depth > 0
              b = selector.getbyte(i)
              if b == BYTE_LPAREN
                paren_depth += 1
              elsif b == BYTE_RPAREN
                paren_depth -= 1
              end
              i += 1 if paren_depth > 0
            end

            not_content = selector[not_content_start...i]

            # Recursively calculate specificity of :not() content
            if !not_content.empty?
              not_specificity = calculate_specificity(not_content)

              # Add :not() content's specificity to our counts
              additional_a = not_specificity / 100
              additional_b = (not_specificity % 100) / 10
              additional_c = not_specificity % 10

              id_count += additional_a
              class_count += additional_b
              element_count += additional_c
            end

            i += 1  # Skip closing paren
          else
            # Skip other function arguments
            while i < len && paren_depth > 0
              b = selector.getbyte(i)
              if b == BYTE_LPAREN
                paren_depth += 1
              elsif b == BYTE_RPAREN
                paren_depth -= 1
              end
              i += 1
            end

            # Count the pseudo-class/element
            if is_pseudo_element || is_legacy_pseudo_element
              pseudo_element_count += 1
            else
              pseudo_class_count += 1
            end
          end
        else
          # No function arguments - count the pseudo-class/element
          if is_not
            # :not without parens is invalid, but don't count it
          elsif is_pseudo_element || is_legacy_pseudo_element
            pseudo_element_count += 1
          else
            pseudo_class_count += 1
          end
        end
        next
      end

      # Universal selector: *
      if byte == BYTE_ASTERISK
        # Universal selector has specificity 0, don't count
        i += 1
        next
      end

      # Type selector (element name): div, span, etc.
      if letter?(byte)
        element_count += 1
        # Skip the identifier
        while i < len && ident_char?(selector.getbyte(i))
          i += 1
        end
        next
      end

      # Unknown character, skip it
      i += 1
    end

    # Calculate specificity using W3C formula
    specificity = (id_count * 100) +
                  ((class_count + attr_count + pseudo_class_count) * 10) +
                  ((element_count + pseudo_element_count) * 1)

    specificity
  end
end
