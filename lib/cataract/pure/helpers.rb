# frozen_string_literal: true

# Pure Ruby CSS parser - Helper methods
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  # Check if a byte is whitespace (space, tab, newline, CR)
  # @param byte [Integer] Byte value from String#getbyte
  # @return [Boolean] true if whitespace
  def self.is_whitespace?(byte)
    byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR
  end

  # Check if byte is a letter (a-z, A-Z)
  # @param byte [Integer] Byte value from String#getbyte
  # @return [Boolean] true if letter
  def self.letter?(byte)
    (byte >= BYTE_LOWER_A && byte <= BYTE_LOWER_Z) ||
    (byte >= BYTE_UPPER_A && byte <= BYTE_UPPER_Z)
  end

  # Check if byte is a digit (0-9)
  # @param byte [Integer] Byte value from String#getbyte
  # @return [Boolean] true if digit
  def self.digit?(byte)
    byte >= BYTE_DIGIT_0 && byte <= BYTE_DIGIT_9
  end

  # Check if byte is alphanumeric, hyphen, or underscore (CSS identifier char)
  # @param byte [Integer] Byte value from String#getbyte
  # @return [Boolean] true if valid identifier character
  def self.ident_char?(byte)
    letter?(byte) || digit?(byte) || byte == BYTE_HYPHEN || byte == BYTE_UNDERSCORE
  end
end
