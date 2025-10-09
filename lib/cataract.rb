require_relative 'cataract/version'
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/parser'

begin
  # Try to load the C extension first
  require 'cataract/cataract'
  CATARACT_C_EXT = true
rescue LoadError
  # Fall back to pure Ruby implementation
  CATARACT_C_EXT = false
  require_relative 'cataract/pure_ruby_parser'
end

module Cataract
  # Convenience method for quick parsing
  def self.parse(css_string, options = {})
    parser = Parser.new(options)
    parser.parse(css_string)
    parser
  end
end
