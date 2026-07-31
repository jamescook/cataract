# frozen_string_literal: true

# Preloaded with `ruby -r` ahead of a benchmark script to answer one question:
# does running this file actually start a benchmark?
#
# Replacing .run means the answer comes back in milliseconds instead of by
# letting the real benchmark run. A script that defines its class but never
# invokes it prints nothing.
require_relative '../../benchmarks/benchmark_harness'

class BenchmarkHarness
  class << self
    def run(*, **)
      puts "ENTRYPOINT #{name}"
      exit 0
    end
  end
end
