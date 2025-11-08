# frozen_string_literal: true

# Load SimpleCov for code coverage when COVERAGE env var is set
if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'

  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                                    SimpleCov::Formatter::HTMLFormatter,
                                                                    SimpleCov::Formatter::CoberturaFormatter
                                                                  ])

  SimpleCov.start do
    add_filter '/test/'
    add_filter '/benchmarks/'

    # Group coverage by component
    add_group 'Parser', 'lib/cataract/parser.rb'
    add_group 'RuleSet', 'lib/cataract/rule_set.rb'
    add_group 'Declarations', 'lib/cataract/declarations.rb'
  end
end

require 'minitest/autorun'
require 'cataract'
require 'cataract/color_conversion' # Load color conversion extension for tests

# Load test helpers
require_relative 'support/stylesheet_test_helper'

# Include helpers in all test classes
module Minitest
  class Test
    include StylesheetTestHelper
  end
end
