# This file is deprecated - benchmarks have been split into separate files
#
# Run benchmarks with:
#   rake benchmark              # Run all benchmarks
#   rake benchmark:parsing      # Run parsing benchmarks only
#   rake benchmark:specificity  # Run specificity benchmarks only
#
# See:
#   test/benchmarks/benchmark_parsing.rb
#   test/benchmarks/benchmark_specificity.rb

require_relative 'benchmarks/benchmark_parsing'
require_relative 'benchmarks/benchmark_specificity'

puts "="*60
puts "DEPRECATED: This file is deprecated"
puts "Run 'rake benchmark' to run all benchmarks"
puts "="*60
puts

BenchmarkParsing.run
puts "\n"
BenchmarkSpecificity.run
