# frozen_string_literal: true

require 'test_helper'
require 'tempfile'
require 'fileutils'
require 'json'

class TestBenchmarkDocGenerator < Minitest::Test
  def setup
    # Use real fixtures we saved earlier
    @fixtures_dir = File.expand_path('fixtures/benchmarks', __dir__)

    # Create a temporary directory for results
    @temp_dir = Dir.mktmpdir
    @results_dir = File.join(@temp_dir, '.results')
    @output_path = File.join(@temp_dir, 'BENCHMARKS.md')
    FileUtils.mkdir_p(@results_dir)

    # Copy fixtures to temp results directory
    FileUtils.cp(File.join(@fixtures_dir, 'parsing_sample.json'), File.join(@results_dir, 'parsing.json'))
    FileUtils.cp(File.join(@fixtures_dir, 'yjit_sample.json'), File.join(@results_dir, 'yjit.json'))

    # Create minimal metadata.json
    metadata = {
      'ruby_description' => 'ruby 3.4.5 (test)',
      'cpu' => 'Test CPU',
      'memory' => '16GB',
      'os' => 'Test OS',
      'timestamp' => '2025-10-30T12:00:00Z'
    }
    File.write(File.join(@results_dir, 'metadata.json'), JSON.pretty_generate(metadata))

    # Load the generator
    require_relative '../scripts/generate_benchmarks_md'
  end

  def teardown
    # Clean up temp directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir
  end

  def test_generates_benchmarks_md
    generator = BenchmarkDocGenerator.new(results_dir: @results_dir, output_path: @output_path)
    generator.generate

    assert_path_exists @output_path, 'BENCHMARKS.md should be generated'

    content = File.read(@output_path)

    # Check basic structure
    assert_includes content, '# Performance Benchmarks'
    assert_includes content, '## Test Environment'
    assert_includes content, 'Test CPU'
    assert_includes content, '16GB'

    # Check parsing section exists
    assert_includes content, '## CSS Parsing'
    assert_includes content, 'css_parser'
    assert_includes content, 'Cataract'
    assert_includes content, 'faster'

    # Check YJIT section exists
    assert_includes content, '## YJIT Impact'
    assert_includes content, 'property access'
  end

  def test_handles_missing_benchmarks
    # Remove all benchmark files except metadata
    Dir.glob(File.join(@results_dir, '*.json')).each do |file|
      File.delete(file) unless file.end_with?('metadata.json')
    end

    generator = BenchmarkDocGenerator.new(results_dir: @results_dir, output_path: @output_path)

    # Should not crash with missing data, but will warn
    generator.generate

    # Verify no output file was created since there's no data
    refute_path_exists @output_path, 'BENCHMARKS.md should not be generated without data'
  end
end
