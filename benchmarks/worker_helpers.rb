# frozen_string_literal: true

require_relative 'implementation'

# Mixed into the worker benchmark classes that run inside a subprocess.
#
# The worker reads its backend and JIT off the running VM and verifies them
# against what the parent asked for, so measurements can only be labeled with
# the configuration that produced them.
module WorkerHelpers
  # This process's configuration. Verified on first use, before any
  # measurement is taken.
  def implementation
    @implementation ||= Implementation.current
  end

  # Gives each variant its own result file so the JIT runs of one benchmark
  # don't overwrite each other.
  def benchmark_name
    "#{self.class.benchmark_name}_#{implementation.id}"
  end

  # Names a benchmark-ips report "label: test_case_id". The id must match the
  # benchmark metadata exactly - that is how a measurement finds its row in
  # BENCHMARKS.md. The label names only the backend; the JIT is recorded in
  # the row's own fields.
  def result_name(test_case_id)
    "#{implementation.backend.label}: #{test_case_id}"
  end
end
