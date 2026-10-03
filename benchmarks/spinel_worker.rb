# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative 'benchmark_formatting'
require_relative 'implementation'
require_relative 'results_directory'
require_relative 'spinel_compiler'

# The worker for the Spinel backend: builds a benchmark's CompiledProgram, runs
# the executable, and records what it measured.
#
# The harness itself - benchmark-ips, JSON, subprocess handling - is not Ruby
# Spinel can compile, and does not need to be. Only the workload is compiled;
# this process is an ordinary Ruby that stands where the other backends'
# workers stand, and writes rows with the keys benchmark-ips writes, so
# combining, speedups and BENCHMARKS.md treat a Spinel row like any other.
class SpinelWorker
  include BenchmarkFormatting

  # What the harness launches, followed by the benchmark's name, the
  # program's source and the program's own arguments.
  SCRIPT = __FILE__

  # Root that `require "cataract"` resolves against: the local development
  # version, not an installed gem.
  LOAD_PATH = File.expand_path('../lib', __dir__)

  IMPLEMENTATION = Implementation.find(:spinel, :none)

  class Mismatch < StandardError
  end

  # Turns an executable's output (see benchmarks/spinel/measure.rb) into result
  # rows. Raises rather than label as Spinel's a run that says it was
  # something else, as Implementation.current does for the other backends.
  #
  # @param output [String] the executable's stdout
  # @return [Array<Hash>] rows in benchmark-ips's JSON shape, stamped with the
  #   implementation's result fields
  def self.rows(output, implementation: IMPLEMENTATION)
    lines = output.lines.map { |line| line.chomp.split("\t") }
    engine = lines.find { |fields| fields.first == 'engine' }&.last

    unless engine == 'spinel'
      raise Mismatch, "expected a program compiled by Spinel but it reports RUBY_ENGINE #{engine.inspect}"
    end

    lines.select { |fields| fields.first == 'result' }.map { |fields| row(fields.drop(1), implementation) }
  end

  def self.row(fields, implementation)
    id, rate, stddev, iterations, per_cycle, seconds = fields

    {
      'name' => "#{implementation.backend.label}: #{id}",
      'central_tendency' => rate.to_f,
      'ips' => rate.to_f,
      'error' => stddev.to_f,
      'stddev' => stddev.to_f,
      'microseconds' => seconds.to_f * 1_000_000,
      'iterations' => iterations.to_i,
      'cycles' => per_cycle.to_i
    }.merge(implementation.result_fields, 'jit_stats' => {})
  end

  # @param benchmark_name [String] names the result file, e.g. "parsing"
  # @param source [String] the program's entry file
  # @param args [Array<String>] arguments the executable is run with
  def initialize(benchmark_name:, source:, args:, results: ResultsDirectory.from_env(ENV),
                 compiler: SpinelCompiler.locate(ENV))
    @benchmark_name = benchmark_name
    @source = source
    @args = args
    @results = results
    @compiler = compiler
  end

  def run
    raise SpinelCompiler::CompileError, 'no Spinel compiler found (set SPINEL or SPINEL_DIR)' unless @compiler

    Dir.mktmpdir('cataract-spinel') do |dir|
      puts "Compiling #{File.basename(@source)} with #{@compiler.version}"
      executable = @compiler.compile(@source, output: File.join(dir, @benchmark_name), load_path: LOAD_PATH)

      rows = self.class.rows(execute(executable))
      raise "#{File.basename(@source)} reported no measurements" if rows.empty?

      @results.create.write("#{@benchmark_name}_#{IMPLEMENTATION.id}.json", rows)
    end
  end

  private

  # Runs the executable to completion, echoing each measurement as it lands so
  # a benchmark that takes a minute isn't silent.
  def execute(executable)
    output = +''

    Open3.popen2(executable, *@args) do |stdin, stdout, wait_thr|
      stdin.close
      stdout.each_line do |line|
        output << line
        announce(line)
      end

      status = wait_thr.value
      raise "#{File.basename(@source)} #{describe(status)}" unless status.success?
    end

    output
  end

  def announce(line)
    fields = line.chomp.split("\t")
    return unless fields.first == 'result'

    row = self.class.row(fields.drop(1), IMPLEMENTATION)
    puts "#{row['name'].ljust(48)} #{format_ips(row)}"
  end

  def describe(status)
    status.signaled? ? "was killed by signal #{status.termsig}" : "exited #{status.exitstatus}"
  end
end

if __FILE__ == $PROGRAM_NAME
  benchmark_name, source, *args = ARGV
  abort "usage: #{File.basename(__FILE__)} <benchmark name> <program.rb> [args...]" unless benchmark_name && source

  begin
    SpinelWorker.new(benchmark_name: benchmark_name, source: source, args: args).run
  rescue StandardError => e
    # stderr and a non-zero exit, which is what the harness reads to explain
    # why a variant died.
    warn "❌ Benchmark failed: #{e.message}"
    exit 1
  end
end
