require_relative 'cataract/version'
require_relative 'cataract/rule_set'
require_relative 'cataract/declarations'
require_relative 'cataract/parser'
require 'cataract/cataract'

module Cataract
  def self.parse(css_string, options = {})
    parser = Parser.new(options)
    parser.parse(css_string)
    parser
  end
end
