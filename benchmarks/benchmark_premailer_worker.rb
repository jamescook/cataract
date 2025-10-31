# frozen_string_literal: true

require_relative 'benchmark_harness'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# Worker benchmark for Premailer
# Controlled by USE_CATARACT env var
class PremailerWorkerBenchmark < BenchmarkHarness
  def self.benchmark_name
    use_cataract? ? 'premailer_cataract' : 'premailer_css_parser'
  end

  def self.description
    use_cataract? ? 'Premailer with Cataract shim' : 'Premailer with css_parser'
  end

  def self.metadata
    {
      'using_cataract' => use_cataract?
    }
  end

  # Override speedup_config - workers don't calculate speedups
  def self.speedup_config
    nil
  end

  def self.use_cataract?
    ENV['USE_CATARACT'] == '1'
  end

  def sanity_checks
    require 'premailer'

    # Set up shim if requested
    Cataract.mimic_CssParser! if use_cataract?

    # Verify fixture files exist
    fixtures_dir = File.expand_path('premailer_fixtures', __dir__)
    html_path = File.join(fixtures_dir, 'email.html')
    raise "HTML fixture not found: #{html_path}" unless File.exist?(html_path)

    # Restore if we set up shim
    Cataract.restore_CssParser! if use_cataract?
  end

  def call
    run_premailer_benchmark
  end

  private

  def use_cataract?
    self.class.use_cataract?
  end

  def run_premailer_benchmark
    fixtures_dir = File.expand_path('premailer_fixtures', __dir__)
    html_path = File.join(fixtures_dir, 'email.html')
    html_content = File.read(html_path)

    css_files = [
      File.join(fixtures_dir, 'base.css'),
      File.join(fixtures_dir, 'email.css')
    ]

    # Set up shim if requested
    Cataract.mimic_CssParser! if self.class.use_cataract?

    puts '=' * 80
    puts "TEST: Premailer email CSS inlining - #{self.class.use_cataract? ? 'Cataract' : 'css_parser'}"
    puts '=' * 80

    label = self.class.use_cataract? ? 'cataract' : 'css_parser'

    benchmark('email_inlining') do |x|
      x.config(time: 10, warmup: 3)

      x.report("#{label}: email_inlining") do
        premailer = Premailer.new(
          html_content,
          with_html_string: true,
          css: css_files,
          adapter: :nokogiri
        )
        premailer.to_inline_css
      end
    end

    # Restore if we set up shim
    Cataract.restore_CssParser! if self.class.use_cataract?
  end
end

# Run if executed directly
PremailerWorkerBenchmark.run if __FILE__ == $PROGRAM_NAME
