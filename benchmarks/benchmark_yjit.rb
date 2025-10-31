# frozen_string_literal: true

require_relative 'benchmark_harness'
require 'open3'
require 'json'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# YJIT Benchmark Supervisor
# Spawns two subprocesses (with/without YJIT) and combines results
class YjitBenchmark < BenchmarkHarness
  def self.benchmark_name
    'yjit'
  end

  def self.description
    'Ruby-side operations with and without YJIT'
  end

  def self.metadata
    {
      'operations' => [
        'property access',
        'declaration merging',
        'to_s generation',
        'parse + iterate'
      ],
      'note' => 'C extension performance is the same regardless of YJIT. This measures Ruby code.'
    }
  end

  def self.speedup_config
    # Compare without YJIT (baseline) vs with YJIT (comparison)
    {
      baseline_matcher: SpeedupCalculator::Matchers.without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.with_yjit,
      test_case_key: nil # No test_cases array, just operations
    }
  end

  def sanity_checks
    # Verify basic operations work
    decls = Cataract::Declarations.new
    decls['color'] = 'red'
    raise 'Property access failed' unless decls['color']

    parser = Cataract::Parser.new
    sample_css = 'body { margin: 0; }'
    parser.parse(sample_css)
    raise 'Parse failed' if parser.rules_count.zero?
  end

  def call
    worker_script = File.expand_path('benchmark_yjit_workers.rb', __dir__)

    # Clean up any leftover worker files from previous runs
    without_path = File.join(RESULTS_DIR, 'yjit_without.json')
    with_path = File.join(RESULTS_DIR, 'yjit_with.json')
    FileUtils.rm_f(without_path)
    FileUtils.rm_f(with_path)

    puts 'Running YJIT benchmarks via subprocesses...'
    puts

    # Run without YJIT
    puts '→ Running without YJIT (--disable-yjit)...'
    stdout_without, status_without = run_subprocess(['ruby', '--disable-yjit', worker_script])
    unless status_without.success?
      raise "Worker without YJIT failed:\n#{stdout_without}"
    end

    puts stdout_without
    puts

    # Run with YJIT
    puts '→ Running with YJIT (--yjit)...'
    stdout_with, status_with = run_subprocess(['ruby', '--yjit', worker_script])
    unless status_with.success?
      raise "Worker with YJIT failed:\n#{stdout_with}"
    end

    puts stdout_with
    puts

    # Combine results
    combine_worker_results
  end

  private

  def run_subprocess(command)
    stdout, stderr, status = Open3.capture3(*command)

    # Print stderr if present (warnings, etc)
    unless stderr.empty?
      puts "⚠️  stderr: #{stderr}"
    end

    [stdout, status]
  end

  def combine_worker_results
    without_path = File.join(RESULTS_DIR, 'yjit_without.json')
    with_path = File.join(RESULTS_DIR, 'yjit_with.json')

    # Check both files exist
    unless File.exist?(without_path) && File.exist?(with_path)
      raise "Worker results not found:\n  #{without_path}\n  #{with_path}"
    end

    # Read both JSON files
    without_data = JSON.parse(File.read(without_path))
    with_data = JSON.parse(File.read(with_path))

    # Combine into single benchmark result
    combined_data = {
      'name' => self.class.benchmark_name,
      'description' => self.class.description,
      'metadata' => self.class.metadata,
      'timestamp' => Time.now.iso8601,
      'results' => []
    }

    # Merge results from both workers
    combined_data['results'].concat(without_data['results']) if without_data['results']
    combined_data['results'].concat(with_data['results']) if with_data['results']

    # Calculate speedups using configured strategy
    config = self.class.speedup_config
    if config
      calculator = SpeedupCalculator.new(
        results: combined_data['results'],
        test_cases: combined_data['metadata']['operations'],
        baseline_matcher: config[:baseline_matcher],
        comparison_matcher: config[:comparison_matcher],
        test_case_key: config[:test_case_key]
      )

      speedup_stats = calculator.calculate
      combined_data['metadata']['speedups'] = speedup_stats if speedup_stats
    end

    # Write combined file
    combined_path = File.join(RESULTS_DIR, "#{self.class.benchmark_name}.json")
    File.write(combined_path, JSON.pretty_generate(combined_data))

    # Clean up worker files
    File.delete(without_path)
    File.delete(with_path)

    puts "✓ Combined results saved to #{combined_path}"
  end
end

# Run if executed directly
YjitBenchmark.run if __FILE__ == $PROGRAM_NAME
