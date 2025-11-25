# frozen_string_literal: true

# Pure Ruby CSS parser - Byte constants for fast parsing
# Using getbyte() instead of String#[] to avoid allocating millions of string objects

module Cataract
  # Whitespace bytes
  BYTE_SPACE     = 32  # ' '
  BYTE_TAB       = 9   # '\t'
  BYTE_NEWLINE   = 10  # '\n'
  BYTE_CR        = 13  # '\r'

  # CSS structural characters
  BYTE_AT        = 64  # '@'
  BYTE_LBRACE    = 123 # '{'
  BYTE_RBRACE    = 125 # '}'
  BYTE_LPAREN    = 40  # '('
  BYTE_RPAREN    = 41  # ')'
  BYTE_LBRACKET  = 91  # '['
  BYTE_RBRACKET  = 93  # ']'
  BYTE_SEMICOLON = 59  # ';'
  BYTE_COLON     = 58  # ':'
  BYTE_COMMA     = 44  # ','

  # Comment characters
  BYTE_SLASH     = 47  # '/'
  BYTE_STAR      = 42  # '*'

  # Quote characters
  BYTE_SQUOTE    = 39  # "'"
  BYTE_DQUOTE    = 34  # '"'

  # Selector characters
  BYTE_HASH      = 35  # '#'
  BYTE_DOT       = 46  # '.'
  BYTE_GT        = 62  # '>'
  BYTE_PLUS      = 43  # '+'
  BYTE_TILDE     = 126 # '~'
  BYTE_ASTERISK  = 42  # '*'
  BYTE_AMPERSAND = 38  # '&'

  # Other
  BYTE_HYPHEN     = 45 # '-'
  BYTE_UNDERSCORE = 95 # '_'
  BYTE_BACKSLASH  = 92 # '\\'
  BYTE_BANG       = 33 # '!'
  BYTE_PERCENT    = 37 # '%'
  BYTE_SLASH_FWD  = 47 # '/' (also defined as BYTE_SLASH above)
  BYTE_EQUALS     = 61 # '='
  BYTE_CARET      = 94 # '^'
  BYTE_DOLLAR     = 36 # '$'
  BYTE_PIPE       = 124 # '|'

  # Specific lowercase letters (for keyword matching)
  BYTE_LOWER_U    = 117 # 'u'
  BYTE_LOWER_R    = 114 # 'r'
  BYTE_LOWER_L    = 108 # 'l'
  BYTE_LOWER_D    = 100 # 'd'
  BYTE_LOWER_T    = 116 # 't'
  BYTE_LOWER_N    = 110 # 'n'

  # Specific uppercase letters (for case-insensitive matching)
  BYTE_UPPER_U    = 85  # 'U'
  BYTE_UPPER_R    = 82  # 'R'
  BYTE_UPPER_L    = 76  # 'L'
  BYTE_UPPER_D    = 68  # 'D'
  BYTE_UPPER_T    = 84  # 'T'
  BYTE_UPPER_N    = 78  # 'N'

  # Letter ranges (a-z, A-Z)
  BYTE_LOWER_A   = 97  # 'a'
  BYTE_LOWER_Z   = 122 # 'z'
  BYTE_UPPER_A   = 65  # 'A'
  BYTE_UPPER_Z   = 90  # 'Z'
  BYTE_CASE_DIFF = 32  # Difference between lowercase and uppercase ('a' - 'A')

  # Digit range (0-9)
  BYTE_DIGIT_0   = 48  # '0'
  BYTE_DIGIT_9   = 57  # '9'

  # Nesting styles (for CSS nesting support)
  NESTING_STYLE_IMPLICIT = 0  # Implicit nesting: .parent { .child { ... } } => .parent .child
  NESTING_STYLE_EXPLICIT = 1  # Explicit nesting: .parent { &:hover { ... } } => .parent:hover
end
