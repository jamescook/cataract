# Load SimpleCov for code coverage when COVERAGE env var is set
if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'

  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

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
