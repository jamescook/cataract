# frozen_string_literal: true

# Timing for a benchmark compiled by Spinel.
#
# benchmark-ips cannot be compiled, so this does the same job in Ruby that
# can: run the workload for a warm-up period, then count iterations in cycles
# of about 100ms for a fixed time, and report the mean rate across the cycles
# and its standard deviation. One line per test case goes to stdout, tab
# separated, for benchmarks/spinel_worker.rb to turn into a result row:
#
#   result <id> <iterations/s> <stddev> <iterations> <iterations per cycle> <seconds>
#
# Everything here also runs under CRuby, which is how the output format is
# tested without a compiler.
module SpinelBench
  CYCLE_SECONDS = 0.1

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Says what produced the lines that follow, so the worker can refuse to
  # label an interpreter's numbers as Spinel's.
  def self.header
    puts "engine\t#{RUBY_ENGINE}"
  end

  # @param id [String] test case id, matching the benchmark's metadata
  # @param warmup [Float] seconds to run before measuring
  # @param time [Float] seconds to measure for
  def self.measure(id, warmup, time)
    warmup_iterations = 0
    warmup_start = now
    loop do
      yield
      warmup_iterations += 1
      break if now - warmup_start >= warmup
    end

    warmup_elapsed = now - warmup_start
    per_cycle = warmup_elapsed.positive? ? (warmup_iterations * CYCLE_SECONDS / warmup_elapsed).to_i : 1
    per_cycle = 1 if per_cycle < 1

    iterations = 0
    cycles = 0
    sum = 0.0
    sum_of_squares = 0.0
    start = now
    while now - start < time
      cycle_start = now
      i = 0
      while i < per_cycle
        yield
        i += 1
      end
      rate = per_cycle / (now - cycle_start)

      sum += rate
      sum_of_squares += rate * rate
      iterations += per_cycle
      cycles += 1
    end
    elapsed = now - start

    mean = sum / cycles
    variance = (sum_of_squares / cycles) - (mean * mean)
    stddev = variance.positive? ? Math.sqrt(variance) : 0.0

    puts "result\t#{id}\t#{mean}\t#{stddev}\t#{iterations}\t#{per_cycle}\t#{elapsed}"
  end
end
