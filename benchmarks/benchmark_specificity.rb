# frozen_string_literal: true

require_relative 'benchmark_harness'
require 'open3'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Specificity Calculation Benchmark
# Compares css_parser gem vs Cataract pure Ruby vs Cataract C extension
class SpecificityBenchmark < BenchmarkHarness
  def self.benchmark_name
    'specificity'
  end

  def self.description
    'Time to calculate CSS selector specificity values'
  end

  def self.metadata
    require_relative 'specificity_tests'
    SpecificityTests.metadata
  end

  def self.speedup_config
    require_relative 'specificity_tests'
    SpecificityTests.speedup_config
  end

  def sanity_checks
    # Verify css_parser gem is available
    require 'css_parser'

    # Verify both libraries work
    raise 'css_parser sanity check failed' unless CssParser.calculate_specificity('div') == 1
    raise 'Cataract sanity check failed' unless Cataract.calculate_specificity('div') == 1
  end

  def call
    require_relative 'specificity_tests'

    worker_script = File.expand_path('benchmark_specificity_workers.rb', __dir__)

    # Clean up any leftover worker files from previous runs
    Dir.glob(File.join(RESULTS_DIR, 'specificity_*.json')).each { |f| FileUtils.rm_f(f) }

    puts 'Running specificity benchmarks via subprocesses...'
    puts 'Testing implementations with YJIT variations where applicable'
    puts

    # Define implementations to test
    implementations = [
      { name: 'css_parser gem', base_impl: :css_parser, env: { 'SPECIFICITY_CSS_PARSER' => '1' } },
      { name: 'Cataract pure Ruby', base_impl: :pure, env: { 'CATARACT_PURE' => '1' } },
      { name: 'Cataract C extension', base_impl: :native, env: { 'CATARACT_PURE' => nil } }
    ]

    implementations.each do |config|
      if SpecificityTests.yjit_applicable?(config[:base_impl])
        # Run both YJIT variants
        puts "→ Running #{config[:name]} without YJIT..."
        puts
        stdout, status = run_subprocess(['ruby', '--disable-yjit', worker_script], env: config[:env])
        raise "#{config[:name]} (no YJIT) benchmark failed" unless status.success?
        puts
        puts

        puts "→ Running #{config[:name]} with YJIT..."
        puts
        stdout, status = run_subprocess(['ruby', '--yjit', worker_script], env: config[:env])
        raise "#{config[:name]} (YJIT) benchmark failed" unless status.success?
        puts
        puts
      else
        # Run without YJIT flags (YJIT not applicable)
        puts "→ Running #{config[:name]}..."
        puts
        stdout, status = run_subprocess(['ruby', worker_script], env: config[:env])
        raise "#{config[:name]} benchmark failed" unless status.success?
        puts
        puts
      end
    end

    # Combine results
    combine_worker_results
  end

  private

  def run_subprocess(command, env: {})
    stdout_lines = []

    Open3.popen3(env, *command) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      # Stream output in real-time
      threads = []

      # Thread for stdout
      threads << Thread.new do
        stdout.each_line do |line|
          puts line
          stdout_lines << line
        end
      end

      # Thread for stderr
      threads << Thread.new do
        stderr.each_line do |line|
          warn "⚠️  #{line}"
        end
      end

      # Wait for all output to be read
      threads.each(&:join)

      # Get exit status
      status = wait_thr.value

      return [stdout_lines.join, status]
    end
  end

  def combine_worker_results
    # Read all worker result files
    all_results = read_worker_results('specificity_*.json')

    # Combine into single result
    combined = {
      'name' => self.class.benchmark_name,
      'description' => self.class.description,
      'metadata' => self.class.metadata,
      'results' => all_results
    }

    # Calculate speedups using configured strategy
    require_relative 'speedup_calculator'
    config = self.class.speedup_config
    if config
      calculator = SpeedupCalculator.new(
        results: combined['results'],
        test_cases: combined['metadata']['test_cases'],
        baseline_matcher: config[:baseline_matcher],
        comparison_matcher: config[:comparison_matcher],
        test_case_key: config[:test_case_key]
      )

      speedup_stats = calculator.calculate
      combined['metadata']['speedups'] = speedup_stats if speedup_stats
    end

    # Write combined results
    combined_path = File.join(RESULTS_DIR, "#{self.class.benchmark_name}.json")
    File.write(combined_path, JSON.pretty_generate(combined))

    # Clean up worker files
    cleanup_worker_results('specificity_*.json')

    puts '=' * 80
    puts '✓ All specificity benchmarks complete'
    puts "Results saved to: #{combined_path}"
    puts '=' * 80
  end
end

# Run if executed directly
SpecificityBenchmark.run if __FILE__ == $PROGRAM_NAME
