# frozen_string_literal: true

module Cataract
  class Error < StandardError; end

  # Error raised during import resolution
  class ImportError < Error; end

  # Parsing errors
  class DepthError < Error; end
  class SizeError < Error; end
  # Internal parser consistency errors
  class ParserError < Error; end

  # Error raised when invalid CSS is encountered in strict mode
  class ParseError < Error
    attr_reader :line, :column, :error_type

    # @param message [String] Error message (without position info)
    # @param css [String, nil] Full CSS string for calculating position
    # @param pos [Integer, nil] Byte position in CSS where error occurred
    # @param line [Integer, nil] Line number (if already calculated)
    # @param column [Integer, nil] Column number (if already calculated)
    # @param type [Symbol, nil] Type of parse error (:empty_value, :malformed_declaration, etc.)
    def initialize(message, css: nil, pos: nil, line: nil, column: nil, type: nil)
      # Calculate line/column from css and pos if provided
      if css && pos
        @line = css.byteslice(0, pos).count("\n") + 1
        line_start = css.rindex("\n", pos - 1)
        @column = line_start ? pos - line_start : pos + 1
      else
        @line = line
        @column = column
      end

      @error_type = type

      # Build message with position info
      full_message = if @line && @column
                       "#{message} at line #{@line}, column #{@column}"
                     elsif @line
                       "#{message} at line #{@line}"
                     else
                       message
                     end

      super(full_message)
    end
  end
end
