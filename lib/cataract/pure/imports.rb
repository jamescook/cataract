# frozen_string_literal: true

# Pure Ruby CSS parser - Import extraction
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  # Helper: Case-insensitive ASCII byte comparison
  # Compares bytes at given position with ASCII pattern (case-insensitive)
  # Safe to use even if position is in middle of multi-byte UTF-8 characters
  # Returns true if match, false otherwise
  def self.match_ascii_ci?(str, pos, pattern)
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
  # Extract @import statements from CSS
  #
  # @param css_string [String] CSS to scan for @imports
  # @return [Array<Hash>] Array of import hashes with :url, :media, :full_match
  def self.extract_imports(css_string)
    imports = []

    i = 0
    len = css_string.length

    while i < len
      # Skip whitespace and comments
      while i < len
        byte = css_string.getbyte(i)
        if is_whitespace?(byte)
          i += 1
        elsif i + 1 < len && css_string.getbyte(i) == BYTE_SLASH && css_string.getbyte(i + 1) == BYTE_STAR
          # Skip /* */ comment
          i += 2
          while i + 1 < len && !(css_string.getbyte(i) == BYTE_STAR && css_string.getbyte(i + 1) == BYTE_SLASH)
            i += 1
          end
          i += 2 if i + 1 < len # Skip */
        else
          break
        end
      end

      break if i >= len

      # Check for @import (case-insensitive byte comparison)
      if match_ascii_ci?(css_string, i, '@import')
        import_start = i
        i += 7

        # Skip whitespace after @import
        while i < len && is_whitespace?(css_string.getbyte(i))
          i += 1
        end

        # Check for optional url( (case-insensitive byte comparison)
        has_url_function = false
        if match_ascii_ci?(css_string, i, 'url(')
          has_url_function = true
          i += 4
          while i < len && is_whitespace?(css_string.getbyte(i))
            i += 1
          end
        end

        # Find opening quote
        byte = css_string.getbyte(i) if i < len
        if i >= len || (byte != BYTE_DQUOTE && byte != BYTE_SQUOTE)
          # Invalid @import, skip to next semicolon
          while i < len && css_string.getbyte(i) != BYTE_SEMICOLON
            i += 1
          end
          i += 1 if i < len # Skip semicolon
          next
        end

        quote_char = byte
        i += 1 # Skip opening quote

        url_start = i

        # Find closing quote (handle escaped quotes)
        while i < len && css_string.getbyte(i) != quote_char
          if css_string.getbyte(i) == BYTE_BACKSLASH && i + 1 < len
            i += 2 # Skip escaped character
          else
            i += 1
          end
        end

        break if i >= len # Unterminated string

        url_end = i
        i += 1 # Skip closing quote

        # Skip closing paren if we had url(
        if has_url_function
          while i < len && is_whitespace?(css_string.getbyte(i))
            i += 1
          end
          if i < len && css_string.getbyte(i) == BYTE_RPAREN
            i += 1
          end
        end

        # Skip whitespace before optional media query or semicolon
        while i < len && is_whitespace?(css_string.getbyte(i))
          i += 1
        end

        # Check for optional media query (everything until semicolon)
        media_start = nil
        media_end = nil

        if i < len && css_string.getbyte(i) != BYTE_SEMICOLON
          media_start = i

          # Find semicolon
          while i < len && css_string.getbyte(i) != BYTE_SEMICOLON
            i += 1
          end

          media_end = i

          # Trim trailing whitespace from media query
          while media_end > media_start && is_whitespace?(css_string.getbyte(media_end - 1))
            media_end -= 1
          end
        end

        # Skip semicolon
        i += 1 if i < len && css_string.getbyte(i) == BYTE_SEMICOLON

        import_end = i

        # Build result hash
        url = css_string[url_start...url_end]
        media = media_start && media_end > media_start ? css_string[media_start...media_end] : nil
        full_match = css_string[import_start...import_end]

        imports << { url: url, media: media, full_match: full_match }
      else
        i += 1
      end
    end

    imports
  end

  # Parse media query symbol into array of media types
  #
  # @param media_query_sym [Symbol] Media query as symbol (e.g., :screen, :"print, screen")
  # @return [Array<Symbol>] Array of individual media types
  #
  # @example
  #   parse_media_types(:screen) #=> [:screen]
  #   parse_media_types(:"print, screen") #=> [:print, :screen]
  def self.parse_media_types(media_query_sym)
    query = media_query_sym.to_s
    types = []

    i = 0
    len = query.length

    kwords = %w[and or not only]

    while i < len
      # Skip whitespace
      while i < len && is_whitespace?(query.getbyte(i))
        i += 1
      end
      break if i >= len

      # Check for opening paren - skip conditions like "(min-width: 768px)"
      if query.getbyte(i) == BYTE_LPAREN
        # Skip to matching closing paren
        paren_depth = 1
        i += 1
        while i < len && paren_depth > 0
          byte = query.getbyte(i)
          if byte == BYTE_LPAREN
            paren_depth += 1
          elsif byte == BYTE_RPAREN
            paren_depth -= 1
          end
          i += 1
        end
        next
      end

      # Find end of word (media type or keyword)
      word_start = i
      byte = query.getbyte(i)
      while i < len && !is_whitespace?(byte) && byte != BYTE_COMMA && byte != BYTE_LPAREN && byte != BYTE_COLON
        i += 1
        byte = query.getbyte(i) if i < len
      end

      if i > word_start
        word = query[word_start...i]

        # Check if this is a media feature (followed by ':')
        is_media_feature = (i < len && query.getbyte(i) == BYTE_COLON)

        # Check if it's a keyword (and, or, not, only)
        is_keyword = kwords.include?(word)

        if !is_keyword && !is_media_feature
          # This is a media type - add it as symbol
          types << word.to_sym
        end
      end

      # Skip to comma or end
      while i < len && query.getbyte(i) != BYTE_COMMA
        if query.getbyte(i) == BYTE_LPAREN
          # Skip condition
          paren_depth = 1
          i += 1
          while i < len && paren_depth > 0
            byte = query.getbyte(i)
            if byte == BYTE_LPAREN
              paren_depth += 1
            elsif byte == BYTE_RPAREN
              paren_depth -= 1
            end
            i += 1
          end
        else
          i += 1
        end
      end

      i += 1 if i < len && query.getbyte(i) == BYTE_COMMA # Skip comma
    end

    types
  end
end
