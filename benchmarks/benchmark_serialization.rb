# frozen_string_literal: true

require_relative 'benchmark_harness'
require 'open3'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Serialization Performance Benchmark
# Compares css_parser gem vs Cataract pure Ruby vs Cataract C extension
class SerializationBenchmark < BenchmarkHarness
  def self.benchmark_name
    'serialization'
  end

  def self.description
    'Time to convert parsed CSS back to string format'
  end

  def self.metadata
    require_relative 'serialization_tests'
    SerializationTests.metadata
  end

  def self.speedup_config
    require_relative 'serialization_tests'
    SerializationTests.speedup_config
  end

  def sanity_checks
    # Verify Bootstrap fixture exists
    bootstrap_path = File.expand_path('../test/fixtures/bootstrap.css', __dir__)
    raise "Bootstrap CSS fixture not found at #{bootstrap_path}" unless File.exist?(bootstrap_path)

    # Verify css_parser gem is available
    require 'css_parser'

    # Verify cataract works
    bootstrap_css = File.read(bootstrap_path)
    cataract_sheet = Cataract.parse_css(bootstrap_css)
    raise 'Cataract sanity check failed' if cataract_sheet.empty?
    raise 'Cataract serialization failed' if cataract_sheet.to_s.empty?
  end

  def call
    require_relative 'serialization_tests'

    worker_script = File.expand_path('benchmark_serialization_workers.rb', __dir__)

    # Clean up any leftover worker files from previous runs
    Dir.glob(File.join(RESULTS_DIR, 'serialization_*.json')).each { |f| FileUtils.rm_f(f) }

    puts 'Running serialization benchmarks via subprocesses...'
    puts 'Testing implementations with YJIT variations where applicable'
    puts

    # Define implementations to test
    implementations = [
      { name: 'css_parser gem', base_impl: :css_parser, env: { 'SERIALIZATION_CSS_PARSER' => '1' } },
      { name: 'Cataract pure Ruby', base_impl: :pure, env: { 'CATARACT_PURE' => '1' } },
      { name: 'Cataract C extension', base_impl: :native, env: { 'CATARACT_PURE' => nil } }
    ]

    implementations.each do |config|
      if SerializationTests.yjit_applicable?(config[:base_impl])
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

    # Show correctness comparison
    show_correctness_comparison
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
    all_results = read_worker_results('serialization_*.json')

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
    cleanup_worker_results('serialization_*.json')

    puts '=' * 80
    puts '✓ All serialization benchmarks complete'
    puts "Results saved to: #{combined_path}"
    puts '=' * 80
  end

  def show_correctness_comparison
    puts "\n#{'=' * 80}"
    puts 'CORRECTNESS VALIDATION'
    puts '=' * 80

    bootstrap_path = File.expand_path('../test/fixtures/bootstrap.css', __dir__)
    bootstrap_css = File.read(bootstrap_path)

    puts "Input: Bootstrap CSS (#{bootstrap_css.length} bytes)"

    # Parse with both libraries
    cataract_sheet = Cataract.parse_css(bootstrap_css)
    require 'css_parser'
    css_parser = CssParser::Parser.new
    css_parser.add_block!(bootstrap_css)

    # Serialize
    cataract_output = cataract_sheet.to_s
    css_parser_output = css_parser.to_s

    puts "Cataract output: #{cataract_output.length} bytes (#{cataract_sheet.size} rules)"
    puts "css_parser output: #{css_parser_output.length} bytes"

    # Basic sanity check - outputs should be similar in size
    size_ratio = cataract_output.length.to_f / css_parser_output.length
    unless size_ratio > 0.8 && size_ratio < 1.2
      puts "⚠️  Output sizes differ significantly (ratio: #{size_ratio.round(2)})"
    end

    # Check that output can be re-parsed
    begin
      reparsed = Cataract.parse_css(cataract_output)
      puts "Re-parsed output: #{reparsed.size} rules"
    rescue StandardError => e
      puts "❌ Failed to re-parse: #{e.message}"
      raise
    end
  end
end

# Run if executed directly
SerializationBenchmark.run if __FILE__ == $PROGRAM_NAME
