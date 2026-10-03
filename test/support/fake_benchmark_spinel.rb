# frozen_string_literal: true

# The fake benchmark worker's one test case as a program Spinel can compile -
# what fake_benchmark_worker.rb is to the Ruby backends. Measures nothing
# meaningful, as briefly as it can: it exists to exercise the harness.
require_relative '../../benchmarks/spinel/measure'

SpinelBench.header
SpinelBench.measure('tiny', 0.0, 0.01) { 1 + 1 }
