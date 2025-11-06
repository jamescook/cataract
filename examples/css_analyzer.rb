#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'css_analyzer/analyzer'

# CLI Interface
if __FILE__ == $PROGRAM_NAME
  options = {}

  OptionParser.new do |opts|
    opts.banner = 'Usage: css_analyzer.rb [options] URL_OR_FILE'
    opts.separator ''
    opts.separator 'Analyze CSS from a file, URL, or website:'
    opts.separator '  - Local file: css_analyzer.rb styles.css'
    opts.separator '  - CSS URL: css_analyzer.rb https://example.com/styles.css'
    opts.separator '  - Website: css_analyzer.rb https://example.com (analyzes all CSS)'
    opts.separator ''

    opts.on('-t', '--top N', Integer, 'Show top N properties (default: 20)') do |n|
      options[:top] = n
    end

    opts.on('-o', '--output FILE', 'Write report to FILE instead of stdout') do |file|
      options[:output] = file
    end

    opts.on('--use-shim', 'Use Cataract shim for css_parser (for Premailer)') do
      options[:use_shim] = true
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end.parse!

  # Check for ENV var to enable shim
  options[:use_shim] = true if ENV['CATARACT_SHIM']

  # Check for required argument
  if ARGV.empty?
    warn 'Error: No URL or file specified'
    warn 'Usage: css_analyzer.rb [options] URL_OR_FILE'
    exit 1
  end

  source = ARGV[0]

  # Run analyzer
  total_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  analyzer = CSSAnalyzer::Analyzer.new(source, options)

  analysis_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  analyzer.save_report

  # Output timing information to stderr
  total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - total_start
  analysis_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - analysis_start

  warn "\n=== Timing ==="
  if analyzer.timings[:fetch]
    warn "Fetch webpage: #{format('%.3f', analyzer.timings[:fetch])}s"
    warn "Premailer parse: #{format('%.3f', analyzer.timings[:premailer_parse])}s"
    warn "Cataract parse: #{format('%.3f', analyzer.timings[:cataract_parse])}s"
  end
  warn "Analysis & report: #{format('%.3f', analysis_time)}s"
  warn "Total: #{format('%.3f', total_time)}s"
end
