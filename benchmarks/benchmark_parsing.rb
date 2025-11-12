# frozen_string_literal: true

require_relative 'benchmark_harness'
require 'open3'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Parsing Performance Benchmark
# Compares css_parser gem vs Cataract pure Ruby vs Cataract C extension
class ParsingBenchmark < BenchmarkHarness
  def self.benchmark_name
    'parsing'
  end

  def self.description
    'Time to parse CSS into internal data structures'
  end

  def self.metadata
    require_relative 'parsing_tests'
    ParsingTests.metadata
  end

  def self.speedup_config
    require_relative 'parsing_tests'
    ParsingTests.speedup_config
  end

  def sanity_checks
    # Verify fixtures exist
    fixtures_dir = File.expand_path('../test/fixtures', __dir__)
    css1_path = File.join(fixtures_dir, 'css1_sample.css')
    css2_path = File.join(fixtures_dir, 'css2_sample.css')

    raise "CSS fixture not found: #{css1_path}" unless File.exist?(css1_path)
    raise "CSS fixture not found: #{css2_path}" unless File.exist?(css2_path)

    # Verify css_parser gem is available
    require 'css_parser'

    # Verify cataract works
    parser = Cataract::Stylesheet.new
    parser.add_block('body { color: red; }')
    raise 'Cataract sanity check failed' if parser.rules_count.zero?
  end

  def call
    require_relative 'parsing_tests'

    worker_script = File.expand_path('benchmark_parsing_workers.rb', __dir__)

    # Clean up any leftover worker files from previous runs
    Dir.glob(File.join(RESULTS_DIR, 'parsing_*.json')).each { |f| FileUtils.rm_f(f) }

    puts 'Running parsing benchmarks via subprocesses...'
    puts 'Testing implementations with YJIT variations where applicable'
    puts

    # Define implementations to test
    implementations = [
      { name: 'css_parser gem', base_impl: :css_parser, env: { 'PARSING_CSS_PARSER' => '1' } },
      { name: 'Cataract pure Ruby', base_impl: :pure, env: { 'CATARACT_PURE' => '1' } },
      { name: 'Cataract C extension', base_impl: :native, env: { 'CATARACT_PURE' => nil } }
    ]

    implementations.each do |config|
      if ParsingTests.yjit_applicable?(config[:base_impl])
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
    all_results = read_worker_results('parsing_*.json')

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
    cleanup_worker_results('parsing_*.json')

    puts '=' * 80
    puts '✓ All parsing benchmarks complete'
    puts "Results saved to: #{combined_path}"
    puts '=' * 80
  end

  def show_correctness_comparison
    puts "\n#{'=' * 80}"
    puts 'CORRECTNESS VALIDATION'
    puts '=' * 80

    fixtures_dir = File.expand_path('../test/fixtures', __dir__)
    css2 = File.read(File.join(fixtures_dir, 'css2_sample.css'))

    # Test Cataract
    parser = Cataract::Stylesheet.new
    parser.add_block(css2)
    cataract_rules = parser.rules_count
    puts "Cataract found #{cataract_rules} rules"

    # Test css_parser
    require 'css_parser'
    css_parser = CssParser::Parser.new(import: false, io_exceptions: false)
    css_parser.add_block!(css2)
    css_parser_rules = 0
    css_parser.each_selector { css_parser_rules += 1 }
    puts "css_parser found #{css_parser_rules} rules"

    unless cataract_rules == css_parser_rules
      puts '⚠️  Different number of rules parsed'
      puts '    Note: css_parser has a known bug with ::after pseudo-elements'
      puts '    (it concatenates them with previous rules instead of parsing separately)'
    end

    # Show sample output
    puts "\nSample Cataract output:"
    parser.select(&:selector?).first(5).each do |rule|
      puts "  #{rule.selector}: #{rule.declarations} (spec: #{rule.specificity})"
    end
  end
end

# Run if executed directly
ParsingBenchmark.run if __FILE__ == $PROGRAM_NAME
