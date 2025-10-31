# frozen_string_literal: true

require_relative 'benchmark_harness'
require 'open3'
require 'json'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# Premailer Benchmark Supervisor
# Spawns two subprocesses (css_parser vs Cataract) and combines results
class PremailerBenchmark < BenchmarkHarness
  def self.benchmark_name
    'premailer'
  end

  def self.description
    'Premailer email CSS inlining with css_parser vs Cataract'
  end

  def self.metadata
    fixtures_dir = File.expand_path('premailer_fixtures', __dir__)
    html_path = File.join(fixtures_dir, 'email.html')

    {
      'test_cases' => [
        {
          'name' => 'Email HTML with CSS inlining',
          'key' => 'email_inlining',
          'html_size' => File.size(html_path),
          'css_files' => 2
        }
      ],
      'note' => 'Measures real-world Premailer usage for email HTML generation'
    }
  end

  def self.speedup_config
    {
      baseline_matcher: SpeedupCalculator::Matchers.css_parser,
      comparison_matcher: SpeedupCalculator::Matchers.cataract,
      test_case_key: :key
    }
  end

  def sanity_checks
    require 'premailer'

    # Verify fixture files exist
    fixtures_dir = File.expand_path('premailer_fixtures', __dir__)
    html_path = File.join(fixtures_dir, 'email.html')
    base_css = File.join(fixtures_dir, 'base.css')
    email_css = File.join(fixtures_dir, 'email.css')

    raise "HTML fixture not found: #{html_path}" unless File.exist?(html_path)
    raise "Base CSS not found: #{base_css}" unless File.exist?(base_css)
    raise "Email CSS not found: #{email_css}" unless File.exist?(email_css)
  end

  def call
    worker_script = File.expand_path('benchmark_premailer_worker.rb', __dir__)

    # Clean up any leftover worker files from previous runs
    css_parser_path = File.join(RESULTS_DIR, 'premailer_css_parser.json')
    cataract_path = File.join(RESULTS_DIR, 'premailer_cataract.json')
    FileUtils.rm_f(css_parser_path)
    FileUtils.rm_f(cataract_path)

    puts 'Running Premailer benchmarks via subprocesses...'
    puts

    # Run with css_parser
    puts '→ Running with css_parser (baseline)...'
    stdout_css_parser, status_css_parser = run_subprocess([RbConfig.ruby, worker_script])
    unless status_css_parser.success?
      raise "Worker with css_parser failed:\n#{stdout_css_parser}"
    end

    puts stdout_css_parser
    puts

    # Run with Cataract
    puts '→ Running with Cataract shim...'
    stdout_cataract, status_cataract = run_subprocess(
      [RbConfig.ruby, worker_script],
      env: { 'USE_CATARACT' => '1' }
    )
    unless status_cataract.success?
      raise "Worker with Cataract failed:\n#{stdout_cataract}"
    end

    puts stdout_cataract
    puts

    # Combine results
    combine_worker_results
  end

  private

  def run_subprocess(command, env: {})
    stdout, stderr, status = Open3.capture3(env, *command)

    # Print stderr if present (warnings, etc)
    unless stderr.empty?
      puts "⚠️  stderr: #{stderr}"
    end

    [stdout, status]
  end

  def combine_worker_results
    css_parser_path = File.join(RESULTS_DIR, 'premailer_css_parser.json')
    cataract_path = File.join(RESULTS_DIR, 'premailer_cataract.json')

    # Check both files exist
    unless File.exist?(css_parser_path) && File.exist?(cataract_path)
      raise "Worker results not found:\n  #{css_parser_path}\n  #{cataract_path}"
    end

    # Read both JSON files
    css_parser_data = JSON.parse(File.read(css_parser_path))
    cataract_data = JSON.parse(File.read(cataract_path))

    # Combine into single benchmark result
    combined_data = {
      'name' => self.class.benchmark_name,
      'description' => self.class.description,
      'metadata' => self.class.metadata,
      'timestamp' => Time.now.iso8601,
      'results' => []
    }

    # Merge results from both workers
    combined_data['results'].concat(css_parser_data['results']) if css_parser_data['results']
    combined_data['results'].concat(cataract_data['results']) if cataract_data['results']

    # Calculate speedups using configured strategy
    config = self.class.speedup_config
    if config
      calculator = SpeedupCalculator.new(
        results: combined_data['results'],
        test_cases: combined_data['metadata']['test_cases'],
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
    File.delete(css_parser_path)
    File.delete(cataract_path)

    puts "✓ Combined results saved to #{combined_path}"
  end
end

# Run if executed directly
PremailerBenchmark.run if __FILE__ == $PROGRAM_NAME
