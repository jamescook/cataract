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
if ENV['CATARACT_PURE'].nil?
  require 'cataract/color_conversion' # Load color conversion extension for tests
end

# ssrf_filter (used by ImportResolver to guard @import / load_uri http(s)
# fetches against SSRF) resolves hostnames via Resolv.getaddresses *before*
# webmock's stubs ever come into play - webmock only intercepts the HTTP
# request itself. Real DNS isn't available in sandboxed/CI test runs, so give
# the example.com test domain (used throughout the import/load_uri specs) a
# fixed, real public IP instead of hitting the network. Anything else -
# including IP literals like 127.0.0.1, which Resolv resolves instantly with
# no network call - falls through to the real implementation unchanged.
require 'resolv'

class Resolv
  class << self
    alias real_getaddresses getaddresses

    def getaddresses(hostname)
      return ['93.184.216.34'] if hostname == 'example.com' || hostname.end_with?('.example.com')

      real_getaddresses(hostname)
    end
  end
end

# Load test helpers
require_relative 'support/stylesheet_test_helper'
require_relative 'support/color_conversion_test_helper'

# Include helpers in all test classes
module Minitest
  class Test
    include StylesheetTestHelper
    include ColorConversionTestHelper
  end
end
