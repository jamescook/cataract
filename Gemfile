# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in cataract.gemspec
gemspec

# Build dependencies
gem 'rake', '~> 13.0'
gem 'rake-compiler', '~> 1.0'

# Development/benchmarking dependencies (not needed by gem users)
gem 'addressable', '~> 2.8' # for custom URI resolver testing
gem 'benchmark-ips', '~> 2.0'
gem 'css_parser', '~> 1.0' # for benchmarking against
gem 'minitest'
gem 'minitest-spec'
gem 'nokogiri' # for docs
gem 'simplecov', require: false
gem 'simplecov-cobertura', require: false
gem 'webmock', '~> 3.0' # for testing URL loading

# Profiling gems (not supported on JRuby)
platforms :ruby do
  gem 'ruby-prof', require: false # for profiling
  gem 'stackprof', require: false # for profiling
end

gem 'overcommit', '~> 0.64', group: :development
gem 'premailer'
gem 'rubocop', '~> 1.81', group: :development
gem 'rubocop-minitest', '~> 0.38.2', group: :development
gem 'rubocop-performance', '~> 1.26', group: :development

gem 'yard', '~> 0.9', group: :development
