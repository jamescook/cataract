require_relative 'cataract/version'
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/parser'
require 'cataract/cataract' # Load the C extension

module Cataract
  # Convenience method for quick parsing
  def self.parse(css_string, options = {})
    parser = Parser.new(options)
    parser.parse(css_string)
    parser
  end
end
