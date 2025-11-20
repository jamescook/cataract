# frozen_string_literal: true

module Cataract
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
