# frozen_string_literal: true

require 'benchmark/ips'
require 'json'
require 'fileutils'
require 'open3'
require_relative 'system_metadata'
require_relative 'speedup_calculator'
require_relative 'implementation'
require_relative 'results_directory'

# Base class for all benchmarks. Provides structure and automatic JSON output.
#
# Usage:
#   class MyBenchmark < BenchmarkHarness
#     def self.benchmark_name
#       'my_benchmark'
#     end
#
#     def self.description
#       'What this benchmark measures'
#     end
#
#     def self.metadata
#       { 'key' => 'value' } # Optional metadata for docs
#     end
#
#     def self.sanity_checks
#       # Optional: verify code works before benchmarking
#       raise "Sanity check failed!" unless something_works
#     end
#
#     def self.call
#       run_test_case_1
#       run_test_case_2
#     end
#
#     private
#
#     def self.run_test_case_1
#       benchmark('test_case_1') do |x|
#         x.config(time: 5, warmup: 2)
#         x.report('label') { ... }
#         x.compare!
#       end
#     end
#   end
#
# Why benchmarks that compare native vs pure Ruby (benchmark_parsing.rb and
# siblings) spawn a separate `ruby` subprocess per implementation instead of
# just requiring both backends and measuring them back-to-back in one
# process: Stylesheet#add_block calls @backend.parse(...) - one call site
# shared by both backends. Under YJIT, warming that call site up for one
# backend first measurably slows down the OTHER backend's dispatch through
# the now-polymorphic inline cache once it's called there too - confirmed
# empirically as a ~2.3x regression for pure Ruby specifically when measured
# in-process right after native, with NO such effect running each in its own
# process (or with YJIT disabled entirely, where in-process measurement is
# actually fine). Since these benchmarks need accurate YJIT-enabled numbers,
# not just YJIT-disabled ones, per-implementation subprocess isolation stays
# even though it could technically be done in-process.
class BenchmarkHarness
  # Where this run's result JSON lives. Passed in rather than looked up, so a
  # test can redirect it without touching global state.
  attr_reader :results

  def initialize(results:)
    @results = results
  end

  class << self
    # Abstract methods - must be implemented by subclasses
    def benchmark_name
      raise NotImplementedError, "#{self} must implement .benchmark_name"
    end

    def description
      raise NotImplementedError, "#{self} must implement .description"
    end

    def metadata
      {} # Optional, can be overridden
    end

    def sanity_checks
      # Optional, can be overridden
    end

    def call
      raise NotImplementedError, "#{self} must implement .call"
    end

    # The pair compared by the headline "speedups" figure in this benchmark's
    # metadata. Both sides run without a JIT, isolating the C extension's
    # advantage from anything a JIT contributed.
    #
    # @return [Hash] { baseline: Implementation, comparison: Implementation }
    def speedup_config
      {
        baseline: Implementation.find(:pure, :none),
        comparison: Implementation.find(:native, :none)
      }
    end

    # Main entry point - handles setup, execution, and cleanup
    def run(skip_finalize: false, results: ResultsDirectory.from_env(ENV))
      instance = new(results: results)
      setup(results)
      instance.sanity_checks if instance.respond_to?(:sanity_checks, true)

      # Warm up the VM before benchmarking for stable, reproducible results
      # This runs a major GC, compacts the heap, promotes objects to old gen,
      # and prepares YJIT/internal state for optimal performance
      # https://docs.ruby-lang.org/en/master/Process.html#method-c-warmup
      Process.warmup

      instance.call
      finalize(instance) unless skip_finalize
    rescue StandardError => e
      puts "❌ Benchmark failed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end

    # Fills in metadata['speedups'] (and each test case's own 'speedup') from
    # the pair named by speedup_config.
    def annotate_speedups(combined_data)
      config = speedup_config
      return unless config

      stats = SpeedupCalculator.new(
        results: combined_data['results'],
        test_cases: combined_data['metadata']['test_cases'],
        baseline: config[:baseline],
        comparison: config[:comparison]
      ).calculate

      combined_data['metadata']['speedups'] = stats if stats
    end

    private

    def setup(results)
      results.create

      # Always refresh - each of the 4 benchmark scripts runs in its own
      # subprocess, so metadata.json existing doesn't mean it reflects THIS
      # run's Ruby version/machine. Previously guarded with `unless
      # File.exist?(...)`, which meant metadata.json was captured once ever
      # (whatever machine/Ruby version happened to run the very first
      # benchmark) and then silently never refreshed again - BENCHMARKS.md
      # kept reporting a Ruby version and date from months earlier while the
      # actual numbers below it came from whatever's currently installed.
      # The four sysctl/sw_vers shell calls this costs per full `rake
      # benchmark` run are cheap; a stale, silently-wrong header is not.
      SystemMetadata.collect(results)

      # Print header
      puts "\n\n"
      puts '=' * 80
      puts "#{benchmark_name.upcase.tr('_', ' ')} BENCHMARK"
      puts "Measures: #{description}"
      puts '=' * 80
      puts
    end

    def finalize(instance)
      # Combine all JSON files for this benchmark into one
      return unless instance.instance_variable_defined?(:@json_files) && instance.instance_variable_get(:@json_files)&.any?

      json_files = instance.instance_variable_get(:@json_files)

      combined_data = {
        'name' => benchmark_name,
        'description' => description,
        'metadata' => metadata,
        'timestamp' => Time.now.iso8601,
        'results' => []
      }

      # Read all the individual JSON files
      json_files.each do |filename|
        next unless instance.results.exist?(filename)

        data = instance.results.read(filename)
        combined_data['results'].concat(data) if data.is_a?(Array)
      end

      annotate_speedups(combined_data)

      # Write combined file
      combined_file = "#{benchmark_name}.json"
      instance.results.write(combined_file, combined_data)

      # Clean up individual files
      json_files.each { |filename| File.delete(instance.results.join(filename)) }

      puts "\n✓ Results saved to #{instance.results.join(combined_file)}"
    end
  end

  # Instance methods

  # Default instance method that falls back to class method
  # Can be overridden by modules like WorkerHelpers
  def benchmark_name
    self.class.benchmark_name
  end

  protected

  def benchmark(test_case_name)
    json_filename = "#{benchmark_name}_#{test_case_name}.json"
    json_path = results.join(json_filename)

    Benchmark.ips do |x|
      # Automatically enable JSON output
      x.json!(json_path)

      # Let the benchmark configure and run
      yield x
    end

    # Tag each measurement with the implementation that produced it and the
    # JIT stats at that point. Stats are cumulative for the process, so the
    # last test case's snapshot is the run's total.
    if File.exist?(json_path) && respond_to?(:implementation) && implementation
      fields = implementation.result_fields.merge('jit_stats' => implementation.mode.stats)
      results = JSON.parse(File.read(json_path))
      results.each { |result| result.merge!(fields) }
      File.write(json_path, JSON.pretty_generate(results))
    end

    # Track that we created this file
    @json_files ||= []
    @json_files << json_filename
  end

  # Helper to read and combine worker result files
  # Worker files are raw arrays from benchmark-ips, not hashes with 'results' key
  def read_worker_results(pattern)
    worker_paths = results.glob(pattern)
    raise 'No worker results found' if worker_paths.empty?

    all_results = []
    worker_paths.each do |path|
      data = JSON.parse(File.read(path))
      all_results.concat(data.is_a?(Array) ? data : data['results'])
    end
    all_results
  end

  # Helper to clean up worker result files
  def cleanup_worker_results(pattern)
    results.delete(pattern)
  end

  def announce_variants
    puts "Running #{self.class.benchmark_name} benchmarks via subprocesses..."
    puts "Variants: #{Implementation.available.map(&:label).join(', ')}"
    puts
  end

  # Runs a worker script once per Implementation, each in its own process,
  # then merges their output into this benchmark's combined results file.
  def run_all_variants(worker_script)
    cleanup_worker_results(worker_glob)

    Implementation.available.each do |implementation|
      puts "→ Running #{implementation}..."
      puts
      # Workers write into the same directory as their parent, so a redirected
      # results location survives the process boundary.
      env = implementation.env.merge(results.env)
      _, status = run_subprocess(implementation.ruby_command(worker_script), env: env)
      raise "#{implementation} benchmark failed" unless status.success?

      puts
      puts
    end

    combine_worker_results
  end

  private

  def worker_glob
    "#{self.class.benchmark_name}_*.json"
  end

  def run_subprocess(command, env: {})
    stdout_lines = []

    Open3.popen3(env, *command) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      # Stream both streams as they arrive so a long benchmark isn't silent
      readers = [
        Thread.new do
          stdout.each_line do |line|
            puts line
            stdout_lines << line
          end
        end,
        Thread.new { stderr.each_line { |line| warn "⚠️  #{line}" } }
      ]
      readers.each(&:join)

      return [stdout_lines.join, wait_thr.value]
    end
  end

  def combine_worker_results
    combined = {
      'name' => self.class.benchmark_name,
      'description' => self.class.description,
      'metadata' => self.class.metadata,
      'results' => read_worker_results(worker_glob)
    }
    self.class.annotate_speedups(combined)

    combined_file = "#{self.class.benchmark_name}.json"
    results.write(combined_file, combined)
    cleanup_worker_results(worker_glob)

    puts '=' * 80
    puts "✓ All #{self.class.benchmark_name} benchmarks complete"
    puts "Results saved to: #{results.join(combined_file)}"
    puts '=' * 80
  end
end
